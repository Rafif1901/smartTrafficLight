#define __SFR_OFFSET 0x00
#include <avr/io.h>

/* --- Konstanta Sistem (Format Desimal) --- */
#define GREEN_TIME 3
#define YELLOW_TIME 1
#define HOUR_SWITCH_MODE 0x19    /* (Jam 19:00) */
#define HOUR_WAKE 0
#define YEL_D_MASK 0b10010000  /* Mask untuk PD4 dan PD7 */
#define YEL_B_MASK 0b00000100  /* Mask untuk PB2 */

.global main
.global INT0_vect

.section .bss
siren_flag: .byte 1
last_switch: .byte 1

.section .text
/* --- Vector Table Interupsi --- */
.org 0x0000
    rjmp main
.org 0x0002
    rjmp isr_int0

/* --- Inisialisasi Sistem --- */
main:
    rcall twi_init
    rcall uart_init
    
    ldi r16, 0b11111100        /* Set PD2-PD7 sebagai output */
    out DDRD, r16
    ldi r16, 0b00001111        /* Set PB0-PB3 sebagai output */
    out DDRB, r16
    
    in r16, DDRC
    andi r16, 0b11111110       /* Set PC0 sebagai input */
    out DDRC, r16
    in r16, PORTC
    ori r16, 0b00000001        /* Aktifkan pull-up PC0 */
    out PORTC, r16
    
    ldi r16, 0b00000010        /* Timer0 Mode CTC */
    out TCCR0A, r16

    ldi r16, 0b00000011        /* Trigger INT0 pada Rising Edge */
    sts EICRA, r16
    ldi r16, 0b00000001        /* Aktifkan External Interrupt 0 */
    out EIMSK, r16
    clr r16
    sts siren_flag, r16
    sei                        /* Aktifkan interupsi global */

/* --- Loop Utama: Pengatur Prioritas --- */
intersection_loop:
    rcall log_time
    lds r16, siren_flag
    cpi r16, 1
    brne skip_siren
    rjmp do_siren_mode         /* Prioritas 1: Sirene Ambulans */
skip_siren:

    rcall read_rtc
    mov r16, r22
    andi r16, 63               /* Masking bit jam (0x3F = 63) */
    rcall check_night_hour
    
    in r16, PINC
    andi r16, 1
    sts last_switch, r16       /* Simpan status saklar terakhir */
    
    clr r18
    sbrs r16, 0
    ldi r18, 1
    
    eor r17, r18               /* Logika XOR untuk toggle mode malam/normal */
    tst r17
    brne execute_yellow        /* Prioritas 2/3: Mode Kuning Berkedip */
    rjmp normal_cycle          /* Prioritas 4: Siklus Normal */

/* --- Subrutin Mode Darurat Sirene --- */
do_siren_mode:
    ldi r16, 0b01001000        /* Semua merah (PD3, PD6) */
    out PORTD, r16
    ldi r16, 0b00000010        /* Merah Timur (PB1) */
    out PORTB, r16
    ldi r20, 50
siren_wait:
    rcall delay_100ms
    dec r20
    brne siren_wait
    clr r16
    sts siren_flag, r16
    rjmp intersection_loop

/* --- Mode Kuning Berkedip --- */
execute_yellow:
    ldi r16, YEL_D_MASK
    out PORTD, r16
    ldi r16, YEL_B_MASK
    out PORTB, r16
    rcall delay_500ms
    tst r25
    brne intersection_loop
    clr r16
    out PORTD, r16
    out PORTB, r16
    rcall delay_500ms
    tst r25
    brne intersection_loop
    rjmp intersection_loop

/* --- Siklus Normal Lampu Pertigaan --- */
normal_cycle:
    /* Utara Persiapan */
    ldi r30, lo8(str_utara_siap)
    ldi r31, hi8(str_utara_siap)
    rcall print_str_pm
    ldi r16, 0b01010000
    out PORTD, r16
    ldi r16, 0b00000010
    out PORTB, r16
    ldi r18, YELLOW_TIME
    rcall delay_seconds
    tst r25
    breq skip_abort_1
    rjmp intersection_loop
skip_abort_1:

    /* Utara Hijau */
    ldi r30, lo8(str_utara_hijau)
    ldi r31, hi8(str_utara_hijau)
    rcall print_str_pm
    ldi r16, 0b01100000
    out PORTD, r16
    ldi r16, 0b00000010
    out PORTB, r16
    ldi r23, GREEN_TIME
    rcall print_countdown
    tst r25
    breq skip_abort_2
    rjmp intersection_loop
skip_abort_2:

    /* Utara Kuning */
    ldi r30, lo8(str_utara_kuning)
    ldi r31, hi8(str_utara_kuning)
    rcall print_str_pm
    ldi r16, 0b01010000
    out PORTD, r16
    ldi r16, 0b00000010
    out PORTB, r16
    ldi r18, YELLOW_TIME
    rcall delay_seconds
    tst r25
    breq skip_abort_3
    rjmp intersection_loop
skip_abort_3:

    /* Selatan Persiapan */
    ldi r30, lo8(str_selatan_siap)
    ldi r31, hi8(str_selatan_siap)
    rcall print_str_pm
    ldi r16, 0b10001000
    out PORTD, r16
    ldi r16, 0b00000010
    out PORTB, r16
    ldi r18, YELLOW_TIME
    rcall delay_seconds
    tst r25
    breq skip_abort_4
    rjmp intersection_loop
skip_abort_4:

    /* Selatan Hijau */
    ldi r30, lo8(str_selatan_hijau)
    ldi r31, hi8(str_selatan_hijau)
    rcall print_str_pm
    ldi r16, 0b01001000
    out PORTD, r16
    ldi r16, 0b00000011
    out PORTB, r16
    ldi r23, GREEN_TIME
    rcall print_countdown
    tst r25
    breq skip_abort_5
    rjmp intersection_loop
skip_abort_5:

    /* Selatan Kuning */
    ldi r30, lo8(str_selatan_kuning)
    ldi r31, hi8(str_selatan_kuning)
    rcall print_str_pm
    ldi r16, 0b10001000
    out PORTD, r16
    ldi r16, 0b00000010
    out PORTB, r16
    ldi r18, YELLOW_TIME
    rcall delay_seconds
    tst r25
    breq skip_abort_6
    rjmp intersection_loop
skip_abort_6:

    /* Timur Persiapan */
    ldi r30, lo8(str_timur_siap)
    ldi r31, hi8(str_timur_siap)
    rcall print_str_pm
    ldi r16, 0b01001000
    out PORTD, r16
    ldi r16, 0b00000100
    out PORTB, r16
    ldi r18, YELLOW_TIME
    rcall delay_seconds
    tst r25
    breq skip_abort_7
    rjmp intersection_loop
skip_abort_7:

    /* Timur Hijau */
    ldi r30, lo8(str_timur_hijau)
    ldi r31, hi8(str_timur_hijau)
    rcall print_str_pm
    ldi r16, 0b01001000
    out PORTD, r16
    ldi r16, 0b00001000
    out PORTB, r16
    ldi r23, GREEN_TIME
    rcall print_countdown
    tst r25
    breq skip_abort_8
    rjmp intersection_loop
skip_abort_8:

    /* Timur Kuning */
    ldi r30, lo8(str_timur_kuning)
    ldi r31, hi8(str_timur_kuning)
    rcall print_str_pm
    ldi r16, 0b01001000
    out PORTD, r16
    ldi r16, 0b00000100
    out PORTB, r16
    ldi r18, YELLOW_TIME
    rcall delay_seconds
    tst r25
    breq skip_abort_9
    rjmp intersection_loop
skip_abort_9:

    rjmp intersection_loop

/* --- Fungsi Deteksi Perubahan Saklar --- */
check_abort_normal:
    clr r25
    in r16, PINC
    andi r16, 1
    lds r17, last_switch
    cp r16, r17
    breq can_done
    ldi r25, 1                 /* Set flag abort jika saklar berubah */
can_done:
    ret

/* --- Fungsi Cek Jam Malam --- */
check_night_hour:
    cpi r16, HOUR_SWITCH_MODE
    brsh cnh_night
    cpi r16, HOUR_WAKE
    brlo cnh_night
    clr r17
    ret
cnh_night:
    ldi r17, 1
    ret

/* --- Fungsi Delay 500ms --- */
delay_500ms:
    clr r25
    ldi r19, 50
    ldi r16, 155
    out OCR0A, r16
    ldi r16, 0b00000101        /* Prescaler 1024 */
    out TCCR0B, r16
d500_loop:
    clr r16
    out TCNT0, r16
    ldi r16, 0b00000010        /* Clear OCF0A flag */
    out TIFR0, r16
d500_wait:
    rcall check_abort_normal
    tst r25
    brne d500_abort
    in r16, TIFR0
    sbrs r16, 1
    rjmp d500_wait
    dec r19
    brne d500_loop
d500_abort:
    clr r16
    out TCCR0B, r16
    ret

/* --- Fungsi Delay Detik --- */
delay_seconds:
    clr r25
    tst r18
    breq delay_done
    ldi r19, 100               /* 100 * 10ms = 1 detik */
    ldi r16, 155
    out OCR0A, r16
    ldi r16, 0b00000101
    out TCCR0B, r16
loop_10ms:
    clr r16
    out TCNT0, r16
    ldi r16, 0b00000010
    out TIFR0, r16
wait_flag:
    rcall check_abort_normal
    tst r25
    brne delay_abort
    in r16, TIFR0
    sbrs r16, 1
    rjmp wait_flag
    dec r19
    brne loop_10ms
    dec r18
    rjmp delay_seconds
delay_abort:
delay_done:
    clr r16
    out TCCR0B, r16
    ret

/* --- Fungsi Delay 100ms --- */
delay_100ms:
    ldi r21, 100
d1: ldi r22, 200
d2: ldi r23, 20
d3: dec r23
    brne d3
    dec r22
    brne d2
    dec r21
    brne d1
    ret

/* --- Fungsi Cetak String Flash --- */
print_str_pm:
    lpm r16, Z+
    tst r16
    breq psp_done
    rcall uart_tx
    rjmp print_str_pm
psp_done:
    ret

/* --- Fungsi Hitung Mundur Serial --- */
print_countdown:
pcd_loop:
    tst r23
    breq pcd_done
    mov r16, r23
    ori r16, 48                /* Konversi ke ASCII ('0' = 48) */
    rcall uart_tx
    ldi r16, 32                /* Karakter spasi (ASCII 32) */
    rcall uart_tx
    push r23
    ldi r18, 1
    rcall delay_seconds
    pop r23
    tst r25
    brne pcd_done
    dec r23
    rjmp pcd_loop
pcd_done:
    ret

/* --- Konfigurasi TWI/I2C --- */
twi_init:
    ldi r16, 72                /* Kecepatan 100kHz pada 16MHz */
    sts TWBR, r16
    clr r16
    sts TWSR, r16
    ret

twi_start:
    ldi r16, 0b10100100        /* TWINT, TWSTA, TWEN */
    sts TWCR, r16
wait_start:
    lds r16, TWCR
    sbrs r16, 7
    rjmp wait_start
    ret

twi_stop:
    ldi r16, 0b10010100        /* TWINT, TWSTO, TWEN */
    sts TWCR, r16
    ret

twi_write:
    sts TWDR, r18
    ldi r16, 0b10000100        /* TWINT, TWEN */
    sts TWCR, r16
wait_write:
    lds r16, TWCR
    sbrs r16, 7
    rjmp wait_write
    ret

twi_read_ack:
    ldi r16, 0b11000100        /* TWINT, TWEN, TWEA */
    sts TWCR, r16
wait_read_ack:
    lds r16, TWCR
    sbrs r16, 7
    rjmp wait_read_ack
    lds r18, TWDR
    ret

twi_read_nack:
    ldi r16, 0b10000100        /* TWINT, TWEN */
    sts TWCR, r16
wait_read_nack:
    lds r16, TWCR
    sbrs r16, 7
    rjmp wait_read_nack
    lds r18, TWDR
    ret

/* --- Baca Data Waktu RTC --- */
read_rtc:
    rcall twi_start
    ldi r18, 208               /* Alamat tulis DS3231 (0xD0) */
    rcall twi_write
    ldi r18, 0
    rcall twi_write
    rcall twi_start
    ldi r18, 209               /* Alamat baca DS3231 (0xD1) */
    rcall twi_write
    rcall twi_read_ack
    mov r20, r18               /* Detik */
    rcall twi_read_ack
    mov r21, r18               /* Menit */
    rcall twi_read_nack
    mov r22, r18               /* Jam */
    rcall twi_stop
    ret

/* --- Konfigurasi UART --- */
uart_init:
    ldi r16, 0
    sts UBRR0H, r16
    ldi r16, 103               /* 9600 Baud pada 16MHz */
    sts UBRR0L, r16
    ldi r16, 0b00001000        /* Aktifkan Transmitter (TXEN0) */
    sts UCSR0B, r16
    ldi r16, 0b00000110        /* 8-bit data, 1 stop bit */
    sts UCSR0C, r16
    ret

uart_tx:
    lds r17, UCSR0A
    sbrs r17, 5                /* Tunggu buffer UDR0 kosong (UDRE0) */
    rjmp uart_tx
    sts UDR0, r16
    ret

bcd_to_ascii_tx:
    mov r16, r18
    swap r16
    andi r16, 15
    ori r16, 48
    rcall uart_tx
    mov r16, r18
    andi r16, 15
    ori r16, 48
    rcall uart_tx
    ret

log_time:
    rcall read_rtc
    mov r18, r22
    andi r18, 63
    rcall bcd_to_ascii_tx
    ldi r16, 58                /* ':' ASCII */
    rcall uart_tx
    mov r18, r21
    rcall bcd_to_ascii_tx
    ldi r16, 58
    rcall uart_tx
    mov r18, r20
    rcall bcd_to_ascii_tx
    ldi r16, 13                /* Carriage Return */
    rcall uart_tx
    ldi r16, 10                /* Line Feed */
    rcall uart_tx
    ret

/* --- Rutin Interupsi Eksternal INT0 --- */
isr_int0:
    push r16
    in r16, SREG
    push r16
    ldi r16, 1
    sts siren_flag, r16
    pop r16
    out SREG, r16
    pop r16
    reti

/* --- Data Teks di Flash Memory --- */
str_utara_siap: .asciz "Utara: PERSIAPAN\r\n"
str_utara_hijau: .asciz "Utara: HIJAU - "
str_utara_kuning: .asciz "\r\nUtara: KUNING\r\n"

str_selatan_siap: .asciz "Selatan: PERSIAPAN\r\n"
str_selatan_hijau: .asciz "Selatan: HIJAU - "
str_selatan_kuning: .asciz "\r\nSelatan: KUNING\r\n"

str_timur_siap: .asciz "Timur: PERSIAPAN\r\n"
str_timur_hijau: .asciz "Timur: HIJAU - "
str_timur_kuning: .asciz "\r\nTimur: KUNING\r\n"