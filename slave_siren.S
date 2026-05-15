#define __SFR_OFFSET 0x00
#include <avr/io.h>

/* --- Konstanta Sistem (Format Desimal) --- */
#define UBRR_VAL          103
#define TIMER0_OCR        249
#define N_SAMPLES         100
#define COEFF_800         26510
#define COEFF_1500        12063
#define ENERGY_THRESH_LO  61568    /* Ekuivalen dengan 0xF080 */
#define ENERGY_THRESH_HI  762      /* Ekuivalen dengan 0x02FA */
#define WINDOWS_PER_TONE  20
#define TONE_MARGIN       8
#define MIN_ALTS          3
#define SILENCE_TIMEOUT   40
#define FSM_IDLE          0
#define FSM_TONE_A        1
#define FSM_TONE_B        2
#define FSM_CONFIRMED     3
#define INT_PIN           2

.section .bss
/* --- Variabel SRAM --- */
sample_ready:   .byte 1
adc_raw:        .byte 1
fsm_state:      .byte 1
alt_count:      .byte 1
win_in_tone:    .byte 1
silence_cnt:    .byte 1
urx_state:      .byte 1
urx_tmp:        .byte 1

.section .text
.global main

/* --- Vector Table Interupsi --- */
.org 0
    rjmp main
.org 28                        /* Alamat 0x001C: TIMER0 COMPA */
    rjmp isr_t0
.org 36                        /* Alamat 0x0024: USART RX */
    rjmp isr_rx

/* --- Inisialisasi Utama --- */
main:
    ldi  r16, hi8(RAMEND)
    out  SPH, r16
    ldi  r16, lo8(RAMEND)
    out  SPL, r16

    sbi  DDRD, INT_PIN         /* Konfigurasi PD2 sebagai Output Interupsi ke Master */
    cbi  PORTD, INT_PIN

    /* Inisialisasi UART (Baud 9600) */
    ldi  r16, hi8(UBRR_VAL)
    sts  UBRR0H, r16
    ldi  r16, lo8(UBRR_VAL)
    sts  UBRR0L, r16
    ldi  r16, 0b10011000       /* Mengaktifkan RXEN0, TXEN0, dan RXCIE0 */
    sts  UCSR0B, r16
    ldi  r16, 0b00000110       /* Format 8-bit data, 1 stop bit */
    sts  UCSR0C, r16

    /* Inisialisasi ADC (Free-run, Prescaler 128) */
    ldi  r16, 0b01100000       /* Mengaktifkan Vref AVcc (REFS0) dan Left Adjust (ADLAR) */
    sts  ADMUX, r16
    ldi  r16, 0b10100111       /* Mengaktifkan ADEN, ADATE, ADPS2, ADPS1, ADPS0 */
    sts  ADCSRA, r16
    ldi  r16, 0b00000000       /* Auto-trigger di set ke Free Running Mode */
    sts  ADCSRB, r16
    ldi  r16, 0b00000001       /* Mematikan buffer digital di pin ADC0 (Hemat daya) */
    sts  DIDR0, r16
    lds  r16, ADCSRA
    ori  r16, 0b01000000       /* Menyuntikkan bit ADSC untuk memulai konversi ADC pertama */
    sts  ADCSRA, r16

    /* Inisialisasi Timer0 (Mode CTC, 8000 Hz) */
    ldi  r16, 0b00000010       /* Mengaktifkan bit WGM01 untuk Mode CTC */
    out  TCCR0A, r16
    ldi  r16, 0b00000010       /* Mengaktifkan Prescaler 8 melalui bit CS01 */
    out  TCCR0B, r16
    ldi  r16, TIMER0_OCR
    out  OCR0A, r16
    ldi  r16, 0b00000010       /* Mengaktifkan interupsi OCIE0A */
    sts  TIMSK0, r16

    /* Bersihkan register kerja Goertzel */
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

    /* Atur state machine ke mode awal */
    ldi  r16, FSM_IDLE
    sts  fsm_state,  r16
    clr  r16
    sts  alt_count,  r16
    sts  win_in_tone,r16
    sts  silence_cnt,r16
    sts  urx_state,  r16
    sts  urx_tmp,    r16

    sei                        /* Izinkan sistem menerima interupsi */

/* --- Loop Pemrosesan Polling --- */
main_loop:
    lds  r16, sample_ready
    tst  r16
    breq main_loop             /* Tahan di sini hingga ADC selesai mengambil sampel */

    clr  r16
    sts  sample_ready, r16

    lds  r24, adc_raw
    subi r24, 128              /* Menggeser referensi amplitudo gelombang ADC ke titik tengah */
    clr  r25
    sbrc r24, 7
    ldi  r25, 255              /* Operasi Sign-extension untuk bilangan negatif */

    rcall gi800
    rcall gi1500

    inc  r2
    mov  r16, r2
    cpi  r16, N_SAMPLES
    brne main_loop             /* Kembali ke atas jika belum mencapai 100 sampel */

    /* Evaluasi hasil sampel (Window selesai) */
    clr  r2

    rcall e800
    rcall threshold
    mov  r17, r16              /* r17 menyimpan hasil deteksi aktif 800 Hz */

    clr  r4
    clr  r5
    clr  r6
    clr  r7

    rcall e1500
    rcall threshold            /* r16 menyimpan hasil deteksi aktif 1500 Hz */

    clr  r8
    clr  r9
    clr  r10
    clr  r11

    rcall fsm                  /* Periksa kecocokan pola bunyi sirene dengan State Machine */

    rjmp main_loop

/* --- Eksekusi Algoritma Goertzel untuk Frekuensi 800 Hz --- */
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

/* --- Eksekusi Algoritma Goertzel untuk Frekuensi 1500 Hz --- */
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

/* --- Subrutin Utilitas Pemangkatan (Kuadrat 16-bit) --- */
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

/* --- Subrutin Pengubahan ke Nilai Mutlak --- */
abs16i:
    sbrs r17, 7
    ret
    clr  r18
    clr  r19
    sub  r18, r16
    sbc  r19, r17
    movw r16, r18
    ret

/* --- Kalkulasi Spektrum Energi (800 Hz) --- */
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

/* --- Kalkulasi Spektrum Energi (1500 Hz) --- */
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

/* --- Pembanding Energi Terhadap Ambang Batas --- */
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

/* --- Mesin Logika Pembaca Pola Suara Ambulans --- */
fsm:
    clr  r18
    tst  r17
    breq fsm_check1500
    tst  r16
    brne fsm_no_dominant       /* Suara dianggap bising/noise jika kedua frekuensi aktif bersamaan */
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
    cbi  PORTD, INT_PIN
    rjmp fsm_done

fsm_trigger:
    ldi  r19, FSM_CONFIRMED
    sts  fsm_state, r19
    sbi  PORTD, INT_PIN        /* Mengirimkan pulsa tegangan interupsi ke Master */
    ldi  r24, lo8(40000)
    ldi  r25, hi8(40000)
fsm_pulse:
    sbiw r24, 1
    brne fsm_pulse
    cbi  PORTD, INT_PIN
    clr  r25
    rcall uart_siren

fsm_done:
    ret

/* --- Rutin Interupsi (Timer0): Sampling ADC 8000 Hz --- */
isr_t0:
    push r16
    in   r16, SREG
    push r16
    lds  r16, ADCH             /* Segera ambil hasil ADC terbaru tanpa menunggu loop utama */
    sts  adc_raw, r16
    ldi  r16, 1
    sts  sample_ready, r16
    pop  r16
    out  SREG, r16
    pop  r16
    reti

/* --- Rutin Interupsi (UART): Menerima Data --- */
isr_rx:
    push r16
    in   r16, SREG
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
    cpi  r16, 161              /* Membaca byte awal (Ekuivalen dengan 0xA1) */
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
    out  SREG, r16
    pop  r16
    reti

/* --- Subrutin Kirim Pesan Sirene via UART --- */
uart_siren:
    push r16
    push r17
    push r30
    push r31
    ldi  r30, lo8(siren_msg)
    ldi  r31, hi8(siren_msg)
    ldi  r17, 7
us_loop:
    lpm  r16, Z+
us_wait:
    lds  r18, UCSR0A
    sbrs r18, 5                /* Pastikan buffer transmisi (UDRE0) siap menampung data */
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