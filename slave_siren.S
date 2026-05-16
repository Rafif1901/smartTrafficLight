/*
 * slave_siren.S — Ambulance Siren Detector, Slave Arduino
 * V2 - Stabilized Vector Table & Tuned Thresholds
 */

#include <avr/io.h>

/* ── Constants ─────────────────────────────────────────────────────────────── */
#define UBRR_VAL          103     // 9600 baud @ 16MHz
#define TIMER0_OCR        249     // 8000 Hz Target
#define N_SAMPLES         100     // 12.5ms window
#define COEFF_800         26510
#define COEFF_1500        12063

// Lowered Threshold for easier triggering
#define THRESH_LO_WORD    0x0070
#define THRESH_HI_WORD    0x0000  // 0x00700000

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

/* ── Text Section ──────────────────────────────────────────────────────────── */
.section .text
.global main

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

    /* ADC */
    ldi  r16, (1<<REFS0)|(1<<ADLAR)
    sts  ADMUX, r16
    ldi  r16, (1<<ADEN)|(1<<ADATE)|(1<<ADPS2)|(1<<ADPS1)|(1<<ADPS0)
    sts  ADCSRA, r16
    ldi  r16, 0
    sts  ADCSRB, r16
    lds  r16, ADCSRA
    ori  r16, (1<<ADSC)
    sts  ADCSRA, r16

    /* Timer0 */
    ldi  r16, (1<<WGM01)
    out  _SFR_IO_ADDR(TCCR0A), r16
    ldi  r16, (1<<CS01)
    out  _SFR_IO_ADDR(TCCR0B), r16
    ldi  r16, TIMER0_OCR
    out  _SFR_IO_ADDR(OCR0A), r16
    ldi  r16, (1<<OCIE0A)
    sts  TIMSK0, r16

    clr  r2
    clr  r3
    clr  r4
    clr  r5
    clr  r6
    clr  r7
    clr  r8
    clr  r9
    clr  r10
    clr  r11

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
    rcall e1500
    rcall threshold

    clr  r8
    clr  r9
    clr  r10
    clr  r11

    /* --- NEW DEBUG PRINTER --- */
    mov  r18, r16       // Save 1500Hz active flag to r18
    tst  r17            // Is 800Hz active?
    breq check_1500
    ldi  r16, 'A'       // If yes, print 'A'
    call uart_tx_char
    rjmp print_done

check_1500:
    tst  r18            // Is 1500Hz active?
    breq print_dot
    ldi  r16, 'B'       // If yes, print 'B'
    call uart_tx_char
    rjmp print_done

print_dot:
    ldi  r16, '.'       // If neither, print '.'
    call uart_tx_char

print_done:
    ldi  r16, '\r'
    call uart_tx_char
    ldi  r16, '\n'
    call uart_tx_char
    mov  r16, r18       // Restore 1500Hz active flag for the FSM
    /* ------------------------- */

    rcall fsm

    rjmp main_loop

uart_tx_char:
    push r17
1:  lds  r17, UCSR0A
    sbrs r17, UDRE0
    rjmp 1b
    sts  UDR0, r16
    pop  r17
    ret

/* ══════════════════════════════════════════════════════════════════════════════
   GOERTZEL & MATH SUBROUTINES
   (Your math logic remains completely untouched from V1)
   ══════════════════════════════════════════════════════════════════════════════ */
gi800:
    movw r20, r4
    sbrs r21, 7
    rjmp gi800_abs_ok
    clr  r22
    clr  r23
    sub  r22, r20
    sbc  r23, r21
    movw r20, r22
gi800_abs_ok:
    ldi  r22, lo8(COEFF_800)
    ldi  r23, hi8(COEFF_800)
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
    sub  r20, r6
    sbc  r21, r7
    add  r20, r24
    adc  r21, r25
    movw r6, r4
    movw r4, r20
    clr  r1
    ret

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

sq16:
    mul  r16, r16
    movw r20, r0
    clr  r22
    clr  r23
    mul  r16, r17
    add  r21, r0
    adc  r22, r1
    add  r21, r0
    adc  r22, r1
    adc  r23, r25
    mul  r17, r17
    add  r22, r0
    adc  r23, r1
    clr  r1
    ret

abs16i:
    sbrs r17, 7
    ret
    clr  r18
    clr  r19
    sub  r18, r16
    sbc  r19, r17
    movw r16, r18
    ret

e800:
    movw r16, r4
    rcall abs16i
    rcall sq16
    push r20
    push r21
    push r22
    push r23
    movw r16, r6
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

/* UPDATED THRESHOLD COMPARISON */
threshold:
    ldi  r16, lo8(THRESH_LO_WORD)
    ldi  r17, hi8(THRESH_LO_WORD)
    ldi  r18, lo8(THRESH_HI_WORD)
    ldi  r19, hi8(THRESH_HI_WORD)
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
   STATE MACHINE
   ══════════════════════════════════════════════════════════════════════════════ */
fsm:
    clr  r18
    tst  r17
    breq fsm_check1500
    tst  r16
    brne fsm_no_dominant
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
    clr  r19
    sts  silence_cnt, r19
    lds  r16, fsm_state
    cpi  r16, FSM_IDLE
    breq fsm_idle
    cpi  r16, FSM_TONE_A
    breq fsm_tone_a
    cpi  r16, FSM_TONE_B
    breq fsm_tone_b
    rjmp fsm_done
fsm_idle:
    sts  fsm_state,   r18
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
    sbi  _SFR_IO_ADDR(PORTD), INT_PIN
    ldi  r24, lo8(40000)
    ldi  r25, hi8(40000)
fsm_pulse:
    sbiw r24, 1
    brne fsm_pulse
    cbi  _SFR_IO_ADDR(PORTD), INT_PIN
    clr  r25
    rcall uart_siren
fsm_done:
    ret

/* ══════════════════════════════════════════════════════════════════════════════
   INTERRUPTS & HARDWARE COMMUNICATION
   ══════════════════════════════════════════════════════════════════════════════ */
.global TIMER0_COMPA_vect
TIMER0_COMPA_vect:
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

.global USART_RX_vect
USART_RX_vect:
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
