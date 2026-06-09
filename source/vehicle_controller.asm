.include "m64def.inc"

;==================================================
; REGISTER MAP
;==================================================
; r20 : speed
; r21 : gear
; r22 : state (0=IDLE,1=STARTUP,2=DRIVE)
; r23 : clutch
; r24 : gas
; r25 : brake
; r26 : 250ms tick
; r27 : 1s tick
; r28 : warning flags
;==================================================

.org 0x0000
    rjmp RESET
.org 0x0002  
	rjmp INT_GAS
.org 0x0004  
	rjmp INT_BRAKE
.org 0x0006  
	rjmp INT_CLUTCH
.org 0x0008  
	rjmp INT_GEAR_UP
.org 0x000A  
	rjmp INT_GEAR_DOWN
.org 0x000C  
	rjmp INT_START
.org 0x0020  
	rjmp TIMER0_ISR

;==================================================
.org 0x0050  
RESET:
ldi r16,HIGH(RAMEND)
    out SPH,r16
    ldi r16,LOW(RAMEND)
    out SPL,r16

    ldi r16,0xAA
    sts EICRA,r16
    ldi r16,0x0A
    out EICRB,r16
    ldi r16,0x3F
    out EIMSK,r16

    clr r20
    clr r21
    clr r22
    clr r23
    clr r24
    clr r25
    clr r26
    clr r27
    clr r28
	clr r31


    ; outputs
    ldi r16,0xFF
    out DDRA,r16
    out DDRB,r16
    out DDRC,r16

    ; inputs
    clr r16
    out DDRD,r16
    out DDRE,r16

    ; pull-ups
    ldi r16,0xFF
    out PORTD,r16
    out PORTE,r16

    ; TIMER0 ~32ms
    ldi r16,0x07
    out TCCR0,r16
    ldi r16,0x01
    out TIMSK,r16

    sei

MAIN_LOOP:
	rcall FSM
    rcall CHECK_WARNINGS
	rcall WARNING_BLINK
	rcall WARNING_OUTPUT
    rjmp MAIN_LOOP

;==================================================
FSM:
    cpi r22,0
    breq FSM_IDLE
    cpi r22,1
    breq FSM_STARTUP
	cpi r22,2
    breq FSM_DRIVE
    ret

FSM_IDLE:
    clr r20
    clr r21
    cbi PORTC,0
    cbi PORTC,1
    cbi PORTC,2
    ret

FSM_STARTUP:
    sbi PORTC,0
    sbi PORTC,1
    sbi PORTC,2

    cpi r31,1
    brlo FS_EXIT

    clr r31
	cbi PORTC,0
    cbi PORTC,1
    cbi PORTC,2
    clr r20             
    clr r21               ; 
    ldi r22,2
FS_EXIT:
    ret

FSM_DRIVE:
    rcall SPEED_CONTROL
    rcall UPDATE_DISPLAY
    ret

;==================================================
SPEED_CONTROL:
    tst r23
    brne SPD_EXIT

    tst r24
    brne SPD_GAS

    tst r25
    brne SPD_BRAKE

    cpi r31,1
    brlo SPD_EXIT
    clr r31
    tst r20
    breq SPD_EXIT
    dec r20
    ret

SPD_GAS:
	tst r21
    breq SPD_EXIT

    tst r25
    brne SPD_EXIT
    cpi r27,1
    brlo SPD_EXIT
    clr r27
    rcall CHECK_MAX_SPEED
    brcs SPD_EXIT
    inc r20
    ret

SPD_BRAKE:
    cpi r27,1
    brlo SPD_EXIT
    clr r27
    subi r20,2
    brcc SPD_EXIT
    clr r20
SPD_EXIT:
    ret

;==================================================
CHECK_MAX_SPEED:
    ; r21 = gear
    cpi r21,1
    breq G1
    cpi r21,2
    breq G2
    cpi r21,3
    breq G3
    cpi r21,4
    breq G4
    cpi r21,5
    breq G5
    clc
    ret

G1: 
	ldi r16,25
    rjmp CMP
G2: 
	ldi r16,50
    rjmp CMP
G3: 
	ldi r16,75
    rjmp CMP
G4: 
	ldi r16,100
    rjmp CMP
G5: 
	ldi r16,125

CMP:
    cp r20,r16
    brlo OK
    sec           
    ret
OK:
    clc
    ret

;==================================================
UPDATE_DISPLAY:
    clr r16             
    cpi r20, 100
    brlo NO_HUNDRED
    ldi r16, 1
NO_HUNDRED:

    mov r17, r20         
    cpi r17, 100
    brlo SKIP_SUB100
    subi r17, 100        
SKIP_SUB100:

; ===============================
    clr r18              
TEN_LOOP:
    cpi r17, 10
    brlo TEN_DONE
    subi r17, 10
    inc r18
    rjmp TEN_LOOP
TEN_DONE:

; ===============================
    mov r19, r18       
    swap r19             
    andi r19, 0xF0

    andi r17, 0x0F       

    or r19, r17
    out PORTB, r19

; ===============================
    mov r19, r16       
    swap r19             
    andi r19, 0xF0

    mov r17, r21         
    andi r17, 0x0F

    or r19, r17
    out PORTA, r19

    ret

;==================================================
CHECK_WARNINGS:
    clr r28

    cpi r22,2
    brne CW_EXIT

    tst r24
    breq NO_GB
    tst r25
    breq NO_GB
    sbr r28,(1<<0)
NO_GB:

    tst r24
    breq NO_MAXW
    rcall CHECK_MAX_SPEED
    brcc NO_MAXW
    sbr r28,(1<<1)
NO_MAXW:


    tst r25
    breq NO_MINW
    rcall CHECK_MIN_SPEED
    brcc NO_MINW
    sbr r28,(1<<2)
NO_MINW:

CW_EXIT:
    ret


CHECK_MIN_SPEED:
    cpi r21,1
    breq MG1
    cpi r21,2
    breq MG2
    cpi r21,3
    breq MG3
    cpi r21,4
    breq MG4
    cpi r21,5
    breq MG5
    clc                
    ret

MG1:
    ldi r16,0
    rjmp MCMP
MG2:
    ldi r16,15
    rjmp MCMP
MG3:
    ldi r16,35
    rjmp MCMP
MG4:
    ldi r16,60
    rjmp MCMP
MG5:
    ldi r16,80

MCMP:
    cp r20, r16         
    brcs MIN_WARN       
	breq MIN_WARN       
    clc                 
    ret

MIN_WARN:
    sec
    ret

;==================================================
WARNING_BLINK:
    ; ??? ?? DRIVE
    cpi r22,2
    brne WARN_FORCE_OFF

    tst r28
    breq WARN_FORCE_OFF

    ; ??? ?? 250ms
    tst r26
    brne WARN_EXIT

    inc r29

    ; ---------- Warning 1 (bit0) ----------
    sbrc r28,0
    rjmp WARN1

    ; ---------- Warning 2 ?? 3 ----------
    sbrc r28,1
    rjmp WARN23
    sbrc r28,2
    rjmp WARN23

    rjmp WARN_EXIT


WARN1:
    cpi r29,1      ; tick 0 ? ON
    breq WARN_ON
    cpi r29,2      ; tick 1 ? OFF
    breq WARN_OFF
    clr r29
    rjmp WARN_ON


WARN23:
    cpi r29,2      ; 2×250ms = 500ms ? ON
    brlo WARN_ON
    cpi r29,4      ; 4×250ms = 1000ms
    brlo WARN_OFF
    clr r29
    rjmp WARN_ON



WARN_ON:
    sbr r30,(1<<0)
    rjmp WARN_EXIT

WARN_OFF:
    cbr r30,(1<<0)
    rjmp WARN_EXIT

WARN_FORCE_OFF:
    clr r29
    cbr r30,(1<<0)

WARN_EXIT:
    ret


WARNING_OUTPUT:
	clr r16

    sbrc r28,0
    sbr r16,(1<<0)

    sbrc r28,1
    sbr r16,(1<<1)

    sbrc r28,2
    sbr r16,(1<<2)

    sbrc r30,0
    rjmp WO_ON

WO_OFF:
    clr r16
    out PORTC,r16
    ret

WO_ON:
    out PORTC,r16
    ret

;==================================================
INT_GAS:    
	ldi r24,1  
	reti

INT_BRAKE:  
	ldi r25,1  
	reti

INT_CLUTCH: 
	ldi r23,1  
	reti

INT_GEAR_UP:
    tst r23
    breq GU_EX
    cpi r21,5
    breq GU_EX
    inc r21
GU_EX: reti

INT_GEAR_DOWN:
    tst r23
    breq GD_EX
    tst r21
    breq GD_EX
    dec r21
GD_EX: reti

INT_START:
    cpi r22,0
    brne START_EXIT
    ldi r22,1
START_EXIT:
    reti

;==================================================
TIMER0_ISR:
    ldi r16, 6
    out TCNT0,r16

T1:
    sbis PIND,0    
    rjmp SKIP_GAS
    clr r24
SKIP_GAS:

    sbis PIND,1
    rjmp SKIP_BRAKE
    clr r25
SKIP_BRAKE:

    sbis PIND,2
    rjmp SKIP_CLUTCH
    clr r23
SKIP_CLUTCH:

    inc r26
    cpi r26,8
    brlo T_EXIT

T2:
	clr r26
	inc r27
	cpi r27,3
	brlo T_EXIT
	inc r31
	clr r27

T_EXIT:
    reti
