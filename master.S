#define __SFR_OFFSET 0x00
#include <avr/io.h>

#define GREEN_TIME 3
#define YELLOW_TIME 1
#define HOUR_SWITCH_MODE 0x19
#define HOUR_WAKE 0x00
#define YEL_D_MASK ((1<<4)|(1<<7))
#define YEL_B_MASK (1<<2)

.global main

.section .bss
last_switch: .byte 1

.section .text
main:
    RCALL twi_init
    RCALL uart_init
    LDI R16, 0b11111100
    OUT DDRD, R16
    LDI R16, 0b00001111
    OUT DDRB, R16
    IN R16, DDRC
    ANDI R16, ~(1<<0)
    OUT DDRC, R16
    IN R16, PORTC
    ORI R16, (1<<0)
    OUT PORTC, R16
    LDI R20, (1<<WGM01)
    OUT TCCR0A, R20

intersection_loop:
    RCALL log_time
    RCALL read_rtc
    MOV R16, R22
    ANDI R16, 0x3F
    RCALL check_night_hour
    
    IN R16, PINC
    ANDI R16, 1
    STS last_switch, R16
    
    CLR R18
    SBRS R16, 0
    LDI R18, 1
    
    EOR R17, R18
    TST R17
    BRNE execute_yellow
    RJMP normal_cycle

execute_yellow:
    LDI R16, YEL_D_MASK
    OUT PORTD, R16
    LDI R16, YEL_B_MASK
    OUT PORTB, R16
    RCALL delay_500ms
    TST R25
    BRNE intersection_loop
    CLR R16
    OUT PORTD, R16
    OUT PORTB, R16
    RCALL delay_500ms
    TST R25
    BRNE intersection_loop
    RJMP intersection_loop

normal_cycle:
    LDI R30, lo8(str_utara_siap)
    LDI R31, hi8(str_utara_siap)
    RCALL print_str_pm
    LDI R16, (1<<4)|(1<<6)
    OUT PORTD, R16
    LDI R16, (1<<1)
    OUT PORTB, R16
    LDI R18, YELLOW_TIME
    RCALL delay_seconds
    TST R25
    BREQ skip_abort_1
    RJMP intersection_loop
skip_abort_1:

    LDI R30, lo8(str_utara_hijau)
    LDI R31, hi8(str_utara_hijau)
    RCALL print_str_pm
    LDI R16, (1<<5)|(1<<6)
    OUT PORTD, R16
    LDI R16, (1<<1)
    OUT PORTB, R16
    LDI R23, GREEN_TIME
    RCALL print_countdown
    TST R25
    BREQ skip_abort_2
    RJMP intersection_loop
skip_abort_2:

    LDI R30, lo8(str_utara_kuning)
    LDI R31, hi8(str_utara_kuning)
    RCALL print_str_pm
    LDI R16, (1<<4)|(1<<6)
    OUT PORTD, R16
    LDI R16, (1<<1)
    OUT PORTB, R16
    LDI R18, YELLOW_TIME
    RCALL delay_seconds
    TST R25
    BREQ skip_abort_3
    RJMP intersection_loop
skip_abort_3:

    LDI R30, lo8(str_selatan_siap)
    LDI R31, hi8(str_selatan_siap)
    RCALL print_str_pm
    LDI R16, (1<<3)|(1<<7)
    OUT PORTD, R16
    LDI R16, (1<<1)
    OUT PORTB, R16
    LDI R18, YELLOW_TIME
    RCALL delay_seconds
    TST R25
    BREQ skip_abort_4
    RJMP intersection_loop
skip_abort_4:

    LDI R30, lo8(str_selatan_hijau)
    LDI R31, hi8(str_selatan_hijau)
    RCALL print_str_pm
    LDI R16, (1<<3)
    OUT PORTD, R16
    LDI R16, (1<<0)|(1<<1)
    OUT PORTB, R16
    LDI R23, GREEN_TIME
    RCALL print_countdown
    TST R25
    BREQ skip_abort_5
    RJMP intersection_loop
skip_abort_5:

    LDI R30, lo8(str_selatan_kuning)
    LDI R31, hi8(str_selatan_kuning)
    RCALL print_str_pm
    LDI R16, (1<<3)|(1<<7)
    OUT PORTD, R16
    LDI R16, (1<<1)
    OUT PORTB, R16
    LDI R18, YELLOW_TIME
    RCALL delay_seconds
    TST R25
    BREQ skip_abort_6
    RJMP intersection_loop
skip_abort_6:

    LDI R30, lo8(str_timur_siap)
    LDI R31, hi8(str_timur_siap)
    RCALL print_str_pm
    LDI R16, (1<<3)|(1<<6)
    OUT PORTD, R16
    LDI R16, (1<<2)
    OUT PORTB, R16
    LDI R18, YELLOW_TIME
    RCALL delay_seconds
    TST R25
    BREQ skip_abort_7
    RJMP intersection_loop
skip_abort_7:

    LDI R30, lo8(str_timur_hijau)
    LDI R31, hi8(str_timur_hijau)
    RCALL print_str_pm
    LDI R16, (1<<3)|(1<<6)
    OUT PORTD, R16
    LDI R16, (1<<3)
    OUT PORTB, R16
    LDI R23, GREEN_TIME
    RCALL print_countdown
    TST R25
    BREQ skip_abort_8
    RJMP intersection_loop
skip_abort_8:

    LDI R30, lo8(str_timur_kuning)
    LDI R31, hi8(str_timur_kuning)
    RCALL print_str_pm
    LDI R16, (1<<3)|(1<<6)
    OUT PORTD, R16
    LDI R16, (1<<2)
    OUT PORTB, R16
    LDI R18, YELLOW_TIME
    RCALL delay_seconds
    TST R25
    BREQ skip_abort_9
    RJMP intersection_loop
skip_abort_9:

    RJMP intersection_loop

check_abort_normal:
    CLR R25
    IN R16, PINC
    ANDI R16, 1
    LDS R17, last_switch
    CP R16, R17
    BREQ can_done
    LDI R25, 1
can_done:
    RET

check_night_hour:
    CPI R16, HOUR_SWITCH_MODE
    BRSH cnh_night
    CPI R16, HOUR_WAKE
    BRLO cnh_night
    CLR R17
    RET
cnh_night:
    LDI R17, 1
    RET

delay_500ms:
    CLR R25
    LDI R19, 50
    LDI R16, 155
    OUT OCR0A, R16
    LDI R16, (1<<CS02)|(1<<CS00)
    OUT TCCR0B, R16
d500_loop:
    CLR R16
    OUT TCNT0, R16
    LDI R16, (1<<OCF0A)
    OUT TIFR0, R16
d500_wait:
    RCALL check_abort_normal
    TST R25
    BRNE d500_abort
    IN R16, TIFR0
    SBRS R16, OCF0A
    RJMP d500_wait
    DEC R19
    BRNE d500_loop
d500_abort:
    CLR R16
    OUT TCCR0B, R16
    RET

delay_seconds:
    CLR R25
    TST R18
    BREQ delay_done
    LDI R19, 100
    LDI R16, 155
    OUT OCR0A, R16
    LDI R16, (1<<CS02)|(1<<CS00)
    OUT TCCR0B, R16
loop_10ms:
    CLR R16
    OUT TCNT0, R16
    LDI R16, (1<<OCF0A)
    OUT TIFR0, R16
wait_flag:
    RCALL check_abort_normal
    TST R25
    BRNE delay_abort
    IN R16, TIFR0
    SBRS R16, OCF0A
    RJMP wait_flag
    DEC R19
    BRNE loop_10ms
    DEC R18
    RJMP delay_seconds
delay_abort:
delay_done:
    CLR R16
    OUT TCCR0B, R16
    RET

print_str_pm:
    LPM R16, Z+
    TST R16
    BREQ psp_done
    RCALL uart_tx
    RJMP print_str_pm
psp_done:
    RET

print_countdown:
pcd_loop:
    TST R23
    BREQ pcd_done
    MOV R16, R23
    ORI R16, 0x30
    RCALL uart_tx
    LDI R16, ' '
    RCALL uart_tx
    PUSH R23
    LDI R18, 1
    RCALL delay_seconds
    POP R23
    TST R25
    BRNE pcd_done
    DEC R23
    RJMP pcd_loop
pcd_done:
    RET

twi_init:
    LDI R16, 0x48
    STS TWBR, R16
    CLR R16
    STS TWSR, R16
    RET

twi_start:
    LDI R16, (1<<TWINT)|(1<<TWSTA)|(1<<TWEN)
    STS TWCR, R16
wait_start:
    LDS R16, TWCR
    SBRS R16, TWINT
    RJMP wait_start
    RET

twi_stop:
    LDI R16, (1<<TWINT)|(1<<TWSTO)|(1<<TWEN)
    STS TWCR, R16
    RET

twi_write:
    STS TWDR, R18
    LDI R16, (1<<TWINT)|(1<<TWEN)
    STS TWCR, R16
wait_write:
    LDS R16, TWCR
    SBRS R16, TWINT
    RJMP wait_write
    RET

twi_read_ack:
    LDI R16, (1<<TWINT)|(1<<TWEN)|(1<<TWEA)
    STS TWCR, R16
wait_read_ack:
    LDS R16, TWCR
    SBRS R16, TWINT
    RJMP wait_read_ack
    LDS R18, TWDR
    RET

twi_read_nack:
    LDI R16, (1<<TWINT)|(1<<TWEN)
    STS TWCR, R16
wait_read_nack:
    LDS R16, TWCR
    SBRS R16, TWINT
    RJMP wait_read_nack
    LDS R18, TWDR
    RET

read_rtc:
    RCALL twi_start
    LDI R18, 0xD0
    RCALL twi_write
    LDI R18, 0x00
    RCALL twi_write
    RCALL twi_start
    LDI R18, 0xD1
    RCALL twi_write
    RCALL twi_read_ack
    MOV R20, R18
    RCALL twi_read_ack
    MOV R21, R18
    RCALL twi_read_nack
    MOV R22, R18
    RCALL twi_stop
    RET

uart_init:
    LDI R16, 0
    STS UBRR0H, R16
    LDI R16, 103
    STS UBRR0L, R16
    LDI R16, (1<<TXEN0)
    STS UCSR0B, R16
    LDI R16, (1<<UCSZ01)|(1<<UCSZ00)
    STS UCSR0C, R16
    RET

uart_tx:
    LDS R17, UCSR0A
    SBRS R17, UDRE0
    RJMP uart_tx
    STS UDR0, R16
    RET

bcd_to_ascii_tx:
    MOV R16, R18
    SWAP R16
    ANDI R16, 0x0F
    ORI R16, 0x30
    RCALL uart_tx
    MOV R16, R18
    ANDI R16, 0x0F
    ORI R16, 0x30
    RCALL uart_tx
    RET

log_time:
    RCALL read_rtc
    MOV R18, R22
    ANDI R18, 0x3F
    RCALL bcd_to_ascii_tx
    LDI R16, ':'
    RCALL uart_tx
    MOV R18, R21
    RCALL bcd_to_ascii_tx
    LDI R16, ':'
    RCALL uart_tx
    MOV R18, R20
    RCALL bcd_to_ascii_tx
    LDI R16, '\r'
    RCALL uart_tx
    LDI R16, '\n'
    RCALL uart_tx
    RET

str_utara_siap: .asciz "Utara: PERSIAPAN\r\n"
str_utara_hijau: .asciz "Utara: HIJAU - "
str_utara_kuning: .asciz "\r\nUtara: KUNING\r\n"

str_selatan_siap: .asciz "Selatan: PERSIAPAN\r\n"
str_selatan_hijau: .asciz "Selatan: HIJAU - "
str_selatan_kuning: .asciz "\r\nSelatan: KUNING\r\n"

str_timur_siap: .asciz "Timur: PERSIAPAN\r\n"
str_timur_hijau: .asciz "Timur: HIJAU - "
str_timur_kuning: .asciz "\r\nTimur: KUNING\r\n"
