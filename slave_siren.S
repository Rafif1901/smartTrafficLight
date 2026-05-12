/*
 * slave_siren.S — Ambulance Siren Detector, Slave Arduino (ATmega328P @ 16MHz)
 *
 * Goertzel algorithm, two bins: 800 Hz and 1500 Hz
 * Sample rate : 8000 Hz via Timer0 CTC
 * Window size : N = 100  → 12.5 ms per window
 * Siren model : Fast yelp, ~4 Hz alternation (250 ms/tone)
 *               Confirm after MIN_ALTS=3 clean tone alternations
 *
 * Coefficients (Q14 = coeff * 16384):
 *   800 Hz  k=10  coeff=1.618034  Q14=26510
 *   1500 Hz k=19  coeff=0.736249  Q14=12063
 *
 * Pins:
 *   PC0  ADC0   MAX4466 analog out
 *   PD2         INT pulse to Master (HIGH ~10ms = siren detected)
 *   PD0/PD1     UART RX/TX, 9600 baud
 *
 * Build:
 *   avr-gcc -mmcu=atmega328p -x assembler-with-cpp slave_siren.S -o slave_siren.elf
 *   avr-objcopy -O ihex slave_siren.elf slave_siren.hex
 */

#include <avr/io.h>

/* ── Constants ─────────────────────────────────────────────────────────────── */
#define UBRR_VAL          103
#define TIMER0_OCR        249
#define N_SAMPLES         100
#define COEFF_800         26510
#define COEFF_1500        12063
#define ENERGY_THRESH_LO  0xF080
#define ENERGY_THRESH_HI  0x02FA
#define WINDOWS_PER_TONE  20
#define TONE_MARGIN       8
#define MIN_ALTS          3
#define SILENCE_TIMEOUT   40
#define FSM_IDLE          0
#define FSM_TONE_A        1
#define FSM_TONE_B        2
#define FSM_CONFIRMED     3
#define INT_PIN           2

/* ── SRAM ──────────────────────────────────────────────────────────────────── */
.section .bss
sample_ready:   .byte 1
adc_raw:        .byte 1
fsm_state:      .byte 1
alt_count:      .byte 1
win_in_tone:    .byte 1
silence_cnt:    .byte 1
urx_state:      .byte 1
urx_tmp:        .byte 1

/* ── IVT ───────────────────────────────────────────────────────────────────── */
.section .text
.global main
.org 0x0000 ; RESET
    rjmp main
.org 0x001C ; TIMER0 COMPA
    rjmp isr_t0
.org 0x0024 ; USART RX
    rjmp isr_rx

/* ══════════════════════════════════════════════════════════════════════════════
   MAIN
   ══════════════════════════════════════════════════════════════════════════════ */
main:
    ldi  r16, hi8(RAMEND)
    out  _SFR_IO_ADDR(SPH), r16
    ldi  r16, lo8(RAMEND)
    out  _SFR_IO_ADDR(SPL), r16

    sbi  _SFR_IO_ADDR(DDRD),  INT_PIN
    cbi  _SFR_IO_ADDR(PORTD), INT_PIN

    /* UART */
    ldi  r16, hi8(UBRR_VAL)
    sts  UBRR0H, r16
    ldi  r16, lo8(UBRR_VAL)
    sts  UBRR0L, r16
    ldi  r16, (1<<RXEN0)|(1<<TXEN0)|(1<<RXCIE0)
    sts  UCSR0B, r16
    ldi  r16, (1<<UCSZ01)|(1<<UCSZ00)
    sts  UCSR0C, r16

    /* ADC: AVcc, left-adjust, ADC0, free-run, prescaler/128 */
    ldi  r16, (1<<REFS0)|(1<<ADLAR)
    sts  ADMUX, r16
    ldi  r16, (1<<ADEN)|(1<<ADATE)|(1<<ADPS2)|(1<<ADPS1)|(1<<ADPS0)
    sts  ADCSRA, r16
    ldi  r16, 0
    sts  ADCSRB, r16
    ldi  r16, (1<<ADC0D)
    sts  DIDR0, r16
    lds  r16, ADCSRA
    ori  r16, (1<<ADSC)
    sts  ADCSRA, r16

    /* Timer0 CTC 8kHz */
    ldi  r16, (1<<WGM01)
    out  _SFR_IO_ADDR(TCCR0A), r16
    ldi  r16, (1<<CS01)
    out  _SFR_IO_ADDR(TCCR0B), r16
    ldi  r16, TIMER0_OCR
    out  _SFR_IO_ADDR(OCR0A), r16
    ldi  r16, (1<<OCIE0A)
    sts  TIMSK0, r16

    /* Zero all working registers */
    clr  r2   /* sample_count lo */
    clr  r3   /* sample_count hi (unused but kept for clarity) */
    clr  r4   /* Q1_800  lo */
    clr  r5   /* Q1_800  hi */
    clr  r6   /* Q2_800  lo */
    clr  r7   /* Q2_800  hi */
    clr  r8   /* Q1_1500 lo */
    clr  r9   /* Q1_1500 hi */
    clr  r10  /* Q2_1500 lo */
    clr  r11  /* Q2_1500 hi */

    /* SRAM init */
    ldi  r16, FSM_IDLE
    sts  fsm_state,  r16
    clr  r16
    sts  alt_count,  r16
    sts  win_in_tone,r16
    sts  silence_cnt,r16
    sts  urx_state,  r16
    sts  urx_tmp,    r16

    sei

/* ── Poll loop ─────────────────────────────────────────────────────────────── */
main_loop:
    lds  r16, sample_ready
    tst  r16
    breq main_loop

    clr  r16
    sts  sample_ready, r16

    /* r24 = signed sample: ADCH - 128 */
    lds  r24, adc_raw
    subi r24, 128
    /* sign-extend into r25 for 16-bit add/sub operations */
    clr  r25
    sbrc r24, 7
    ldi  r25, 0xFF   /* r25 = 0xFF if sample negative, 0x00 if positive */

    rcall gi800
    rcall gi1500

    inc  r2
    mov  r16, r2
    cpi  r16, N_SAMPLES
    brne main_loop

    /* Window done */
    clr  r2

    rcall e800
    rcall threshold
    mov  r17, r16    /* r17 = active_800 */

    clr  r4
    clr  r5
    clr  r6
    clr  r7

    rcall e1500
    rcall threshold  /* r16 = active_1500 */

    clr  r8
    clr  r9
    clr  r10
    clr  r11

    rcall fsm        /* r17=active_800, r16=active_1500 */

    rjmp main_loop


/* ══════════════════════════════════════════════════════════════════════════════
   gi800 — Goertzel iteration, 800 Hz
   State: r4:r5=Q1, r6:r7=Q2  (lo:hi, signed 16-bit)
   Input: r24:r25 = signed 16-bit sample (prepared in main_loop above)
   Q0 = (COEFF*Q1 >> 14) - Q2 + sample;  Q2=Q1; Q1=Q0
   ══════════════════════════════════════════════════════════════════════════════
   16x16 signed multiply strategy:
     COEFF is always positive (fits in 15 bits), Q1 can be negative.
     1. Take |Q1|
     2. Unsigned 16x16 multiply: COEFF * |Q1| → 32-bit
     3. If Q1 was negative, negate the 32-bit result
     4. Arithmetic right-shift 14 → 16-bit term
     5. term - Q2 + sample
*/
gi800:
    /* |Q1_800| into r20:r21 */
    movw r20, r4        /* r21:r20 = Q1 lo:hi */
    sbrs r21, 7
    rjmp gi800_abs_ok
    clr  r22
    clr  r23
    sub  r22, r20
    sbc  r23, r21
    movw r20, r22
gi800_abs_ok:

    /* Load coeff r22:r23 */
    ldi  r22, lo8(COEFF_800)
    ldi  r23, hi8(COEFF_800)

    /* 16x16 unsigned multiply → r19:r18:r17:r16 */
    mul  r22, r20      /* Clo * Qlo */
    movw r16, r0
    clr  r18
    clr  r19

    mul  r22, r21      /* Clo * Qhi → add at offset+8 */
    add  r17, r0
    adc  r18, r1
    adc  r19, r25      /* r25=0 here (set in main_loop but safe) */

    mul  r23, r20      /* Chi * Qlo → add at offset+8 */
    add  r17, r0
    adc  r18, r1
    adc  r19, r25

    mul  r23, r21      /* Chi * Qhi → add at offset+16 */
    add  r18, r0
    adc  r19, r1

    /* Negate if Q1 was negative */
    sbrs r5, 7
    rjmp gi800_sign_ok
    clr  r20
    clr  r21
    clr  r22
    clr  r23
    sub  r20, r16
    sbc  r21, r17
    sbc  r22, r18
    sbc  r23, r19
    movw r16, r20
    movw r18, r22
gi800_sign_ok:

    /* >> 14: result_lo = (r17>>6)|(r18<<2), result_hi = (r18>>6)|(r19<<2) */
    mov  r20, r17
    lsr  r20
    lsr  r20
    lsr  r20
    lsr  r20
    lsr  r20
    lsr  r20
    mov  r22, r18
    lsl  r22
    lsl  r22
    or   r20, r22      /* term lo */

    mov  r21, r18
    lsr  r21
    lsr  r21
    lsr  r21
    lsr  r21
    lsr  r21
    lsr  r21
    mov  r22, r19
    lsl  r22
    lsl  r22
    or   r21, r22      /* term hi */

    /* Q0 = term - Q2 + sample (r24:r25 already sign-extended) */
    sub  r20, r6
    sbc  r21, r7
    add  r20, r24
    adc  r21, r25

    /* Q2=Q1, Q1=Q0 */
    movw r6, r4
    movw r4, r20

    clr  r1
    ret


/* ══════════════════════════════════════════════════════════════════════════════
   gi1500 — Goertzel iteration, 1500 Hz
   State: r8:r9=Q1, r10:r11=Q2
   Same algorithm as gi800 with COEFF_1500
*/
gi1500:
    movw r20, r8
    sbrs r21, 7
    rjmp gi1500_abs_ok
    clr  r22
    clr  r23
    sub  r22, r20
    sbc  r23, r21
    movw r20, r22
gi1500_abs_ok:

    ldi  r22, lo8(COEFF_1500)
    ldi  r23, hi8(COEFF_1500)

    mul  r22, r20
    movw r16, r0
    clr  r18
    clr  r19

    mul  r22, r21
    add  r17, r0
    adc  r18, r1
    adc  r19, r25

    mul  r23, r20
    add  r17, r0
    adc  r18, r1
    adc  r19, r25

    mul  r23, r21
    add  r18, r0
    adc  r19, r1

    sbrs r9, 7
    rjmp gi1500_sign_ok
    clr  r20
    clr  r21
    clr  r22
    clr  r23
    sub  r20, r16
    sbc  r21, r17
    sbc  r22, r18
    sbc  r23, r19
    movw r16, r20
    movw r18, r22
gi1500_sign_ok:

    mov  r20, r17
    lsr  r20
    lsr  r20
    lsr  r20
    lsr  r20
    lsr  r20
    lsr  r20
    mov  r22, r18
    lsl  r22
    lsl  r22
    or   r20, r22

    mov  r21, r18
    lsr  r21
    lsr  r21
    lsr  r21
    lsr  r21
    lsr  r21
    lsr  r21
    mov  r22, r19
    lsl  r22
    lsl  r22
    or   r21, r22

    sub  r20, r10
    sbc  r21, r11
    add  r20, r24
    adc  r21, r25

    movw r10, r8
    movw r8,  r20

    clr  r1
    ret


/* ══════════════════════════════════════════════════════════════════════════════
   sq16 — 16-bit unsigned square
   Input : r17:r16  (lo:hi)
   Output: r23:r22:r21:r20  (32-bit)
*/
sq16:
    mul  r16, r16      /* lo*lo */
    movw r20, r0
    clr  r22
    clr  r23

    mul  r16, r17      /* lo*hi (add twice for symmetric cross term) */
    add  r21, r0
    adc  r22, r1
    add  r21, r0
    adc  r22, r1
    adc  r23, r25      /* r25=0 always */

    mul  r17, r17      /* hi*hi */
    add  r22, r0
    adc  r23, r1

    clr  r1
    ret


/* ══════════════════════════════════════════════════════════════════════════════
   abs16i — absolute value of r17:r16, result in r17:r16
*/
abs16i:
    sbrs r17, 7
    ret
    clr  r18
    clr  r19
    sub  r18, r16
    sbc  r19, r17
    movw r16, r18
    ret


/* ══════════════════════════════════════════════════════════════════════════════
   e800 — energy for 800 Hz bin  ≈ Q1²+Q2²
   Output: r23:r22:r21:r20
*/
e800:
    movw r16, r4       /* Q1_800 */
    rcall abs16i
    rcall sq16         /* r23:r22:r21:r20 = Q1² */
    push r20
    push r21
    push r22
    push r23

    movw r16, r6       /* Q2_800 */
    rcall abs16i
    rcall sq16         /* r23:r22:r21:r20 = Q2² */

    pop  r19
    pop  r18
    pop  r17
    pop  r16           /* r19:r18:r17:r16 = Q1² */

    add  r20, r16
    adc  r21, r17
    adc  r22, r18
    adc  r23, r19
    ret


/* ══════════════════════════════════════════════════════════════════════════════
   e1500 — energy for 1500 Hz bin
*/
e1500:
    movw r16, r8
    rcall abs16i
    rcall sq16
    push r20
    push r21
    push r22
    push r23

    movw r16, r10
    rcall abs16i
    rcall sq16

    pop  r19
    pop  r18
    pop  r17
    pop  r16

    add  r20, r16
    adc  r21, r17
    adc  r22, r18
    adc  r23, r19
    ret


/* ══════════════════════════════════════════════════════════════════════════════
   threshold — compare 32-bit energy vs threshold
   Input : r23:r22:r21:r20
   Output: r16 = 1 if ≥ threshold, 0 otherwise
*/
threshold:
    ldi  r16, lo8(ENERGY_THRESH_LO)
    ldi  r17, hi8(ENERGY_THRESH_LO)
    ldi  r18, lo8(ENERGY_THRESH_HI)
    ldi  r19, hi8(ENERGY_THRESH_HI)
    cp   r20, r16
    cpc  r21, r17
    cpc  r22, r18
    cpc  r23, r19
    brcs thr_below
    ldi  r16, 1
    ret
thr_below:
    clr  r16
    ret


/* ══════════════════════════════════════════════════════════════════════════════
   fsm — siren pattern state machine
   Input : r17=active_800, r16=active_1500
   SRAM  : fsm_state, alt_count, win_in_tone, silence_cnt
*/
fsm:
    /* Determine dominant: 1=800Hz only, 2=1500Hz only, 0=none/both */
    clr  r18
    tst  r17
    breq fsm_check1500
    tst  r16
    brne fsm_no_dominant   /* both active = noise */
    ldi  r18, 1
    rjmp fsm_dispatch
fsm_check1500:
    tst  r16
    breq fsm_no_dominant
    ldi  r18, 2
    rjmp fsm_dispatch
fsm_no_dominant:
    clr  r18

fsm_dispatch:
    tst  r18
    brne  .+2
    rjmp  fsm_silence

    /* Tone active: reset silence counter */
    clr  r19
    sts  silence_cnt, r19

    lds  r16, fsm_state
    cpi  r16, FSM_IDLE
    breq fsm_idle
    cpi  r16, FSM_TONE_A
    breq fsm_tone_a
    cpi  r16, FSM_TONE_B
    breq fsm_tone_b
    /* FSM_CONFIRMED: stay until silence resets */
    rjmp fsm_done

fsm_idle:
    sts  fsm_state,   r18   /* latch first tone */
    clr  r19
    sts  win_in_tone, r19
    sts  alt_count,   r19
    rjmp fsm_done

fsm_tone_a:
    lds  r19, win_in_tone
    inc  r19
    sts  win_in_tone, r19
    cpi  r18, 1
    breq fsm_a_staying
    /* switched to 1500 Hz — check timing */
    cpi  r19, (WINDOWS_PER_TONE - TONE_MARGIN)
    brlo fsm_bad
    cpi  r19, (WINDOWS_PER_TONE + TONE_MARGIN + 1)
    brsh fsm_bad
    lds  r20, alt_count
    inc  r20
    sts  alt_count, r20
    ldi  r19, FSM_TONE_B
    sts  fsm_state,   r19
    clr  r19
    sts  win_in_tone, r19
    cpi  r20, MIN_ALTS
    brsh fsm_trigger
    rjmp fsm_done
fsm_a_staying:
    cpi  r19, (WINDOWS_PER_TONE + TONE_MARGIN + TONE_MARGIN + 1)
    brlo  .+2
    rjmp  fsm_reset
    rjmp fsm_done

fsm_tone_b:
    lds  r19, win_in_tone
    inc  r19
    sts  win_in_tone, r19
    cpi  r18, 2
    breq fsm_b_staying
    cpi  r19, (WINDOWS_PER_TONE - TONE_MARGIN)
    brlo fsm_bad
    cpi  r19, (WINDOWS_PER_TONE + TONE_MARGIN + 1)
    brsh fsm_bad
    lds  r20, alt_count
    inc  r20
    sts  alt_count, r20
    ldi  r19, FSM_TONE_A
    sts  fsm_state,   r19
    clr  r19
    sts  win_in_tone, r19
    cpi  r20, MIN_ALTS
    brsh fsm_trigger
    rjmp fsm_done
fsm_b_staying:
    cpi  r19, (WINDOWS_PER_TONE + TONE_MARGIN + TONE_MARGIN + 1)
    brsh fsm_reset
    rjmp fsm_done

fsm_silence:
    lds  r19, silence_cnt
    inc  r19
    sts  silence_cnt, r19
    cpi  r19, SILENCE_TIMEOUT
    brsh fsm_reset
    rjmp fsm_done

fsm_bad:
    /* bad timing: restart with current tone */
    sts  fsm_state,   r18
    clr  r19
    sts  win_in_tone, r19
    sts  alt_count,   r19
    rjmp fsm_done

fsm_reset:
    ldi  r19, FSM_IDLE
    sts  fsm_state,   r19
    clr  r19
    sts  alt_count,   r19
    sts  win_in_tone, r19
    sts  silence_cnt, r19
    cbi  _SFR_IO_ADDR(PORTD), INT_PIN
    rjmp fsm_done

fsm_trigger:
    ldi  r19, FSM_CONFIRMED
    sts  fsm_state, r19
    /* Pulse PD2 HIGH for ~10ms */
    sbi  _SFR_IO_ADDR(PORTD), INT_PIN
    ldi  r24, lo8(40000)
    ldi  r25, hi8(40000)
fsm_pulse:
    sbiw r24, 1
    brne fsm_pulse
    cbi  _SFR_IO_ADDR(PORTD), INT_PIN
    /* Restore r25=0 for sign-extension in main_loop */
    clr  r25
    rcall uart_siren

fsm_done:
    ret


/* ══════════════════════════════════════════════════════════════════════════════
   isr_t0 — Timer0 COMPA, fires at 8000 Hz
*/
isr_t0:
    push r16
    in   r16, _SFR_IO_ADDR(SREG)
    push r16
    lds  r16, ADCH
    sts  adc_raw, r16
    ldi  r16, 1
    sts  sample_ready, r16
    pop  r16
    out  _SFR_IO_ADDR(SREG), r16
    pop  r16
    reti


/* ══════════════════════════════════════════════════════════════════════════════
   isr_rx — USART RX, 3-byte config command from master
   0xA1 [lo] [hi] → (threshold update placeholder)
*/
isr_rx:
    push r16
    in   r16, _SFR_IO_ADDR(SREG)
    push r16
    push r17

    lds  r16, UDR0
    lds  r17, urx_state
    tst  r17
    breq urx_idle
    cpi  r17, 1
    breq urx_got_lo
    /* state=2: complete */
    clr  r17
    sts  urx_state, r17
    rjmp urx_done
urx_idle:
    cpi  r16, 0xA1
    brne urx_done
    ldi  r17, 1
    sts  urx_state, r17
    rjmp urx_done
urx_got_lo:
    sts  urx_tmp, r16
    ldi  r17, 2
    sts  urx_state, r17
urx_done:
    pop  r17
    pop  r16
    out  _SFR_IO_ADDR(SREG), r16
    pop  r16
    reti


/* ══════════════════════════════════════════════════════════════════════════════
   uart_siren — blocking transmit "SIREN\r\n"
*/
uart_siren:
    push r16
    push r17
    push r30
    push r31
    ldi  r30, lo8(pm(siren_msg))
    ldi  r31, hi8(pm(siren_msg))
    ldi  r17, 7
us_loop:
    lpm  r16, Z+
us_wait:
    lds  r18, UCSR0A
    sbrs r18, UDRE0
    rjmp us_wait
    sts  UDR0, r16
    dec  r17
    brne us_loop
    pop  r31
    pop  r30
    pop  r17
    pop  r16
    ret

siren_msg:
    .ascii "SIREN\r\n"
