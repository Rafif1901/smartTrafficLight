; Master code 
; V1, basic traffic light

#define __SFR_OFFSET 0x00
#include "avr/io.h"

#define RED_TIME 10 ; set red light to 10s (testing purposes)
#define GREEN_TIME 5 ; set green light to 5s (testing purposes)
#define YELLOW_TIME 2

#define PIN_RED 0
#define PIN_YEL 1
#define PIN_GRN 2

.global main

main:
  RCALL twi_init
  RCALL uart_init
  ; set PD2-7 as output
  LDI R16, 0b11111100
  OUT DDRD, R16 

  ; set PB0-2 as output
  LDI R16, 0b00000111 
  OUT DDRB, R16

  ; Timer0 CTC Mode
  LDI R20, (1<<WGM01)
  OUT TCCR0A, R20

intersection_loop:
  RCALL read_rtc
  RCALL log_time
; --- STATE 1: L1 Green, L2 Red, L3 Red ---
    ; PORTD: L1_Grn (PD4) | L2_Red (PD5) = 0011 0000 = 0x30
    ; PORTB: L3_Red (PB0) = 0x01
    LDI R16, 0x30
    OUT PORTD, R16
    LDI R16, 0x01
    OUT PORTB, R16
    LDI R18, GREEN_TIME
    RCALL delay_seconds

    ; --- STATE 2: L1 Yellow, L2 Red, L3 Red ---
    ; PORTD: L1_Yel (PD3) | L2_Red (PD5) = 0010 1000 = 0x28
    ; PORTB: L3_Red (PB0) = 0x01
    LDI R16, 0x28
    OUT PORTD, R16
    LDI R16, 0x01
    OUT PORTB, R16
    LDI R18, YELLOW_TIME
    RCALL delay_seconds

    ; --- STATE 3: L1 Red, L2 Green, L3 Red ---
    ; PORTD: L1_Red (PD2) | L2_Grn (PD7) = 1000 0100 = 0x84
    ; PORTB: L3_Red (PB0) = 0x01
    LDI R16, 0x84
    OUT PORTD, R16
    LDI R16, 0x01
    OUT PORTB, R16
    LDI R18, GREEN_TIME
    RCALL delay_seconds

    ; --- STATE 4: L1 Red, L2 Yellow, L3 Red ---
    ; PORTD: L1_Red (PD2) | L2_Yel (PD6) = 0100 0100 = 0x44
    ; PORTB: L3_Red (PB0) = 0x01
    LDI R16, 0x44
    OUT PORTD, R16
    LDI R16, 0x01
    OUT PORTB, R16
    LDI R18, YELLOW_TIME
    RCALL delay_seconds

    ; --- STATE 5: L1 Red, L2 Red, L3 Green ---
    ; PORTD: L1_Red (PD2) | L2_Red (PD5) = 0010 0100 = 0x24
    ; PORTB: L3_Grn (PB2) = 0x04
    LDI R16, 0x24
    OUT PORTD, R16
    LDI R16, 0x04
    OUT PORTB, R16
    LDI R18, GREEN_TIME
    RCALL delay_seconds

    ; --- STATE 6: L1 Red, L2 Red, L3 Yellow ---
    ; PORTD: L1_Red (PD2) | L2_Red (PD5) = 0010 0100 = 0x24
    ; PORTB: L3_Yel (PB1) = 0x02
    LDI R16, 0x24
    OUT PORTD, R16
    LDI R16, 0x02
    OUT PORTB, R16
    LDI R18, YELLOW_TIME
    RCALL delay_seconds

    ; Loop forever
    RJMP intersection_loop


/* ══════════════════════════════════════════════════════════════════════════════
   SUBROUTINE: delay_seconds
   Input: R18 (Number of seconds)
   ══════════════════════════════════════════════════════════════════════════════ */
delay_seconds:
    TST R18                 ; Check if seconds counter is 0
    BREQ delay_done         ; If 0, exit subroutine

    LDI R19, 100            ; 100 loops of 10ms = 1 second
    LDI R16, 155            ; 155 ticks * 64us = ~9.98ms per loop
    OUT OCR0A, R16

    ; Start Timer0 with 1024 prescaler (CS02, CS00)
    LDI R16, (1<<CS02) | (1<<CS00)
    OUT TCCR0B, R16

loop_10ms:
    ; Reset Timer0 Counter
    CLR R16
    OUT TCNT0, R16

    ; Clear the Compare Match Flag by writing logic 1
    LDI R16, (1<<OCF0A)
    OUT TIFR0, R16

wait_flag:
    ; Poll the flag
    IN R16, TIFR0
    SBRS R16, OCF0A         ; Skip next instruction if flag is set
    RJMP wait_flag          ; Keep checking

    DEC R19                 ; Decrement the 100-loop counter
    BRNE loop_10ms          ; If not 0, do another 10ms

    ; 1 second is complete
    DEC R18                 ; Decrement the seconds counter
    RJMP delay_seconds      ; Do another second if R18 is not 0

delay_done:
    ; Stop Timer0
    CLR R16
    OUT TCCR0B, R16
    RET

/* ══════════════════════════════════════════════════════════════════════════════
   TWI (I2C) DRIVER LIBRARY FOR ATMEGA328P
   ══════════════════════════════════════════════════════════════════════════════ */

; --- 1. Initialize TWI (Set speed to 100kHz) ---
twi_init:
    ; Assuming 16MHz CPU Clock. 
    ; TWBR = ((16,000,000 / 100,000) - 16) / 2 = 72 = 0x48
    LDI R16, 0x48
    STS TWBR, R16
    ; Set Prescaler to 1 (TWPS0 = 0, TWPS1 = 0 in TWSR)
    CLR R16
    STS TWSR, R16
    RET

; --- 2. Send START Condition ---
twi_start:
    LDI R16, (1<<TWINT) | (1<<TWSTA) | (1<<TWEN)
    STS TWCR, R16
wait_start:
    LDS R16, TWCR
    SBRS R16, TWINT
    RJMP wait_start
    RET

; --- 3. Send STOP Condition ---
twi_stop:
    LDI R16, (1<<TWINT) | (1<<TWSTO) | (1<<TWEN)
    STS TWCR, R16
    RET

; --- 4. Write Byte (Byte to send must be in R18) ---
twi_write:
    STS TWDR, R18
    LDI R16, (1<<TWINT) | (1<<TWEN)
    STS TWCR, R16
wait_write:
    LDS R16, TWCR
    SBRS R16, TWINT
    RJMP wait_write
    RET

; --- 5. Read Byte + send ACK (to read multiple bytes) ---
; Result will be stored in R18
twi_read_ack:
    LDI R16, (1<<TWINT) | (1<<TWEN) | (1<<TWEA)
    STS TWCR, R16
wait_read_ack:
    LDS R16, TWCR
    SBRS R16, TWINT
    RJMP wait_read_ack
    LDS R18, TWDR
    RET

; --- 6. Read Byte + send NACK (for the very last byte) ---
; Result will be stored in R18
twi_read_nack:
    LDI R16, (1<<TWINT) | (1<<TWEN)
    STS TWCR, R16
wait_read_nack:
    LDS R16, TWCR
    SBRS R16, TWINT
    RJMP wait_read_nack
    LDS R18, TWDR
    RET

/* ══════════════════════════════════════════════════════════════════════════════
   READ DS3231 RTC
   This reads Seconds, Minutes, and Hours into R20, R21, and R22.
   ══════════════════════════════════════════════════════════════════════════════ */
read_rtc:
    ; 1. Send START
    RCALL twi_start

    ; 2. Send DS3231 Write Address (0xD0)
    LDI R18, 0xD0
    RCALL twi_write

    ; 3. Send Register Pointer (0x00 to start at Seconds)
    LDI R18, 0x00
    RCALL twi_write

    ; 4. Send REPEATED START (switches from writing to reading)
    RCALL twi_start

    ; 5. Send DS3231 Read Address (0xD1)
    LDI R18, 0xD1
    RCALL twi_write

    ; 6. Read Seconds (Register 0x00) and send ACK
    RCALL twi_read_ack
    MOV R20, R18       ; Save seconds to R20

    ; 7. Read Minutes (Register 0x01) and send ACK
    RCALL twi_read_ack
    MOV R21, R18       ; Save minutes to R21

    ; 8. Read Hours (Register 0x02) and send NACK (because it's the last byte)
    RCALL twi_read_nack
    MOV R22, R18       ; Save hours to R22

    ; 9. Send STOP
    RCALL twi_stop
    
    RET

/* ══════════════════════════════════════════════════════════════════════════════
   UART TRANSMIT LIBRARY (9600 Baud @ 16MHz)
   ══════════════════════════════════════════════════════════════════════════════ */

uart_init:
    ; Set Baud Rate to 9600 (UBRR = 103 for 16MHz)
    LDI R16, hi8(103)
    STS UBRR0H, R16
    LDI R16, lo8(103)
    STS UBRR0L, R16

    ; Enable Transmitter only (TXEN0)
    LDI R16, (1<<TXEN0)
    STS UCSR0B, R16

    ; Format: 8 data bits, 1 stop bit
    LDI R16, (1<<UCSZ01) | (1<<UCSZ00)
    STS UCSR0C, R16
    RET

; --- Transmit a single character stored in R16 ---
uart_tx:
    LDS R17, UCSR0A
    SBRS R17, UDRE0      ; Check if transmit buffer is empty
    RJMP uart_tx         ; If not, wait
    STS UDR0, R16        ; Send the character
    RET

/* ══════════════════════════════════════════════════════════════════════════════
   BCD TO ASCII TRANSMITTER
   Input: R18 contains the BCD byte (e.g., 0x45)
   Output: Transmits '4' then '5' over Serial
   ══════════════════════════════════════════════════════════════════════════════ */
bcd_to_ascii_tx:
    ; --- Extract and send the HIGH nibble (Tens digit) ---
    MOV R16, R18
    SWAP R16             ; Swap nibbles (0x45 becomes 0x54)
    ANDI R16, 0x0F       ; Mask out the top half (0x54 becomes 0x04)
    ORI R16, 0x30        ; Convert to ASCII (0x04 becomes 0x34, which is '4')
    RCALL uart_tx

    ; --- Extract and send the LOW nibble (Ones digit) ---
    MOV R16, R18
    ANDI R16, 0x0F       ; Mask out the top half (0x45 becomes 0x05)
    ORI R16, 0x30        ; Convert to ASCII (0x05 becomes 0x35, which is '5')
    RCALL uart_tx
    
    RET

/* ══════════════════════════════════════════════════════════════════════════════
   LOG TIME TO SERIAL (Format: HH:MM:SS)
   ══════════════════════════════════════════════════════════════════════════════ */
log_time:
    ; Read the time (Assuming read_rtc puts Sec in R20, Min in R21, Hr in R22)
    RCALL read_rtc

    ; --- Print Hours ---
    MOV R18, R22
    ; The DS3231 Hour register has control bits on the top end. 
    ; We mask them out (0x3F) to ensure we only get the hour numbers.
    ANDI R18, 0x3F       
    RCALL bcd_to_ascii_tx

    ; --- Print ':' ---
    LDI R16, ':'
    RCALL uart_tx

    ; --- Print Minutes ---
    MOV R18, R21
    RCALL bcd_to_ascii_tx

    ; --- Print ':' ---
    LDI R16, ':'
    RCALL uart_tx

    ; --- Print Seconds ---
    MOV R18, R20
    RCALL bcd_to_ascii_tx

    ; --- Print Newline (\r\n) ---
    LDI R16, '\r'
    RCALL uart_tx
    LDI R16, '\n'
    RCALL uart_tx

    RET

