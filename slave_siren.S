#include <avr/io.h>

/* Constants */
#define UBRR_VAL          103     // 9600 baud @ 16MHz
#define TIMER0_OCR        249     // 8000 Hz Target
#define N_SAMPLES         100     // 12.5ms window
#define COEFF_800         26510
#define COEFF_1500        12063

/* Thresholds */
#define THRESH_800_LO     0x0300
#define THRESH_800_HI     0x0000

#define THRESH_1500_LO    0x0150
#define THRESH_1500_HI    0x0000

/* FSM Constants */
#define TIMEOUT_WIN       30
#define MIN_ALTS          4  

#define FSM_IDLE          0
#define FSM_WAIT_B        1
#define FSM_WAIT_A        2
#define FSM_CONFIRMED     3

#define INT_PIN           2

.section .bss
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

    /* ADC setup */
    ldi  r16, (1<<REFS0)|(1<<ADLAR)
    sts  ADMUX, r16
    ldi  r16, (1<<ADEN)|(1<<ADATE)|(1<<ADIE)|(1<<ADPS2)|(1<<ADPS1)|(1<<ADPS0)
    sts  ADCSRA, r16
    ldi  r16, (1<<ADTS1)|(1<<ADTS0)   
    sts  ADCSRB, r16
    ldi  r16, (1<<ADC0D)              
    sts  DIDR0, r16

    /* Timer0 */
    ldi  r16, (1<<WGM01)
    out  _SFR_IO_ADDR(TCCR0A), r16
    ldi  r16, (1<<CS01)
    out  _SFR_IO_ADDR(TCCR0B), r16
    ldi  r16, TIMER0_OCR
    out  _SFR_IO_ADDR(OCR0A), r16
    ldi  r16, 0            
    sts  TIMSK0, r16

    /* Start ADC */
    lds  r16, ADCSRA
    ori  r16, (1<<ADSC)
    sts  ADCSRA, r16

    /* Clear Math & State Registers */
    clr  r15                
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

/* Poll loop */
main_loop:
    lds  r16, sample_ready
    tst  r16
    breq main_loop

    clr  r16
    sts  sample_ready, r16

    lds  r24, adc_raw
    subi r24, 128
    clr  r25
    sbrc r24, 7
    ldi  r25, 0xFF

    asr  r25
    ror  r24
    asr  r25
    ror  r24

    rcall gi800
    rcall gi1500

    inc  r2
    mov  r16, r2
    cpi  r16, N_SAMPLES
    brne main_loop

    clr  r2

    rcall e800
    rcall threshold_800
    mov  r14, r16   

    clr  r4
    clr  r5
    clr  r6
    clr  r7

    rcall e1500
    rcall threshold_1500  

    clr  r8
    clr  r9
    clr  r10
    clr  r11

    mov  r18, r16
    tst  r14
    breq check_1500

    ldi  r30, lo8(str_800)
    ldi  r31, hi8(str_800)
    rcall print_string_flash
    rjmp print_done

check_1500:
    tst  r18
    breq print_done    

    ldi  r30, lo8(str_1500)
    ldi  r31, hi8(str_1500)
    rcall print_string_flash

print_done:
    mov  r16, r18
    mov  r17, r14

    rcall fsm

    rjmp main_loop

/* Goertzel calc */
gi800:
    ; abs s[n-1]
    movw r20, r4
    sbrs r21, 7
    rjmp gi800_abs_ok
    com  r20
    com  r21
    subi r20, 0xFF     
    sbci r21, 0xFF     
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
    adc  r19, r15
    mul  r23, r20
    add  r17, r0
    adc  r18, r1
    adc  r19, r15
    mul  r23, r21
    add  r18, r0
    adc  r19, r1
    ; Restore sign
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
    ; Q14 shift
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
    sbc  r21, r7      ; subtract s[n-2]
    add  r20, r24
    adc  r21, r25   
    ; Shift state
    movw r6, r4
    movw r4, r20
    clr  r1
    ret

gi1500:
    /* abs */
    movw r20, r8
    sbrs r21, 7
    rjmp gi1500_abs_ok
    com  r20
    com  r21
    subi r20, 0xFF
    sbci r21, 0xFF
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
    adc  r19, r15

    mul  r23, r20
    add  r17, r0
    adc  r18, r1
    adc  r19, r15

    mul  r23, r21
    add  r18, r0
    adc  r19, r1

    /* Restore sign */
    sbrs r9, 7       
    rjmp gi1500_sign_ok
    com  r16
    com  r17
    com  r18
    com  r19
    subi r16, 0xFF
    sbci r17, 0xFF
    sbci r18, 0xFF
    sbci r19, 0xFF
gi1500_sign_ok:

    /* Q14 */
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

    /* Shift registers */
    movw r10, r8
    movw r8, r20
    clr  r1
    ret

sq16:
    /* Low Byte Squared */
    mul  r16, r16
    movw r20, r0
    clr  r22
    clr  r23

    /* Cross Product */
    mul  r16, r17
    lsl  r0
    rol  r1
    clr  r22          
    adc  r22, r15     
    clr  r23
    add  r21, r0
    adc  r22, r1
    adc  r23, r15

    /* High Byte Squared */
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

/* Threshold */
threshold_800:
    push r17
    push r18
    push r19
    ldi  r16, lo8(THRESH_800_LO)
    ldi  r17, hi8(THRESH_800_LO)
    ldi  r18, lo8(THRESH_800_HI)
    ldi  r19, hi8(THRESH_800_HI)
    rjmp do_threshold

threshold_1500:
    push r17
    push r18
    push r19
    ldi  r16, lo8(THRESH_1500_LO)
    ldi  r17, hi8(THRESH_1500_LO)
    ldi  r18, lo8(THRESH_1500_HI)
    ldi  r19, hi8(THRESH_1500_HI)

do_threshold:
    cp   r20, r16
    cpc  r21, r17
    cpc  r22, r18
    cpc  r23, r19
    pop  r19
    pop  r18
    pop  r17
    brcs thr_below
    ldi  r16, 1
    ret
thr_below:
    clr  r16
    ret

/* FSM */
fsm:
    clr  r18
    tst  r17
    breq fsm_check1500
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
    lds  r16, fsm_state
    cpi  r16, FSM_IDLE
    breq fsm_idle
    cpi  r16, FSM_WAIT_B
    breq fsm_wait_b
    cpi  r16, FSM_WAIT_A
    breq fsm_wait_a
    rjmp fsm_done

fsm_idle:
    tst  r18              
    brne fsm_idle_check_a 
    rjmp fsm_done        

fsm_idle_check_a:
    cpi  r18, 1          
    breq fsm_start_from_a
    ldi  r16, FSM_WAIT_A
    rjmp fsm_start_common

fsm_start_from_a:
    ldi  r16, FSM_WAIT_B
fsm_start_common:
    sts  fsm_state, r16
    clr  r16
    sts  silence_cnt, r16 
    sts  alt_count, r16   
    rjmp fsm_done

fsm_wait_b:
    cpi  r18, 2          
    breq fsm_hit_b
    cpi  r18, 1           
    breq fsm_still_a
 
    lds  r19, silence_cnt
    inc  r19
    sts  silence_cnt, r19
    cpi  r19, TIMEOUT_WIN  
    brlo fsm_wait_b_safe   
    rjmp fsm_reset        
fsm_wait_b_safe:
    rjmp fsm_done

fsm_still_a:
    clr  r16
    sts  silence_cnt, r16 
    rjmp fsm_done

fsm_hit_b:
    lds  r20, alt_count
    inc  r20
    sts  alt_count, r20
    cpi  r20, MIN_ALTS
    brlo fsm_hit_b_safe
    rjmp fsm_trigger       
fsm_hit_b_safe:

    ldi  r16, FSM_WAIT_A
    sts  fsm_state, r16
    clr  r16
    sts  silence_cnt, r16
    rjmp fsm_done

fsm_wait_a:
    cpi  r18, 1           
    breq fsm_hit_a
    cpi  r18, 2           
    breq fsm_still_b

    lds  r19, silence_cnt
    inc  r19
    sts  silence_cnt, r19
    cpi  r19, TIMEOUT_WIN  
    brlo fsm_wait_a_safe   
    rjmp fsm_reset       
fsm_wait_a_safe:
    rjmp fsm_done

fsm_still_b:
    clr  r16
    sts  silence_cnt, r16 
    rjmp fsm_done

fsm_hit_a:
    lds  r20, alt_count
    inc  r20
    sts  alt_count, r20
    cpi  r20, MIN_ALTS
    brlo fsm_hit_a_safe
    rjmp fsm_trigger       
fsm_hit_a_safe:
    ldi  r16, FSM_WAIT_B
    sts  fsm_state, r16
    clr  r16
    sts  silence_cnt, r16
    rjmp fsm_done

fsm_reset:
    ldi  r16, FSM_IDLE
    sts  fsm_state, r16
    cbi  _SFR_IO_ADDR(PORTD), INT_PIN
    rjmp fsm_done

fsm_trigger:
    ldi  r19, FSM_CONFIRMED
    sts  fsm_state, r19

    /* trigger */
    sbi  _SFR_IO_ADDR(PORTD), INT_PIN

    ldi  r24, lo8(40000)
    ldi  r25, hi8(40000)
fsm_pulse:
    sbiw r24, 1
    brne fsm_pulse

	/* clear */
    cbi  _SFR_IO_ADDR(PORTD), INT_PIN

    /* status */
    ldi  r30, lo8(str_siren)
    ldi  r31, hi8(str_siren)
    rcall print_string_flash

    rjmp fsm_reset

fsm_done:
    ret

/* Interrupt */
.global ADC_vect
ADC_vect:
    push r16
    in   r16, _SFR_IO_ADDR(SREG)
    push r16

    ldi  r16, (1<<OCF0A)
    out  _SFR_IO_ADDR(TIFR0), r16

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

/* UART print */
print_string_flash:
    push r16
    push r17
psf_loop:
    lpm  r16, Z+        
    tst  r16          
    breq psf_done      
psf_wait:
    lds  r17, UCSR0A
    sbrs r17, UDRE0
    rjmp psf_wait
    sts  UDR0, r16
    rjmp psf_loop
psf_done:
    pop  r17
    pop  r16
    ret

str_800:   .asciz "800Hz tone detected\r\n"
str_1500:  .asciz "1500Hz tone detected\r\n"
str_siren: .asciz "Siren detected - Interrupting master...\r\n"