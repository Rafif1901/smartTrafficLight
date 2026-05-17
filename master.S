#define __SFR_OFFSET 0x00
#include <avr/io.h>

#define GREEN_TIME 3
#define YELLOW_TIME 1
#define YEL_D_MASK ((1<<4)|(1<<7))
#define YEL_B_MASK (1<<2)

.global main
.global INT0_vect
.global USART_RX_vect

.section .bss
siren_flag: .byte 1
last_switch: .byte 1

/* UART data */
rx_buf: .space 16
rx_idx: .byte 1
parse_flag: .byte 1
standby_time: .space 3   /* HH, MM, SS in BCD */
op_time: .space 3        /* HH, MM, SS in BCD */

.section .text

main:
    RCALL twi_init
    RCALL uart_init

    /* INT0 setup */
    LDI R16, 0b11111000
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

    /* Default Times (Standby = 19:00:00, Op = 05:00:00) */
    LDI R16, 0x19
    STS standby_time, R16
    CLR R16
    STS standby_time+1, R16
    STS standby_time+2, R16

    LDI R16, 0x05
    STS op_time, R16
    CLR R16
    STS op_time+1, R16
    STS op_time+2, R16
    STS rx_idx, R16
    STS parse_flag, R16

    /* INT0 Rising Edge */
    LDI R16, (1<<ISC01) | (1<<ISC00)
    STS EICRA, R16
    LDI R16, (1<<INT0)
    OUT EIMSK, R16
    CLR R16
    STS siren_flag, R16
    SEI

intersection_loop:
    /* check UART */
    LDS R16, parse_flag
    TST R16
    BREQ skip_parsing
    RCALL process_uart_cmd
skip_parsing:

    LDS R16, siren_flag
    CPI R16, 1
    BRNE skip_siren
    RJMP do_siren_mode
skip_siren:

    RCALL log_time
    RCALL read_rtc
    RCALL check_night_hour

    IN R16, PINC
    ANDI R16, 1
    STS last_switch, R16

    CLR R18
    SBRS R16, 0
    LDI R18, 1

    OR R17, R18
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

/* UART PARSER */
process_uart_cmd:
    LDS R16, rx_idx
    CPI R16, 9
    BRNE cmd_invalid

    LDI R28, lo8(rx_buf)
    LDI R29, hi8(rx_buf)

    LDD R16, Y+3
    CPI R16, '.'
    BRNE cmd_invalid
    LDD R16, Y+6
    CPI R16, '.'
    BRNE cmd_invalid

    /* mode */
    LD R23, Y+
    CPI R23, 's'
    BREQ cmd_valid_type
    CPI R23, 'o'
    BREQ cmd_valid_type
    RJMP cmd_invalid

cmd_valid_type:
    /* HH */
    LD R16, Y+
    SUBI R16, 0x30
    SWAP R16
    LD R17, Y+
    SUBI R17, 0x30
    OR R16, R17
    MOV R20, R16

    ADIW R28, 1    

    /* MM */
    LD R16, Y+
    SUBI R16, 0x30
    SWAP R16
    LD R17, Y+
    SUBI R17, 0x30
    OR R16, R17
    MOV R21, R16

    ADIW R28, 1     

    /* SS */
    LD R16, Y+
    SUBI R16, 0x30
    SWAP R16
    LD R17, Y+
    SUBI R17, 0x30
    OR R16, R17
    MOV R22, R16

    CPI R23, 's'
    BREQ cmd_save_s

cmd_save_o:
    STS op_time, R20
    STS op_time+1, R21
    STS op_time+2, R22
    RJMP cmd_valid_done

cmd_save_s:
    STS standby_time, R20
    STS standby_time+1, R21
    STS standby_time+2, R22
    RJMP cmd_valid_done

cmd_invalid:
    LDI R30, lo8(str_invalid)
    LDI R31, hi8(str_invalid)
    RCALL print_str_pm
cmd_valid_done:
    /* reset */
    CLR R16
    STS rx_idx, R16
    STS parse_flag, R16
    RET

/* Time check */
check_night_hour:
    /* RTC mask */
    ANDI R22, 0x3F  /* HH */
    ANDI R21, 0x7F  /* MM */
    ANDI R20, 0x7F  /* SS */

    CLR R17         /* day mode */

    /* compare time */
    LDI R26, lo8(standby_time)
    LDI R27, hi8(standby_time)
    LDI R28, lo8(op_time)
    LDI R29, hi8(op_time)
    RCALL cmp_X_Y
    BRCC cnh_crosses_midnight

    /* Normal Interval (Standby < Op) */
    LDI R26, lo8(standby_time)
    LDI R27, hi8(standby_time)
    RCALL cmp_current_with_X
    BRCS cnh_done             

    LDI R26, lo8(op_time)
    LDI R27, hi8(op_time)
    RCALL cmp_current_with_X
    BRCC cnh_done            

    RJMP cnh_night

cnh_crosses_midnight:
    LDI R26, lo8(standby_time)
    LDI R27, hi8(standby_time)
    RCALL cmp_current_with_X
    BRCC cnh_night           

    LDI R26, lo8(op_time)
    LDI R27, hi8(op_time)
    RCALL cmp_current_with_X
    BRCS cnh_night          

cnh_done:
    RET

cnh_night:
    LDI R17, 1
    RET

/* compare Helpers */
cmp_X_Y:
    LD R16, X+
    LD R19, Y+
    CP R16, R19
    BRNE cxy_done
    LD R16, X+
    LD R19, Y+
    CP R16, R19
    BRNE cxy_done
    LD R16, X+
    LD R19, Y+
    CP R16, R19
cxy_done:
    RET

cmp_current_with_X:
    LD R16, X+
    CP R22, R16
    BRNE ccx_done
    LD R16, X+
    CP R21, R16
    BRNE ccx_done
    LD R16, X+
    CP R20, R16
ccx_done:
    RET

/* Interrupt & subroutine */
check_abort_normal:
    CLR R25
    LDS R16, siren_flag
    CPI R16, 1
    BREQ trigger_abort
    IN R16, PINC
    ANDI R16, 1
    LDS R17, last_switch
    CP R16, R17
    BREQ can_done
trigger_abort:
    LDI R25, 1
can_done:
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

delay_100ms:
    LDI R21, 100
d1: LDI R22, 200
d2: LDI R23, 20
d3: DEC R23
    BRNE d3
    DEC R22
    BRNE d2
    DEC R21
    BRNE d1
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
    LDI R16, (1<<RXEN0)|(1<<TXEN0)|(1<<RXCIE0)
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

do_siren_mode:
    LDI R20, 5
siren_blink_loop:
    LDI R16, 0b01001000
    OUT PORTD, R16
    LDI R16, 0b00000010
    OUT PORTB, R16
    LDI R24, 5
sbl_on_delay:
    RCALL delay_100ms
    DEC R24
    BRNE sbl_on_delay
    CLR R16
    OUT PORTD, R16
    OUT PORTB, R16
    LDI R24, 5
sbl_off_delay:
    RCALL delay_100ms
    DEC R24
    BRNE sbl_off_delay
    DEC R20
    BRNE siren_blink_loop
    CLR R16
    STS siren_flag, R16
    RJMP intersection_loop

USART_RX_vect:
    PUSH R16
    IN R16, SREG
    PUSH R16
    PUSH R17
    PUSH R18
    PUSH R30
    PUSH R31

    LDS R16, UDR0

    CPI R16, '\r'
    BREQ rx_flag
    CPI R16, '\n'
    BREQ rx_flag

    LDS R17, rx_idx
    CPI R17, 15
    BRSH end_rx

    LDI R30, lo8(rx_buf)
    LDI R31, hi8(rx_buf)
    ADD R30, R17
    CLR R18
    ADC R31, R18
    ST Z, R16

    INC R17
    STS rx_idx, R17
    RJMP end_rx

rx_flag:
    LDS R17, rx_idx
    TST R17
    BREQ end_rx
    LDI R17, 1
    STS parse_flag, R17

end_rx:
    POP R31
    POP R30
    POP R18
    POP R17
    POP R16
    OUT SREG, R16
    POP R16
    RETI

INT0_vect:
    PUSH R16
    IN R16, SREG
    PUSH R16
    LDI R16, 1
    STS siren_flag, R16
    POP R16
    OUT SREG, R16
    POP R16
    RETI

str_utara_siap: .asciz "Utara: PERSIAPAN\r\n"
str_utara_hijau: .asciz "Utara: HIJAU - "
str_utara_kuning: .asciz "\r\nUtara: KUNING\r\n"
str_selatan_siap: .asciz "Selatan: PERSIAPAN\r\n"
str_selatan_hijau: .asciz "Selatan: HIJAU - "
str_selatan_kuning: .asciz "\r\nSelatan: KUNING\r\n"
str_timur_siap: .asciz "Timur: PERSIAPAN\r\n"
str_timur_hijau: .asciz "Timur: HIJAU - "
str_timur_kuning: .asciz "\r\nTimur: KUNING\r\n"
str_invalid: .asciz "invalid input.\r\nto configure standby time: shh.mm.ss\r\nto configure operating time: ohh.mm.ss\r\n"