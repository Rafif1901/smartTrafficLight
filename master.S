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
  ; set PD2-7 as output
  LDI R16, 0b11111100
  OUT DDRD, R16 

  ; set PB0-2 as output
  LDI R16 (1<<RED) | (1<<YEL) | (1<<GRN) 
  OUT DDRB, R16

  ; Timer0 CTC Mode
  LDI R20, (1<<WGM01)
  OUT TCCR0A, R20

intersection_loop:
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

