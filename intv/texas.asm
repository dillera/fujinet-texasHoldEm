	; IntyBASIC compiler v1.4.2 Jun/01/2020
	;
	; Prologue for IntyBASIC programs
	; by Oscar Toledo G.  http://nanochess.org/
	;
	; Revision: Jan/30/2014. Spacing adjustment and more comments.
	; Revision: Apr/01/2014. It now sets the starting screen pos. for PRINT
	; Revision: Aug/26/2014. Added PAL detection code.
	; Revision: Dec/12/2014. Added optimized constant multiplication routines.
	;                        by James Pujals.
	; Revision: Jan/25/2015. Added marker for automatic title replacement.
	;                        (option --title of IntyBASIC)
	; Revision: Aug/06/2015. Turns off ECS sound. Seed random generator using
	;                        trash in 16-bit RAM. Solved bugs and optimized
	;                        macro for constant multiplication.
	; Revision: Jan/12/2016. Solved bug in PAL detection.
	; Revision: May/03/2016. Changed in _mode_select initialization.
	; Revision: Jul/31/2016. Solved bug in multiplication by 126 and 127.
	; Revision: Sep/08/2016. Now CLRSCR initializes screen position for PRINT,
	;                        this solves bug when user programs goes directly
	;                        to PRINT.
	; Revision: Oct/21/2016. Accelerated MEMSET.
	; Revision: Jan/09/2018. Adjusted PAL/NTSC constant.
	; Revision: Feb/05/2018. Forces initialization of Intellivoice if included.
	;                        So VOICE INIT ceases to be dangerous.
	; Revision: Oct/30/2018. Redesigned PAL/NTSC detection using intvnut code,
	;                        also now compatible with Tutorvision. Reformatted.
	; Revision: Jan/10/2018. Added ECS detection.
	;

	ROMW 16
	ORG $5000

	; This macro will 'eat' SRCFILE directives if the assembler doesn't support the directive.
	IF ( DEFINED __FEATURE.SRCFILE ) = 0
	    MACRO SRCFILE x, y
	    ; macro must be non-empty, but a comment works fine.
	    ENDM
	ENDI

	;
	; ROM header
	;
	BIDECLE _ZERO		; MOB picture base
	BIDECLE _ZERO		; Process table
	BIDECLE _MAIN		; Program start
	BIDECLE _ZERO		; Background base image
	BIDECLE _ONES		; GRAM
	BIDECLE _TITLE		; Cartridge title and date
	DECLE   $03C0		; No ECS title, jump to code after title,
				; ... no clicks
                                
_ZERO:	DECLE   $0000		; Border control
	DECLE   $0000		; 0 = color stack, 1 = f/b mode
        
_ONES:	DECLE   $0001, $0001	; Initial color stack 0 and 1: Blue
	DECLE   $0001, $0001	; Initial color stack 2 and 3: Blue
	DECLE   $0001		; Initial border color: Blue

CLRSCR:	MVII #$200,R4		; Used also for CLS
	MVO R4,_screen		; Set up starting screen position for PRINT
	MVII #$F0,R1
FILLZERO:
	CLRR R0
MEMSET:
	SARC R1,2
	BNOV $+4
	MVO@ R0,R4
	MVO@ R0,R4
	BNC $+3
	MVO@ R0,R4
	BEQ $+7
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	DECR R1
	BNE $-5
	JR R5

	;
	; Title, Intellivision EXEC will jump over it and start
	; execution directly in _MAIN
	;
	; Note mark is for automatic replacement by IntyBASIC
_TITLE:
	BYTE 126,'IntyBASIC program',0
        
	;
	; Main program
	;
_MAIN:
	DIS			; Disable interrupts
	MVII #STACK,R6

	;
	; Clean memory
	;
	CALL CLRSCR		; Clean up screen, right here to avoid brief
				; screen display of title in Sears Intellivision.
	MVII #$00e,R1		; 14 of sound (ECS)
	MVII #$0f0,R4		; ECS PSG
	CALL FILLZERO
	MVII #$0fe,R1		; 240 words of 8 bits plus 14 of sound
	MVII #$100,R4		; 8-bit scratch RAM
	CALL FILLZERO

	; Seed random generator using 16 bit RAM (not cleared by EXEC)
	CLRR R0
	MVII #$02F0,R4
	MVII #$0110/4,R1	; Includes phantom memory for extra randomness
_MAIN4:				; This loop is courtesy of GroovyBee
	ADD@ R4,R0
	ADD@ R4,R0
	ADD@ R4,R0
	ADD@ R4,R0
	DECR R1
	BNE _MAIN4
	MVO R0,_rand

	MVII #$058,R1		; 88 words of 16 bits
	MVII #$308,R4		; 16-bit scratch RAM
	CALL FILLZERO

	; PAL/NTSC detect
	CALL _set_isr
	DECLE _pal1
	EIS
	DECR PC			; This is a kind of HALT instruction

	; First interrupt may come at a weird time on Tutorvision, or
	; if other startup timing changes.
_pal1:	SUBI #8,R6		; Drop interrupt stack.
	CALL _set_isr
	DECLE _pal2
	DECR PC

	; Second interrupt is safe for initializing MOBs.
	; We will know the screen is off after this one fires.
_pal2:	SUBI #8,R6		; Drop interrupt stack.
	CALL _set_isr
	DECLE _pal3
	; clear MOBs
	CLRR R0
	CLRR R4
	MVII #$18,R2
_pal2_lp:
	MVO@ R0,R4
	DECR R2
	BNE _pal2_lp
	MVO R0,$30		; Reset horizontal delay register
	MVO R0,$31		; Reset vertical delay register

	MVII #-1100,R2		; PAL/NTSC threshold
_pal2_cnt:
	INCR R2
	B _pal2_cnt

	; The final count in R2 will either be negative or positive.
	; If R2 is still -ve, NTSC; else PAL.
_pal3:	SUBI #8,R6		; Drop interrupt stack.
	RLC R2,1
	RLC R2,1
	ANDI #1,R2		; 1 = NTSC, 0 = PAL

	MVII #$55,R1
	MVO R1,$4040
	MVII #$AA,R1
	MVO R1,$4041
	MVI $4040,R1
	CMPI #$55,R1
	BNE _ecs1
	MVI $4041,R1
	CMPI #$AA,R1
	BNE _ecs1
	ADDI #2,R2		; ECS detected flag
_ecs1:
	MVO R2,_ntsc

	CALL _set_isr
	DECLE _int_vector

	CALL CLRSCR		; Because _screen was reset to zero
	CALL _wait
	CALL _init_music
	MVII #2,R0		; Color Stack mode
	MVO R0,_mode_select
	MVII #$038,R0
	MVO R0,$01F8		; Configures sound
	MVO R0,$00F8		; Configures sound (ECS)
	CALL IV_INIT_and_wait	; Setup Intellivoice

;* ======================================================================== *;
;*  These routines are placed into the public domain by their author.  All  *;
;*  copyright rights are hereby relinquished on the routines and data in    *;
;*  this file.  -- James Pujals (DZ-Jay), 2014                              *;
;* ======================================================================== *;

; Modified by Oscar Toledo G. (nanochess), Aug/06/2015
; * Tested all multiplications with automated test.
; * Accelerated multiplication by 7,14,15,28,31,60,62,63,112,120,124
; * Solved bug in multiplication by 23,39,46,47,55,71,78,79,87,92,93,94,95,103,110,111,119
; * Improved sequence of instructions to be more interruptible.

;; ======================================================================== ;;
;;  MULT reg, tmp, const                                                    ;;
;;  Multiplies "reg" by constant "const" and using "tmp" for temporary      ;;
;;  calculations.  The result is placed in "reg."  The multiplication is    ;;
;;  performed by an optimal combination of shifts, additions, and           ;;
;;  subtractions.                                                           ;;
;;                                                                          ;;
;;  NOTE:   The resulting contents of the "tmp" are undefined.              ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      reg         A register containing the multiplicand.                 ;;
;;      tmp         A register for temporary calculations.                  ;;
;;      const       The constant multiplier.                                ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      reg         Output value.                                           ;;
;;      tmp         Trashed.                                                ;;
;;      .ERR.Failed True if operation failed.                               ;;
;; ======================================================================== ;;
MACRO   MULT reg, tmp, const
;
    LISTING "code"

_mul.const      QSET    %const%
_mul.done       QSET    0

        IF (%const% > $7F)
_mul.const      QSET    (_mul.const SHR 1)
                SLL     %reg%,  1
        ENDI

        ; Multiply by $00 (0)
        IF (_mul.const = $00)
_mul.done       QSET    -1
                CLRR    %reg%
        ENDI

        ; Multiply by $01 (1)
        IF (_mul.const = $01)
_mul.done       QSET    -1
                ; Nothing to do
        ENDI

        ; Multiply by $02 (2)
        IF (_mul.const = $02)
_mul.done       QSET    -1
                SLL     %reg%,  1
        ENDI

        ; Multiply by $03 (3)
        IF (_mul.const = $03)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $04 (4)
        IF (_mul.const = $04)
_mul.done       QSET    -1
                SLL     %reg%,  2
        ENDI

        ; Multiply by $05 (5)
        IF (_mul.const = $05)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $06 (6)
        IF (_mul.const = $06)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $07 (7)
        IF (_mul.const = $07)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $08 (8)
        IF (_mul.const = $08)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
        ENDI

        ; Multiply by $09 (9)
        IF (_mul.const = $09)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $0A (10)
        IF (_mul.const = $0A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $0B (11)
        IF (_mul.const = $0B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $0C (12)
        IF (_mul.const = $0C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $0D (13)
        IF (_mul.const = $0D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $0E (14)
        IF (_mul.const = $0E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $0F (15)
        IF (_mul.const = $0F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $10 (16)
        IF (_mul.const = $10)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
        ENDI

        ; Multiply by $11 (17)
        IF (_mul.const = $11)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $12 (18)
        IF (_mul.const = $12)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $13 (19)
        IF (_mul.const = $13)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $14 (20)
        IF (_mul.const = $14)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $15 (21)
        IF (_mul.const = $15)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $16 (22)
        IF (_mul.const = $16)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $17 (23)
        IF (_mul.const = $17)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $18 (24)
        IF (_mul.const = $18)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $19 (25)
        IF (_mul.const = $19)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $1A (26)
        IF (_mul.const = $1A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $1B (27)
        IF (_mul.const = $1B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $1C (28)
        IF (_mul.const = $1C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $1D (29)
        IF (_mul.const = $1D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $1E (30)
        IF (_mul.const = $1E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $1F (31)
        IF (_mul.const = $1F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $20 (32)
        IF (_mul.const = $20)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
        ENDI

        ; Multiply by $21 (33)
        IF (_mul.const = $21)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $22 (34)
        IF (_mul.const = $22)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $23 (35)
        IF (_mul.const = $23)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $24 (36)
        IF (_mul.const = $24)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $25 (37)
        IF (_mul.const = $25)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $26 (38)
        IF (_mul.const = $26)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $27 (39)
        IF (_mul.const = $27)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $28 (40)
        IF (_mul.const = $28)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $29 (41)
        IF (_mul.const = $29)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $2A (42)
        IF (_mul.const = $2A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $2B (43)
        IF (_mul.const = $2B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $2C (44)
        IF (_mul.const = $2C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $2D (45)
        IF (_mul.const = $2D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $2E (46)
        IF (_mul.const = $2E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR	%tmp%,  %reg%
        ENDI

        ; Multiply by $2F (47)
        IF (_mul.const = $2F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR	%tmp%,  %reg%
        ENDI

        ; Multiply by $30 (48)
        IF (_mul.const = $30)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $31 (49)
        IF (_mul.const = $31)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $32 (50)
        IF (_mul.const = $32)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $33 (51)
        IF (_mul.const = $33)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $34 (52)
        IF (_mul.const = $34)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $35 (53)
        IF (_mul.const = $35)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $36 (54)
        IF (_mul.const = $36)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $37 (55)
        IF (_mul.const = $37)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
		SLL	%reg%,	1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $38 (56)
        IF (_mul.const = $38)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $39 (57)
        IF (_mul.const = $39)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $3A (58)
        IF (_mul.const = $3A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $3B (59)
        IF (_mul.const = $3B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $3C (60)
        IF (_mul.const = $3C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $3D (61)
        IF (_mul.const = $3D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $3E (62)
        IF (_mul.const = $3E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $3F (63)
        IF (_mul.const = $3F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $40 (64)
        IF (_mul.const = $40)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
                SLL     %reg%,  2
        ENDI

        ; Multiply by $41 (65)
        IF (_mul.const = $41)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $42 (66)
        IF (_mul.const = $42)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $43 (67)
        IF (_mul.const = $43)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $44 (68)
        IF (_mul.const = $44)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $45 (69)
        IF (_mul.const = $45)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $46 (70)
        IF (_mul.const = $46)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $47 (71)
        IF (_mul.const = $47)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $48 (72)
        IF (_mul.const = $48)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $49 (73)
        IF (_mul.const = $49)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $4A (74)
        IF (_mul.const = $4A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $4B (75)
        IF (_mul.const = $4B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $4C (76)
        IF (_mul.const = $4C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $4D (77)
        IF (_mul.const = $4D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $4E (78)
        IF (_mul.const = $4E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $4F (79)
        IF (_mul.const = $4F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $50 (80)
        IF (_mul.const = $50)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $51 (81)
        IF (_mul.const = $51)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $52 (82)
        IF (_mul.const = $52)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $53 (83)
        IF (_mul.const = $53)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $54 (84)
        IF (_mul.const = $54)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $55 (85)
        IF (_mul.const = $55)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $56 (86)
        IF (_mul.const = $56)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $57 (87)
        IF (_mul.const = $57)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR    %reg%,	%tmp%
                SLL     %reg%,  2
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $58 (88)
        IF (_mul.const = $58)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $59 (89)
        IF (_mul.const = $59)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $5A (90)
        IF (_mul.const = $5A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $5B (91)
        IF (_mul.const = $5B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $5C (92)
        IF (_mul.const = $5C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $5D (93)
        IF (_mul.const = $5D)
_mul.done       QSET    -1
		MOVR	%reg%,	%tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $5E (94)
        IF (_mul.const = $5E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $5F (95)
        IF (_mul.const = $5F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                ADDR	%reg%,	%reg%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $60 (96)
        IF (_mul.const = $60)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $61 (97)
        IF (_mul.const = $61)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $62 (98)
        IF (_mul.const = $62)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $63 (99)
        IF (_mul.const = $63)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $64 (100)
        IF (_mul.const = $64)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $65 (101)
        IF (_mul.const = $65)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $66 (102)
        IF (_mul.const = $66)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $67 (103)
        IF (_mul.const = $67)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $68 (104)
        IF (_mul.const = $68)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $69 (105)
        IF (_mul.const = $69)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $6A (106)
        IF (_mul.const = $6A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $6B (107)
        IF (_mul.const = $6B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $6C (108)
        IF (_mul.const = $6C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $6D (109)
        IF (_mul.const = $6D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $6E (110)
        IF (_mul.const = $6E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $6F (111)
        IF (_mul.const = $6F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $70 (112)
        IF (_mul.const = $70)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $71 (113)
        IF (_mul.const = $71)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $72 (114)
        IF (_mul.const = $72)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $73 (115)
        IF (_mul.const = $73)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $74 (116)
        IF (_mul.const = $74)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $75 (117)
        IF (_mul.const = $75)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $76 (118)
        IF (_mul.const = $76)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $77 (119)
        IF (_mul.const = $77)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $78 (120)
        IF (_mul.const = $78)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $79 (121)
        IF (_mul.const = $79)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $7A (122)
        IF (_mul.const = $7A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $7B (123)
        IF (_mul.const = $7B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $7C (124)
        IF (_mul.const = $7C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $7D (125)
        IF (_mul.const = $7D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $7E (126)
        IF (_mul.const = $7E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $7F (127)
        IF (_mul.const = $7F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        IF  (_mul.done = 0)
            ERR $("Invalid multiplication constant \'%const%\', must be between 0 and ", $#($7F), ".")
        ENDI

    LISTING "prev"
ENDM

;; ======================================================================== ;;
;;  EOF: pm:mac:lang:mult                                                   ;;
;; ======================================================================== ;;

	;FILE texas.bas
	;[1] ' texas.bas -- Texas Hold'em for Intellivision, entry point + state machine.
	SRCFILE "texas.bas",1
	;[2] '
	SRCFILE "texas.bas",2
	;[3] ' Converted from fujinet-5cardstud/intv/5card.bas the same way the C and
	SRCFILE "texas.bas",3
	;[4] ' FastBasic clients were converted: wire offsets shift +11 past viewing
	SRCFILE "texas.bas",4
	;[5] ' (community[11] inserted at 87, see state.bas), 2 hole cards per seat
	SRCFILE "texas.bas",5
	;[6] ' instead of 5, a 5-card community board center-table, and a street label
	SRCFILE "texas.bas",6
	;[7] ' (PRE-FLOP/FLOP/TURN/RIVER/SHOWDOWN). The betting UI is unchanged -- move
	SRCFILE "texas.bas",7
	;[8] ' codes and labels are server-supplied, so the client needs no poker rules.
	SRCFILE "texas.bas",8
	;[9] '
	SRCFILE "texas.bas",9
	;[10] ' Screen flow (simplified from the C clients' full parity, see the plan's
	SRCFILE "texas.bas",10
	;[11] ' Risks section): name entry (disc letter picker, falls back to it whenever
	SRCFILE "texas.bas",11
	;[12] ' the appkey read fails or comes back empty) -> table select (always shown
	SRCFILE "texas.bas",12
	;[13] ' at boot; the server endpoint is a compiled-in default rather than an
	SRCFILE "texas.bas",13
	;[14] ' appkey-persisted URL, since table select runs every boot anyway) -> game
	SRCFILE "texas.bas",14
	;[15] ' loop -> in-game menu (keypad CLEAR: quit table or resume).
	SRCFILE "texas.bas",15
	;[16] '
	SRCFILE "texas.bas",16
	;[17] ' Rendering only fully clears the screen when the table layout actually
	SRCFILE "texas.bas",17
	;[18] ' changes (see render_game); otherwise it updates cells in place, matching
	SRCFILE "texas.bas",18
	;[19] ' the CoCo/MSX C clients' SINGLE_BUFFER mode -- IntyBASIC has no true
	SRCFILE "texas.bas",19
	;[20] ' page-flip double buffering, so avoiding a per-poll CLS is what keeps the
	SRCFILE "texas.bas",20
	;[21] ' screen from flashing blank on every state refresh.
	SRCFILE "texas.bas",21
	;[22] '
	SRCFILE "texas.bas",22
	;[23] ' GOTO boot_start jumps over every INCLUDE below before any of it runs.
	SRCFILE "texas.bas",23
	;[24] ' This isn't optional: fujinet.bas/gfx.bas are libraries whose PROCEDURE
	SRCFILE "texas.bas",24
	;[25] ' (and gfx.bas's DATA) bodies are meant to be reached only via GOSUB, per
	SRCFILE "texas.bas",25
	;[26] ' the IntyBASIC manual's warning that falling into a PROCEDURE or DATA
	SRCFILE "texas.bas",26
	;[27] ' block by straight-line execution corrupts the return stack. Since
	SRCFILE "texas.bas",27
	;[28] ' INCLUDE pastes their text in at this point, and this file's own
	SRCFILE "texas.bas",28
	;[29] ' DATA/PROCEDURE blocks (below) have the same requirement, the single
	SRCFILE "texas.bas",29
	;[30] ' cheapest fix is to never let the CPU reach any of it except via GOSUB --
	SRCFILE "texas.bas",30
	;[31] ' hence jumping straight to boot_start before the includes even begin.
	SRCFILE "texas.bas",31
	;[32]     GOTO boot_start
	SRCFILE "texas.bas",32
	B label_BOOT_START
	;[33] 
	SRCFILE "texas.bas",33
	;[34]     INCLUDE "constants.bas"
	SRCFILE "texas.bas",34
	;FILE constants.bas
	;[1] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",1
	;[2] REM HEADER - CONSTANTS.BAS
	SRCFILE "constants.bas",2
	;[3] REM 
	SRCFILE "constants.bas",3
	;[4] REM Started by Mark Ball, July 2015
	SRCFILE "constants.bas",4
	;[5] REM
	SRCFILE "constants.bas",5
	;[6] REM Constants for use in IntyBASIC
	SRCFILE "constants.bas",6
	;[7] REM
	SRCFILE "constants.bas",7
	;[8] REM HISTORY
	SRCFILE "constants.bas",8
	;[9] REM -------
	SRCFILE "constants.bas",9
	;[10] REM 1.00F 05/07/15 - First version.
	SRCFILE "constants.bas",10
	;[11] REM 1.01F 07/07/15 - Added disc directions.
	SRCFILE "constants.bas",11
	;[12] REM                - Added background modes.
	SRCFILE "constants.bas",12
	;[13] REM                - Minor comment changes.
	SRCFILE "constants.bas",13
	;[14] REM 1.02F 08/07/15 - Renamed constants.
	SRCFILE "constants.bas",14
	;[15] REM                - Added background access information.
	SRCFILE "constants.bas",15
	;[16] REM                - Adjustments to layout.
	SRCFILE "constants.bas",16
	;[17] REM 1.03F 08/07/15 - Fixed comment delimiter.
	SRCFILE "constants.bas",17
	;[18] REM 1.04F 11/07/15 - Added useful functions.
	SRCFILE "constants.bas",18
	;[19] REM	               - Added controller movement mask.
	SRCFILE "constants.bas",19
	;[20] REM 1.05F 11/07/15 - Added BACKGROUND constants.
	SRCFILE "constants.bas",20
	;[21] REM 1.06F 11/07/15 - Changed Y, X order to X, Y in DEF FN functions.
	SRCFILE "constants.bas",21
	;[22] REM 1.07F 11/07/15 - Added colour stack advance.
	SRCFILE "constants.bas",22
	;[23] REM 1.08F 12/07/15 - Added functions for sprite position handling.
	SRCFILE "constants.bas",23
	;[24] REM 1.09F 12/07/15 - Added a function for resetting a sprite.
	SRCFILE "constants.bas",24
	;[25] REM 1.10F 13/07/15 - Added keypad constants.
	SRCFILE "constants.bas",25
	;[26] REM 1.11F 13/07/15 - Added side button constants.
	SRCFILE "constants.bas",26
	;[27] REM 1.12F 13/07/15 - Updated sprite functions.
	SRCFILE "constants.bas",27
	;[28] REM 1.13F 19/07/15 - Added border masking constants.
	SRCFILE "constants.bas",28
	;[29] REM 1.14F 20/07/15 - Added a combined border masking constant.
	SRCFILE "constants.bas",29
	;[30] REM 1.15F 20/07/15 - Renamed border masking constants to BORDER_HIDE_xxxx.
	SRCFILE "constants.bas",30
	;[31] REM 1.16F 28/09/15 - Fixed disc direction typos.
	SRCFILE "constants.bas",31
	;[32] REM 1.17F 30/09/15 - Fixed DISC_SOUTH_WEST value.
	SRCFILE "constants.bas",32
	;[33] REM 1.18F 05/12/15 - Fixed BG_XXXX colours.
	SRCFILE "constants.bas",33
	;[34] REM 1.19F 01/01/16 - Changed name of BACKTAB constant to avoid confusion with #BACKTAB array.
	SRCFILE "constants.bas",34
	;[35] REM                - Added pause key constants.
	SRCFILE "constants.bas",35
	;[36] REM 1.20F 14/01/16 - Added coloured squares mode's pixel colours.
	SRCFILE "constants.bas",36
	;[37] REM 1.21F 15/01/16 - Added coloured squares mode's X and Y limits.
	SRCFILE "constants.bas",37
	;[38] REM 1.22F 23/01/16 - Added PSG constants.
	SRCFILE "constants.bas",38
	;[39] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",39
	;[40] 
	SRCFILE "constants.bas",40
	;[41] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "constants.bas",41
	;[42] 
	SRCFILE "constants.bas",42
	;[43] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",43
	;[44] REM Background information.
	SRCFILE "constants.bas",44
	;[45] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",45
	;[46] CONST BACKTAB_ADDR			= $0200		' Start of the BACKground TABle (BACKTAB) in RAM.
	SRCFILE "constants.bas",46
	;[47] CONST BACKGROUND_ROWS		= 12		' Height of the background in cards.
	SRCFILE "constants.bas",47
	;[48] CONST BACKGROUND_COLUMNS	= 20		' Width of the background in cards.
	SRCFILE "constants.bas",48
	;[49] 
	SRCFILE "constants.bas",49
	;[50] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",50
	;[51] REM Background GRAM cards.
	SRCFILE "constants.bas",51
	;[52] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",52
	;[53] CONST BG00 					= $0800
	SRCFILE "constants.bas",53
	;[54] CONST BG01 					= $0808
	SRCFILE "constants.bas",54
	;[55] CONST BG02 					= $0810
	SRCFILE "constants.bas",55
	;[56] CONST BG03 					= $0818
	SRCFILE "constants.bas",56
	;[57] CONST BG04 					= $0820
	SRCFILE "constants.bas",57
	;[58] CONST BG05 					= $0828
	SRCFILE "constants.bas",58
	;[59] CONST BG06 					= $0830
	SRCFILE "constants.bas",59
	;[60] CONST BG07 					= $0838
	SRCFILE "constants.bas",60
	;[61] CONST BG08 					= $0840
	SRCFILE "constants.bas",61
	;[62] CONST BG09 					= $0848
	SRCFILE "constants.bas",62
	;[63] CONST BG10 					= $0850
	SRCFILE "constants.bas",63
	;[64] CONST BG11 					= $0858
	SRCFILE "constants.bas",64
	;[65] CONST BG12 					= $0860
	SRCFILE "constants.bas",65
	;[66] CONST BG13 					= $0868
	SRCFILE "constants.bas",66
	;[67] CONST BG14 					= $0870
	SRCFILE "constants.bas",67
	;[68] CONST BG15 					= $0878
	SRCFILE "constants.bas",68
	;[69] CONST BG16 					= $0880
	SRCFILE "constants.bas",69
	;[70] CONST BG17 					= $0888
	SRCFILE "constants.bas",70
	;[71] CONST BG18 					= $0890
	SRCFILE "constants.bas",71
	;[72] CONST BG19 					= $0898
	SRCFILE "constants.bas",72
	;[73] CONST BG20 					= $08A0
	SRCFILE "constants.bas",73
	;[74] CONST BG21 					= $08A8
	SRCFILE "constants.bas",74
	;[75] CONST BG22 					= $08B0
	SRCFILE "constants.bas",75
	;[76] CONST BG23 					= $08B8
	SRCFILE "constants.bas",76
	;[77] CONST BG24 					= $08C0
	SRCFILE "constants.bas",77
	;[78] CONST BG25 					= $08C8
	SRCFILE "constants.bas",78
	;[79] CONST BG26 					= $08D0
	SRCFILE "constants.bas",79
	;[80] CONST BG27 					= $08D8
	SRCFILE "constants.bas",80
	;[81] CONST BG28 					= $08E0
	SRCFILE "constants.bas",81
	;[82] CONST BG29 					= $08E8
	SRCFILE "constants.bas",82
	;[83] CONST BG30 					= $08F0
	SRCFILE "constants.bas",83
	;[84] CONST BG31 					= $08F8
	SRCFILE "constants.bas",84
	;[85] CONST BG32 					= $0900
	SRCFILE "constants.bas",85
	;[86] CONST BG33 					= $0908
	SRCFILE "constants.bas",86
	;[87] CONST BG34 					= $0910
	SRCFILE "constants.bas",87
	;[88] CONST BG35 					= $0918
	SRCFILE "constants.bas",88
	;[89] CONST BG36 					= $0920
	SRCFILE "constants.bas",89
	;[90] CONST BG37 					= $0928
	SRCFILE "constants.bas",90
	;[91] CONST BG38 					= $0930
	SRCFILE "constants.bas",91
	;[92] CONST BG39 					= $0938
	SRCFILE "constants.bas",92
	;[93] CONST BG40 					= $0940
	SRCFILE "constants.bas",93
	;[94] CONST BG41 					= $0948
	SRCFILE "constants.bas",94
	;[95] CONST BG42 					= $0950
	SRCFILE "constants.bas",95
	;[96] CONST BG43 					= $0958
	SRCFILE "constants.bas",96
	;[97] CONST BG44 					= $0960
	SRCFILE "constants.bas",97
	;[98] CONST BG45 					= $0968
	SRCFILE "constants.bas",98
	;[99] CONST BG46 					= $0970
	SRCFILE "constants.bas",99
	;[100] CONST BG47 					= $0978
	SRCFILE "constants.bas",100
	;[101] CONST BG48 					= $0980
	SRCFILE "constants.bas",101
	;[102] CONST BG49 					= $0988
	SRCFILE "constants.bas",102
	;[103] CONST BG50 					= $0990
	SRCFILE "constants.bas",103
	;[104] CONST BG51 					= $0998
	SRCFILE "constants.bas",104
	;[105] CONST BG52 					= $09A0
	SRCFILE "constants.bas",105
	;[106] CONST BG53 					= $09A8
	SRCFILE "constants.bas",106
	;[107] CONST BG54 					= $09B0
	SRCFILE "constants.bas",107
	;[108] CONST BG55 					= $09B8
	SRCFILE "constants.bas",108
	;[109] CONST BG56 					= $09C0
	SRCFILE "constants.bas",109
	;[110] CONST BG57 					= $09C8
	SRCFILE "constants.bas",110
	;[111] CONST BG58 					= $09D0
	SRCFILE "constants.bas",111
	;[112] CONST BG59 					= $09D8
	SRCFILE "constants.bas",112
	;[113] CONST BG60 					= $09E0
	SRCFILE "constants.bas",113
	;[114] CONST BG61 					= $09E8
	SRCFILE "constants.bas",114
	;[115] CONST BG62 					= $09F0
	SRCFILE "constants.bas",115
	;[116] CONST BG63 					= $09F8
	SRCFILE "constants.bas",116
	;[117] 	
	SRCFILE "constants.bas",117
	;[118] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "constants.bas",118
	;[119] 
	SRCFILE "constants.bas",119
	;[120] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",120
	;[121] REM GRAM card index numbers.
	SRCFILE "constants.bas",121
	;[122] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",122
	;[123] REM Note: For use with the "define" command.
	SRCFILE "constants.bas",123
	;[124] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",124
	;[125] CONST DEF00 				= $0000
	SRCFILE "constants.bas",125
	;[126] CONST DEF01 				= $0001
	SRCFILE "constants.bas",126
	;[127] CONST DEF02 				= $0002
	SRCFILE "constants.bas",127
	;[128] CONST DEF03 				= $0003
	SRCFILE "constants.bas",128
	;[129] CONST DEF04 				= $0004
	SRCFILE "constants.bas",129
	;[130] CONST DEF05 				= $0005
	SRCFILE "constants.bas",130
	;[131] CONST DEF06 				= $0006
	SRCFILE "constants.bas",131
	;[132] CONST DEF07 				= $0007
	SRCFILE "constants.bas",132
	;[133] CONST DEF08 				= $0008
	SRCFILE "constants.bas",133
	;[134] CONST DEF09 				= $0009
	SRCFILE "constants.bas",134
	;[135] CONST DEF10 				= $000A
	SRCFILE "constants.bas",135
	;[136] CONST DEF11 				= $000B
	SRCFILE "constants.bas",136
	;[137] CONST DEF12 				= $000C
	SRCFILE "constants.bas",137
	;[138] CONST DEF13 				= $000D
	SRCFILE "constants.bas",138
	;[139] CONST DEF14 				= $000E
	SRCFILE "constants.bas",139
	;[140] CONST DEF15 				= $000F
	SRCFILE "constants.bas",140
	;[141] CONST DEF16 				= $0010
	SRCFILE "constants.bas",141
	;[142] CONST DEF17 				= $0011
	SRCFILE "constants.bas",142
	;[143] CONST DEF18 				= $0012
	SRCFILE "constants.bas",143
	;[144] CONST DEF19 				= $0013
	SRCFILE "constants.bas",144
	;[145] CONST DEF20 				= $0014
	SRCFILE "constants.bas",145
	;[146] CONST DEF21 				= $0015
	SRCFILE "constants.bas",146
	;[147] CONST DEF22 				= $0016
	SRCFILE "constants.bas",147
	;[148] CONST DEF23 				= $0017
	SRCFILE "constants.bas",148
	;[149] CONST DEF24 				= $0018
	SRCFILE "constants.bas",149
	;[150] CONST DEF25 				= $0019
	SRCFILE "constants.bas",150
	;[151] CONST DEF26 				= $001A
	SRCFILE "constants.bas",151
	;[152] CONST DEF27 				= $001B
	SRCFILE "constants.bas",152
	;[153] CONST DEF28 				= $001C
	SRCFILE "constants.bas",153
	;[154] CONST DEF29 				= $001D
	SRCFILE "constants.bas",154
	;[155] CONST DEF30 				= $001E
	SRCFILE "constants.bas",155
	;[156] CONST DEF31 				= $001F
	SRCFILE "constants.bas",156
	;[157] CONST DEF32 				= $0020
	SRCFILE "constants.bas",157
	;[158] CONST DEF33 				= $0021
	SRCFILE "constants.bas",158
	;[159] CONST DEF34 				= $0022
	SRCFILE "constants.bas",159
	;[160] CONST DEF35 				= $0023
	SRCFILE "constants.bas",160
	;[161] CONST DEF36 				= $0024
	SRCFILE "constants.bas",161
	;[162] CONST DEF37 				= $0025
	SRCFILE "constants.bas",162
	;[163] CONST DEF38 				= $0026
	SRCFILE "constants.bas",163
	;[164] CONST DEF39 				= $0027
	SRCFILE "constants.bas",164
	;[165] CONST DEF40 				= $0028
	SRCFILE "constants.bas",165
	;[166] CONST DEF41 				= $0029
	SRCFILE "constants.bas",166
	;[167] CONST DEF42 				= $002A
	SRCFILE "constants.bas",167
	;[168] CONST DEF43 				= $002B
	SRCFILE "constants.bas",168
	;[169] CONST DEF44 				= $002C
	SRCFILE "constants.bas",169
	;[170] CONST DEF45 				= $002D
	SRCFILE "constants.bas",170
	;[171] CONST DEF46 				= $002E
	SRCFILE "constants.bas",171
	;[172] CONST DEF47 				= $002F
	SRCFILE "constants.bas",172
	;[173] CONST DEF48 				= $0030
	SRCFILE "constants.bas",173
	;[174] CONST DEF49 				= $0031
	SRCFILE "constants.bas",174
	;[175] CONST DEF50 				= $0032
	SRCFILE "constants.bas",175
	;[176] CONST DEF51 				= $0033
	SRCFILE "constants.bas",176
	;[177] CONST DEF52 				= $0034
	SRCFILE "constants.bas",177
	;[178] CONST DEF53 				= $0035
	SRCFILE "constants.bas",178
	;[179] CONST DEF54 				= $0036
	SRCFILE "constants.bas",179
	;[180] CONST DEF55 				= $0037
	SRCFILE "constants.bas",180
	;[181] CONST DEF56 				= $0038
	SRCFILE "constants.bas",181
	;[182] CONST DEF57 				= $0039
	SRCFILE "constants.bas",182
	;[183] CONST DEF58 				= $003A
	SRCFILE "constants.bas",183
	;[184] CONST DEF59 				= $003B
	SRCFILE "constants.bas",184
	;[185] CONST DEF60 				= $003C
	SRCFILE "constants.bas",185
	;[186] CONST DEF61 				= $003D
	SRCFILE "constants.bas",186
	;[187] CONST DEF62 				= $003E
	SRCFILE "constants.bas",187
	;[188] CONST DEF63 				= $003F
	SRCFILE "constants.bas",188
	;[189] 
	SRCFILE "constants.bas",189
	;[190] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "constants.bas",190
	;[191] 
	SRCFILE "constants.bas",191
	;[192] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",192
	;[193] REM Screen modes.
	SRCFILE "constants.bas",193
	;[194] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",194
	;[195] REM Note: For use with the "mode" command.
	SRCFILE "constants.bas",195
	;[196] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",196
	;[197] CONST SCREEN_COLOR_STACK			= $0000
	SRCFILE "constants.bas",197
	;[198] CONST SCREEN_FOREGROUND_BACKGROUND	= $0001
	SRCFILE "constants.bas",198
	;[199] REM Abbreviated versions.
	SRCFILE "constants.bas",199
	;[200] CONST SCREEN_CS						= $0000
	SRCFILE "constants.bas",200
	;[201] CONST SCREEN_FB						= $0001
	SRCFILE "constants.bas",201
	;[202] 
	SRCFILE "constants.bas",202
	;[203] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "constants.bas",203
	;[204] 
	SRCFILE "constants.bas",204
	;[205] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",205
	;[206] REM COLORS - Border.
	SRCFILE "constants.bas",206
	;[207] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",207
	;[208] REM Notes:
	SRCFILE "constants.bas",208
	;[209] REM - For use with the commands "mode 0" and "mode 1".
	SRCFILE "constants.bas",209
	;[210] REM - For use with the "border" command.
	SRCFILE "constants.bas",210
	;[211] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",211
	;[212] CONST BORDER_BLACK			= $0000
	SRCFILE "constants.bas",212
	;[213] CONST BORDER_BLUE			= $0001
	SRCFILE "constants.bas",213
	;[214] CONST BORDER_RED			= $0002
	SRCFILE "constants.bas",214
	;[215] CONST BORDER_TAN			= $0003
	SRCFILE "constants.bas",215
	;[216] CONST BORDER_DARKGREEN		= $0004
	SRCFILE "constants.bas",216
	;[217] CONST BORDER_GREEN			= $0005
	SRCFILE "constants.bas",217
	;[218] CONST BORDER_YELLOW			= $0006
	SRCFILE "constants.bas",218
	;[219] CONST BORDER_WHITE			= $0007
	SRCFILE "constants.bas",219
	;[220] CONST BORDER_GREY			= $0008
	SRCFILE "constants.bas",220
	;[221] CONST BORDER_CYAN			= $0009
	SRCFILE "constants.bas",221
	;[222] CONST BORDER_ORANGE			= $000A
	SRCFILE "constants.bas",222
	;[223] CONST BORDER_BROWN			= $000B
	SRCFILE "constants.bas",223
	;[224] CONST BORDER_PINK			= $000C
	SRCFILE "constants.bas",224
	;[225] CONST BORDER_LIGHTBLUE		= $000D
	SRCFILE "constants.bas",225
	;[226] CONST BORDER_YELLOWGREEN	= $000E
	SRCFILE "constants.bas",226
	;[227] CONST BORDER_PURPLE			= $000F
	SRCFILE "constants.bas",227
	;[228] 
	SRCFILE "constants.bas",228
	;[229] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "constants.bas",229
	;[230] 
	SRCFILE "constants.bas",230
	;[231] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",231
	;[232] REM BORDER - Edge masks.
	SRCFILE "constants.bas",232
	;[233] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",233
	;[234] REM Note: For use with the "border color, edge" command.
	SRCFILE "constants.bas",234
	;[235] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",235
	;[236] CONST BORDER_HIDE_LEFT_EDGE		= $0001		' Hide the leftmost column of the background.
	SRCFILE "constants.bas",236
	;[237] CONST BORDER_HIDE_TOP_EDGE		= $0002		' Hide the topmost row of the background.
	SRCFILE "constants.bas",237
	;[238] CONST BORDER_HIDE_TOP_LEFT_EDGE	= $0003		' Hide both the topmost row and leftmost column of the background.
	SRCFILE "constants.bas",238
	;[239] 
	SRCFILE "constants.bas",239
	;[240] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "constants.bas",240
	;[241] 
	SRCFILE "constants.bas",241
	;[242] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",242
	;[243] REM COLORS - Mode 0 (Color Stack).
	SRCFILE "constants.bas",243
	;[244] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",244
	;[245] REM Stack
	SRCFILE "constants.bas",245
	;[246] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",246
	;[247] REM Note: For use as the last 4 parameters used in the "mode 1" command.
	SRCFILE "constants.bas",247
	;[248] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",248
	;[249] CONST STACK_BLACK			= $0000
	SRCFILE "constants.bas",249
	;[250] CONST STACK_BLUE			= $0001
	SRCFILE "constants.bas",250
	;[251] CONST STACK_RED				= $0002
	SRCFILE "constants.bas",251
	;[252] CONST STACK_TAN				= $0003
	SRCFILE "constants.bas",252
	;[253] CONST STACK_DARKGREEN		= $0004
	SRCFILE "constants.bas",253
	;[254] CONST STACK_GREEN			= $0005
	SRCFILE "constants.bas",254
	;[255] CONST STACK_YELLOW			= $0006
	SRCFILE "constants.bas",255
	;[256] CONST STACK_WHITE			= $0007
	SRCFILE "constants.bas",256
	;[257] CONST STACK_GREY			= $0008
	SRCFILE "constants.bas",257
	;[258] CONST STACK_CYAN			= $0009
	SRCFILE "constants.bas",258
	;[259] CONST STACK_ORANGE			= $000A
	SRCFILE "constants.bas",259
	;[260] CONST STACK_BROWN			= $000B
	SRCFILE "constants.bas",260
	;[261] CONST STACK_PINK			= $000C
	SRCFILE "constants.bas",261
	;[262] CONST STACK_LIGHTBLUE		= $000D
	SRCFILE "constants.bas",262
	;[263] CONST STACK_YELLOWGREEN		= $000E
	SRCFILE "constants.bas",263
	;[264] CONST STACK_PURPLE			= $000F
	SRCFILE "constants.bas",264
	;[265] 
	SRCFILE "constants.bas",265
	;[266] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",266
	;[267] REM Foreground.
	SRCFILE "constants.bas",267
	;[268] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",268
	;[269] REM Notes:
	SRCFILE "constants.bas",269
	;[270] REM - For use with "peek/poke" commands that access BACKTAB.
	SRCFILE "constants.bas",270
	;[271] REM - Only one foreground colour permitted per background card.
	SRCFILE "constants.bas",271
	;[272] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",272
	;[273] CONST CS_BLACK				= $0000
	SRCFILE "constants.bas",273
	;[274] CONST CS_BLUE				= $0001
	SRCFILE "constants.bas",274
	;[275] CONST CS_RED				= $0002
	SRCFILE "constants.bas",275
	;[276] CONST CS_TAN				= $0003
	SRCFILE "constants.bas",276
	;[277] CONST CS_DARKGREEN			= $0004
	SRCFILE "constants.bas",277
	;[278] CONST CS_GREEN				= $0005
	SRCFILE "constants.bas",278
	;[279] CONST CS_YELLOW				= $0006
	SRCFILE "constants.bas",279
	;[280] CONST CS_WHITE				= $0007
	SRCFILE "constants.bas",280
	;[281] CONST CS_GREY				= $1000
	SRCFILE "constants.bas",281
	;[282] CONST CS_CYAN				= $1001
	SRCFILE "constants.bas",282
	;[283] CONST CS_ORANGE				= $1002
	SRCFILE "constants.bas",283
	;[284] CONST CS_BROWN				= $1003
	SRCFILE "constants.bas",284
	;[285] CONST CS_PINK				= $1004
	SRCFILE "constants.bas",285
	;[286] CONST CS_LIGHTBLUE			= $1005
	SRCFILE "constants.bas",286
	;[287] CONST CS_YELLOWGREEN		= $1006
	SRCFILE "constants.bas",287
	;[288] CONST CS_PURPLE				= $1007
	SRCFILE "constants.bas",288
	;[289] 
	SRCFILE "constants.bas",289
	;[290] CONST CS_CARD_DATA_MASK		= $07F8		' Mask to get the background card's data.
	SRCFILE "constants.bas",290
	;[291] 
	SRCFILE "constants.bas",291
	;[292] CONST CS_ADVANCE			= $2000		' Advance the colour stack by one position.
	SRCFILE "constants.bas",292
	;[293] 
	SRCFILE "constants.bas",293
	;[294] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",294
	;[295] REM Coloured squares mode.
	SRCFILE "constants.bas",295
	;[296] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",296
	;[297] REM Notes :
	SRCFILE "constants.bas",297
	;[298] REM - Only available in colour stack mode.
	SRCFILE "constants.bas",298
	;[299] REM - Pixels in each BACKTAB card are arranged in the following manner:
	SRCFILE "constants.bas",299
	;[300] REM +-------+-------+
	SRCFILE "constants.bas",300
	;[301] REM | Pixel | Pixel |
	SRCFILE "constants.bas",301
	;[302] REM |   0   |   1   !
	SRCFILE "constants.bas",302
	;[303] REM +-------+-------+
	SRCFILE "constants.bas",303
	;[304] REM | Pixel | Pixel |
	SRCFILE "constants.bas",304
	;[305] REM |   2   |   3   !
	SRCFILE "constants.bas",305
	;[306] REM +-------+-------+
	SRCFILE "constants.bas",306
	;[307] REM
	SRCFILE "constants.bas",307
	;[308] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",308
	;[309] CONST CS_COLOUR_SQUARES_ENABLE	=$1000
	SRCFILE "constants.bas",309
	;[310] CONST CS_PIX0_BLACK				=0
	SRCFILE "constants.bas",310
	;[311] CONST CS_PIX0_BLUE				=1
	SRCFILE "constants.bas",311
	;[312] CONST CS_PIX0_RED				=2
	SRCFILE "constants.bas",312
	;[313] CONST CS_PIX0_TAN				=3
	SRCFILE "constants.bas",313
	;[314] CONST CS_PIX0_DARKGREEN			=4
	SRCFILE "constants.bas",314
	;[315] CONST CS_PIX0_GREEN				=5
	SRCFILE "constants.bas",315
	;[316] CONST CS_PIX0_YELLOW			=6
	SRCFILE "constants.bas",316
	;[317] CONST CS_PIX0_BACKGROUND		=7
	SRCFILE "constants.bas",317
	;[318] CONST CS_PIX1_BLACK				=0
	SRCFILE "constants.bas",318
	;[319] CONST CS_PIX1_BLUE				=1*8
	SRCFILE "constants.bas",319
	;[320] CONST CS_PIX1_RED				=2*8
	SRCFILE "constants.bas",320
	;[321] CONST CS_PIX1_TAN				=3*8
	SRCFILE "constants.bas",321
	;[322] CONST CS_PIX1_DARKGREEN			=4*8
	SRCFILE "constants.bas",322
	;[323] CONST CS_PIX1_GREEN				=5*8
	SRCFILE "constants.bas",323
	;[324] CONST CS_PIX1_YELLOW			=6*8
	SRCFILE "constants.bas",324
	;[325] CONST CS_PIX1_BACKGROUND		=7*8
	SRCFILE "constants.bas",325
	;[326] CONST CS_PIX2_BLACK				=0
	SRCFILE "constants.bas",326
	;[327] CONST CS_PIX2_BLUE				=1*64
	SRCFILE "constants.bas",327
	;[328] CONST CS_PIX2_RED				=2*64
	SRCFILE "constants.bas",328
	;[329] CONST CS_PIX2_TAN				=3*64
	SRCFILE "constants.bas",329
	;[330] CONST CS_PIX2_DARKGREEN			=4*64
	SRCFILE "constants.bas",330
	;[331] CONST CS_PIX2_GREEN				=5*64
	SRCFILE "constants.bas",331
	;[332] CONST CS_PIX2_YELLOW			=6*64
	SRCFILE "constants.bas",332
	;[333] CONST CS_PIX2_BACKGROUND		=7*64
	SRCFILE "constants.bas",333
	;[334] CONST CS_PIX3_BLACK				=0
	SRCFILE "constants.bas",334
	;[335] CONST CS_PIX3_BLUE				=$0200
	SRCFILE "constants.bas",335
	;[336] CONST CS_PIX3_RED				=$0400
	SRCFILE "constants.bas",336
	;[337] CONST CS_PIX3_TAN				=$0600
	SRCFILE "constants.bas",337
	;[338] CONST CS_PIX3_DARKGREEN			=$2000
	SRCFILE "constants.bas",338
	;[339] CONST CS_PIX3_GREEN				=$2200
	SRCFILE "constants.bas",339
	;[340] CONST CS_PIX3_YELLOW			=$2400
	SRCFILE "constants.bas",340
	;[341] CONST CS_PIX3_BACKGROUND		=$2600
	SRCFILE "constants.bas",341
	;[342] CONST CS_PIX_MASK				=CS_COLOUR_SQUARES_ENABLE+CS_PIX0_BACKGROUND+CS_PIX1_BACKGROUND+CS_PIX2_BACKGROUND+CS_PIX3_BACKGROUND
	SRCFILE "constants.bas",342
	;[343] 
	SRCFILE "constants.bas",343
	;[344] CONST CS_PIX_X_MIN				=0		' Minimum x coordinate.
	SRCFILE "constants.bas",344
	;[345] CONST CS_PIX_X_MAX				=39		' Maximum x coordinate.
	SRCFILE "constants.bas",345
	;[346] CONST CS_PIX_Y_MIN				=0		' Minimum Y coordinate.
	SRCFILE "constants.bas",346
	;[347] CONST CS_PIX_Y_MAX				=23		' Maximum Y coordinate.
	SRCFILE "constants.bas",347
	;[348] 
	SRCFILE "constants.bas",348
	;[349] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "constants.bas",349
	;[350] 
	SRCFILE "constants.bas",350
	;[351] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",351
	;[352] REM COLORS - Mode 1 (Foreground Background)
	SRCFILE "constants.bas",352
	;[353] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",353
	;[354] REM Foreground.
	SRCFILE "constants.bas",354
	;[355] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",355
	;[356] REM Notes:
	SRCFILE "constants.bas",356
	;[357] REM - For use with "peek/poke" commands that access BACKTAB.
	SRCFILE "constants.bas",357
	;[358] REM - Only one foreground colour permitted per background card.
	SRCFILE "constants.bas",358
	;[359] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",359
	;[360] CONST FG_BLACK				= $0000
	SRCFILE "constants.bas",360
	;[361] CONST FG_BLUE				= $0001
	SRCFILE "constants.bas",361
	;[362] CONST FG_RED				= $0002
	SRCFILE "constants.bas",362
	;[363] CONST FG_TAN				= $0003
	SRCFILE "constants.bas",363
	;[364] CONST FG_DARKGREEN			= $0004
	SRCFILE "constants.bas",364
	;[365] CONST FG_GREEN				= $0005
	SRCFILE "constants.bas",365
	;[366] CONST FG_YELLOW				= $0006
	SRCFILE "constants.bas",366
	;[367] CONST FG_WHITE				= $0007
	SRCFILE "constants.bas",367
	;[368] 
	SRCFILE "constants.bas",368
	;[369] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",369
	;[370] REM Background.
	SRCFILE "constants.bas",370
	;[371] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",371
	;[372] REM Notes:
	SRCFILE "constants.bas",372
	;[373] REM - For use with "peek/poke" commands that access BACKTAB.
	SRCFILE "constants.bas",373
	;[374] REM - Only one background colour permitted per background card.
	SRCFILE "constants.bas",374
	;[375] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",375
	;[376] CONST BG_BLACK				= $0000
	SRCFILE "constants.bas",376
	;[377] CONST BG_BLUE				= $0200
	SRCFILE "constants.bas",377
	;[378] CONST BG_RED				= $0400
	SRCFILE "constants.bas",378
	;[379] CONST BG_TAN				= $0600
	SRCFILE "constants.bas",379
	;[380] CONST BG_DARKGREEN			= $2000
	SRCFILE "constants.bas",380
	;[381] CONST BG_GREEN				= $2200
	SRCFILE "constants.bas",381
	;[382] CONST BG_YELLOW				= $2400
	SRCFILE "constants.bas",382
	;[383] CONST BG_WHITE				= $2600
	SRCFILE "constants.bas",383
	;[384] CONST BG_GREY				= $1000
	SRCFILE "constants.bas",384
	;[385] CONST BG_CYAN				= $1200
	SRCFILE "constants.bas",385
	;[386] CONST BG_ORANGE				= $1400
	SRCFILE "constants.bas",386
	;[387] CONST BG_BROWN				= $1600
	SRCFILE "constants.bas",387
	;[388] CONST BG_PINK				= $3000
	SRCFILE "constants.bas",388
	;[389] CONST BG_LIGHTBLUE			= $3200
	SRCFILE "constants.bas",389
	;[390] CONST BG_YELLOWGREEN		= $3400
	SRCFILE "constants.bas",390
	;[391] CONST BG_PURPLE				= $3600
	SRCFILE "constants.bas",391
	;[392] 
	SRCFILE "constants.bas",392
	;[393] CONST FGBG_CARD_DATA_MASK	= $01F8		' Mask to get the background card's data.
	SRCFILE "constants.bas",393
	;[394] 
	SRCFILE "constants.bas",394
	;[395] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "constants.bas",395
	;[396] 
	SRCFILE "constants.bas",396
	;[397] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",397
	;[398] REM Sprites.
	SRCFILE "constants.bas",398
	;[399] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",399
	;[400] REM Note: For use with "sprite" command.
	SRCFILE "constants.bas",400
	;[401] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",401
	;[402] REM X
	SRCFILE "constants.bas",402
	;[403] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",403
	;[404] REM Note: Add these constants to the sprite command's X parameter.
	SRCFILE "constants.bas",404
	;[405] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",405
	;[406] CONST HIT					= $0100		' Enable the sprite's collision detection.
	SRCFILE "constants.bas",406
	;[407] CONST VISIBLE				= $0200		' Make the sprite visible.
	SRCFILE "constants.bas",407
	;[408] CONST ZOOMX2				= $0400		' Make the sprite twice the width.
	SRCFILE "constants.bas",408
	;[409] 
	SRCFILE "constants.bas",409
	;[410] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",410
	;[411] REM Y
	SRCFILE "constants.bas",411
	;[412] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",412
	;[413] REM Note: Add these constants to the sprite command's Y parameter.
	SRCFILE "constants.bas",413
	;[414] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",414
	;[415] CONST DOUBLEY				= $0080		' Make a double height sprite (with 2 GRAM cards).
	SRCFILE "constants.bas",415
	;[416] CONST ZOOMY2				= $0100		' Make the sprite twice (x2) the normal height.
	SRCFILE "constants.bas",416
	;[417] CONST ZOOMY4				= $0200		' Make the sprite quadruple (x4) the normal height.
	SRCFILE "constants.bas",417
	;[418] CONST ZOOMY8				= $0300		' Make the sprite octuple (x8) the normal height.
	SRCFILE "constants.bas",418
	;[419] CONST FLIPX					= $0400		' Flip/mirror the sprite in X.
	SRCFILE "constants.bas",419
	;[420] CONST FLIPY					= $0800		' Flip/mirror the sprite in Y.
	SRCFILE "constants.bas",420
	;[421] CONST MIRROR				= $0C00		' Flip/mirror the sprite in both X and Y.
	SRCFILE "constants.bas",421
	;[422] 
	SRCFILE "constants.bas",422
	;[423] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",423
	;[424] REM A
	SRCFILE "constants.bas",424
	;[425] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",425
	;[426] REM Notes:
	SRCFILE "constants.bas",426
	;[427] REM - Combine to create the sprite command's A parameter.
	SRCFILE "constants.bas",427
	;[428] REM - Only one colour per sprite.
	SRCFILE "constants.bas",428
	;[429] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",429
	;[430] CONST GRAM					= $0800		' Sprite's data is located in GRAM.
	SRCFILE "constants.bas",430
	;[431] CONST BEHIND				= $2000		' Sprite is behind the background.
	SRCFILE "constants.bas",431
	;[432] CONST SPR_BLACK				= $0000
	SRCFILE "constants.bas",432
	;[433] CONST SPR_BLUE				= $0001
	SRCFILE "constants.bas",433
	;[434] CONST SPR_RED				= $0002
	SRCFILE "constants.bas",434
	;[435] CONST SPR_TAN				= $0003
	SRCFILE "constants.bas",435
	;[436] CONST SPR_DARKGREEN			= $0004
	SRCFILE "constants.bas",436
	;[437] CONST SPR_GREEN				= $0005
	SRCFILE "constants.bas",437
	;[438] CONST SPR_YELLOW			= $0006
	SRCFILE "constants.bas",438
	;[439] CONST SPR_WHITE				= $0007
	SRCFILE "constants.bas",439
	;[440] CONST SPR_GREY				= $1000
	SRCFILE "constants.bas",440
	;[441] CONST SPR_CYAN				= $1001
	SRCFILE "constants.bas",441
	;[442] CONST SPR_ORANGE			= $1002
	SRCFILE "constants.bas",442
	;[443] CONST SPR_BROWN				= $1003
	SRCFILE "constants.bas",443
	;[444] CONST SPR_PINK				= $1004
	SRCFILE "constants.bas",444
	;[445] CONST SPR_LIGHTBLUE			= $1005
	SRCFILE "constants.bas",445
	;[446] CONST SPR_YELLOWGREEN		= $1006
	SRCFILE "constants.bas",446
	;[447] CONST SPR_PURPLE			= $1007
	SRCFILE "constants.bas",447
	;[448] 
	SRCFILE "constants.bas",448
	;[449] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",449
	;[450] REM GRAM numbers.
	SRCFILE "constants.bas",450
	;[451] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",451
	;[452] REM Note: For use in the sprite command's parameter A.
	SRCFILE "constants.bas",452
	;[453] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",453
	;[454] CONST SPR00 				= $0800
	SRCFILE "constants.bas",454
	;[455] CONST SPR01 				= $0808
	SRCFILE "constants.bas",455
	;[456] CONST SPR02 				= $0810
	SRCFILE "constants.bas",456
	;[457] CONST SPR03 				= $0818
	SRCFILE "constants.bas",457
	;[458] CONST SPR04 				= $0820
	SRCFILE "constants.bas",458
	;[459] CONST SPR05 				= $0828
	SRCFILE "constants.bas",459
	;[460] CONST SPR06 				= $0830
	SRCFILE "constants.bas",460
	;[461] CONST SPR07 				= $0838
	SRCFILE "constants.bas",461
	;[462] CONST SPR08 				= $0840
	SRCFILE "constants.bas",462
	;[463] CONST SPR09 				= $0848
	SRCFILE "constants.bas",463
	;[464] CONST SPR10 				= $0850
	SRCFILE "constants.bas",464
	;[465] CONST SPR11 				= $0858
	SRCFILE "constants.bas",465
	;[466] CONST SPR12 				= $0860
	SRCFILE "constants.bas",466
	;[467] CONST SPR13 				= $0868
	SRCFILE "constants.bas",467
	;[468] CONST SPR14 				= $0870
	SRCFILE "constants.bas",468
	;[469] CONST SPR15 				= $0878
	SRCFILE "constants.bas",469
	;[470] CONST SPR16 				= $0880
	SRCFILE "constants.bas",470
	;[471] CONST SPR17 				= $0888
	SRCFILE "constants.bas",471
	;[472] CONST SPR18 				= $0890
	SRCFILE "constants.bas",472
	;[473] CONST SPR19 				= $0898
	SRCFILE "constants.bas",473
	;[474] CONST SPR20 				= $08A0
	SRCFILE "constants.bas",474
	;[475] CONST SPR21 				= $08A8
	SRCFILE "constants.bas",475
	;[476] CONST SPR22 				= $08B0
	SRCFILE "constants.bas",476
	;[477] CONST SPR23 				= $08B8
	SRCFILE "constants.bas",477
	;[478] CONST SPR24 				= $08C0
	SRCFILE "constants.bas",478
	;[479] CONST SPR25 				= $08C8
	SRCFILE "constants.bas",479
	;[480] CONST SPR26 				= $08D0
	SRCFILE "constants.bas",480
	;[481] CONST SPR27 				= $08D8
	SRCFILE "constants.bas",481
	;[482] CONST SPR28 				= $08E0
	SRCFILE "constants.bas",482
	;[483] CONST SPR29 				= $08E8
	SRCFILE "constants.bas",483
	;[484] CONST SPR30 				= $08F0
	SRCFILE "constants.bas",484
	;[485] CONST SPR31 				= $08F8
	SRCFILE "constants.bas",485
	;[486] CONST SPR32 				= $0900
	SRCFILE "constants.bas",486
	;[487] CONST SPR33 				= $0908
	SRCFILE "constants.bas",487
	;[488] CONST SPR34 				= $0910
	SRCFILE "constants.bas",488
	;[489] CONST SPR35 				= $0918
	SRCFILE "constants.bas",489
	;[490] CONST SPR36 				= $0920
	SRCFILE "constants.bas",490
	;[491] CONST SPR37 				= $0928
	SRCFILE "constants.bas",491
	;[492] CONST SPR38 				= $0930
	SRCFILE "constants.bas",492
	;[493] CONST SPR39 				= $0938
	SRCFILE "constants.bas",493
	;[494] CONST SPR40 				= $0940
	SRCFILE "constants.bas",494
	;[495] CONST SPR41 				= $0948
	SRCFILE "constants.bas",495
	;[496] CONST SPR42 				= $0950
	SRCFILE "constants.bas",496
	;[497] CONST SPR43 				= $0958
	SRCFILE "constants.bas",497
	;[498] CONST SPR44 				= $0960
	SRCFILE "constants.bas",498
	;[499] CONST SPR45 				= $0968
	SRCFILE "constants.bas",499
	;[500] CONST SPR46 				= $0970
	SRCFILE "constants.bas",500
	;[501] CONST SPR47 				= $0978
	SRCFILE "constants.bas",501
	;[502] CONST SPR48 				= $0980
	SRCFILE "constants.bas",502
	;[503] CONST SPR49 				= $0988
	SRCFILE "constants.bas",503
	;[504] CONST SPR50 				= $0990
	SRCFILE "constants.bas",504
	;[505] CONST SPR51 				= $0998
	SRCFILE "constants.bas",505
	;[506] CONST SPR52 				= $09A0
	SRCFILE "constants.bas",506
	;[507] CONST SPR53 				= $09A8
	SRCFILE "constants.bas",507
	;[508] CONST SPR54 				= $09B0
	SRCFILE "constants.bas",508
	;[509] CONST SPR55 				= $09B8
	SRCFILE "constants.bas",509
	;[510] CONST SPR56 				= $09C0
	SRCFILE "constants.bas",510
	;[511] CONST SPR57 				= $09C8
	SRCFILE "constants.bas",511
	;[512] CONST SPR58 				= $09D0
	SRCFILE "constants.bas",512
	;[513] CONST SPR59 				= $09D8
	SRCFILE "constants.bas",513
	;[514] CONST SPR60 				= $09E0
	SRCFILE "constants.bas",514
	;[515] CONST SPR61 				= $09E8
	SRCFILE "constants.bas",515
	;[516] CONST SPR62 				= $09F0
	SRCFILE "constants.bas",516
	;[517] CONST SPR63 				= $09F8
	SRCFILE "constants.bas",517
	;[518] 
	SRCFILE "constants.bas",518
	;[519] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",519
	;[520] REM Sprite collision.
	SRCFILE "constants.bas",520
	;[521] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",521
	;[522] REM Notes:
	SRCFILE "constants.bas",522
	;[523] REM - For use with variables COL0, COL1, COL2, COL3, COL4, COL5, COL6 and COL7.
	SRCFILE "constants.bas",523
	;[524] REM - More than one collision can occur simultaneously.
	SRCFILE "constants.bas",524
	;[525] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",525
	;[526] CONST HIT_SPRITE0			= $0001		' Sprite collided with sprite 0.
	SRCFILE "constants.bas",526
	;[527] CONST HIT_SPRITE1			= $0002		' Sprite collided with sprite 1.
	SRCFILE "constants.bas",527
	;[528] CONST HIT_SPRITE2			= $0004		' Sprite collided with sprite 2.
	SRCFILE "constants.bas",528
	;[529] CONST HIT_SPRITE3			= $0008		' Sprite collided with sprite 3.
	SRCFILE "constants.bas",529
	;[530] CONST HIT_SPRITE4			= $0010		' Sprite collided with sprite 4.
	SRCFILE "constants.bas",530
	;[531] CONST HIT_SPRITE5			= $0020		' Sprite collided with sprite 5.
	SRCFILE "constants.bas",531
	;[532] CONST HIT_SPRITE6			= $0040		' Sprite collided with sprite 6.
	SRCFILE "constants.bas",532
	;[533] CONST HIT_SPRITE7			= $0080		' Sprite collided with sprite 7.
	SRCFILE "constants.bas",533
	;[534] CONST HIT_BACKGROUND		= $0100		' Sprite collided with a background pixel.
	SRCFILE "constants.bas",534
	;[535] CONST HIT_BORDER			= $0200		' Sprite collided with the top/bottom/left/right border.
	SRCFILE "constants.bas",535
	;[536] 
	SRCFILE "constants.bas",536
	;[537] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "constants.bas",537
	;[538] 
	SRCFILE "constants.bas",538
	;[539] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",539
	;[540] REM DISC - Compass.
	SRCFILE "constants.bas",540
	;[541] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",541
	;[542] REM   NW         N         NE
	SRCFILE "constants.bas",542
	;[543] REM     \   NNW  |  NNE   /
	SRCFILE "constants.bas",543
	;[544] REM       \      |      /
	SRCFILE "constants.bas",544
	;[545] REM         \    |    /
	SRCFILE "constants.bas",545
	;[546] REM    WNW    \  |  /    ENE
	SRCFILE "constants.bas",546
	;[547] REM             \|/
	SRCFILE "constants.bas",547
	;[548] REM  W ----------+---------- E
	SRCFILE "constants.bas",548
	;[549] REM             /|\ 
	SRCFILE "constants.bas",549
	;[550] REM    WSW    /  |  \    ESE
	SRCFILE "constants.bas",550
	;[554] REM         /    |    REM       /      |      REM     /   SSW  |  SSE   REM   SW         S         SE
	SRCFILE "constants.bas",554
	;[555] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",555
	;[556] REM Notes:
	SRCFILE "constants.bas",556
	;[557] REM - North points upwards on the hand controller.
	SRCFILE "constants.bas",557
	;[558] REM - Directions are listed in a clockwise manner.
	SRCFILE "constants.bas",558
	;[559] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",559
	;[560] CONST DISC_NORTH			= $0004
	SRCFILE "constants.bas",560
	;[561] CONST DISC_NORTH_NORTH_EAST = $0014
	SRCFILE "constants.bas",561
	;[562] CONST DISC_NORTH_EAST		= $0016
	SRCFILE "constants.bas",562
	;[563] CONST DISC_EAST_NORTH_EAST	= $0006
	SRCFILE "constants.bas",563
	;[564] CONST DISC_EAST				= $0002
	SRCFILE "constants.bas",564
	;[565] CONST DISC_EAST_SOUTH_EAST	= $0012
	SRCFILE "constants.bas",565
	;[566] CONST DISC_SOUTH_EAST		= $0013
	SRCFILE "constants.bas",566
	;[567] CONST DISC_SOUTH_SOUTH_EAST	= $0003
	SRCFILE "constants.bas",567
	;[568] CONST DISC_SOUTH			= $0001
	SRCFILE "constants.bas",568
	;[569] CONST DISC_SOUTH_SOUTH_WEST	= $0011
	SRCFILE "constants.bas",569
	;[570] CONST DISC_SOUTH_WEST		= $0019
	SRCFILE "constants.bas",570
	;[571] CONST DISC_WEST_SOUTH_WEST	= $0009
	SRCFILE "constants.bas",571
	;[572] CONST DISC_WEST				= $0008
	SRCFILE "constants.bas",572
	;[573] CONST DISC_WEST_NORTH_WEST	= $0018
	SRCFILE "constants.bas",573
	;[574] CONST DISC_NORTH_WEST		= $001C
	SRCFILE "constants.bas",574
	;[575] CONST DISC_NORTH_NORTH_WEST	= $000C
	SRCFILE "constants.bas",575
	;[576] 
	SRCFILE "constants.bas",576
	;[577] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",577
	;[578] REM DISC - Compass abbreviated versions.
	SRCFILE "constants.bas",578
	;[579] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",579
	;[580] CONST DISC_N				= $0004
	SRCFILE "constants.bas",580
	;[581] CONST DISC_NNE 				= $0014
	SRCFILE "constants.bas",581
	;[582] CONST DISC_NE				= $0016
	SRCFILE "constants.bas",582
	;[583] CONST DISC_ENE				= $0006
	SRCFILE "constants.bas",583
	;[584] CONST DISC_E				= $0002
	SRCFILE "constants.bas",584
	;[585] CONST DISC_ESE				= $0012
	SRCFILE "constants.bas",585
	;[586] CONST DISC_SE				= $0013
	SRCFILE "constants.bas",586
	;[587] CONST DISC_SSE				= $0003
	SRCFILE "constants.bas",587
	;[588] CONST DISC_S				= $0001
	SRCFILE "constants.bas",588
	;[589] CONST DISC_SSW				= $0011
	SRCFILE "constants.bas",589
	;[590] CONST DISC_SW				= $0019
	SRCFILE "constants.bas",590
	;[591] CONST DISC_WSW				= $0009
	SRCFILE "constants.bas",591
	;[592] CONST DISC_W				= $0008
	SRCFILE "constants.bas",592
	;[593] CONST DISC_WNW				= $0018
	SRCFILE "constants.bas",593
	;[594] CONST DISC_NW				= $001C
	SRCFILE "constants.bas",594
	;[595] CONST DISC_NNW				= $000C
	SRCFILE "constants.bas",595
	;[596] 
	SRCFILE "constants.bas",596
	;[597] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",597
	;[598] REM DISC - Directions.
	SRCFILE "constants.bas",598
	;[599] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",599
	;[600] CONST DISC_UP				= $0004
	SRCFILE "constants.bas",600
	;[601] CONST DISC_UP_RIGHT			= $0016		' Up and right diagonal.
	SRCFILE "constants.bas",601
	;[602] CONST DISC_RIGHT			= $0002
	SRCFILE "constants.bas",602
	;[603] CONST DISC_DOWN_RIGHT		= $0013		' Down  and right diagonal.
	SRCFILE "constants.bas",603
	;[604] CONST DISC_DOWN				= $0001
	SRCFILE "constants.bas",604
	;[605] CONST DISC_DOWN_LEFT		= $0019		' Down and left diagonal.
	SRCFILE "constants.bas",605
	;[606] CONST DISC_LEFT				= $0008
	SRCFILE "constants.bas",606
	;[607] CONST DISC_UP_LEFT			= $001C		' Up and left diagonal.
	SRCFILE "constants.bas",607
	;[608] 
	SRCFILE "constants.bas",608
	;[609] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",609
	;[610] REM DISK - Mask.
	SRCFILE "constants.bas",610
	;[611] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",611
	;[612] CONST DISK_MASK				= $001F
	SRCFILE "constants.bas",612
	;[613] 
	SRCFILE "constants.bas",613
	;[614] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",614
	;[615] REM Controller - Keypad.
	SRCFILE "constants.bas",615
	;[616] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",616
	;[617] CONST KEYPAD_0				= 72
	SRCFILE "constants.bas",617
	;[618] CONST KEYPAD_1				= 129
	SRCFILE "constants.bas",618
	;[619] CONST KEYPAD_2				= 65
	SRCFILE "constants.bas",619
	;[620] CONST KEYPAD_3				= 33
	SRCFILE "constants.bas",620
	;[621] CONST KEYPAD_4				= 130
	SRCFILE "constants.bas",621
	;[622] CONST KEYPAD_5				= 66
	SRCFILE "constants.bas",622
	;[623] CONST KEYPAD_6				= 34
	SRCFILE "constants.bas",623
	;[624] CONST KEYPAD_7				= 132
	SRCFILE "constants.bas",624
	;[625] CONST KEYPAD_8				= 68
	SRCFILE "constants.bas",625
	;[626] CONST KEYPAD_9				= 36
	SRCFILE "constants.bas",626
	;[627] CONST KEYPAD_CLEAR			= 136
	SRCFILE "constants.bas",627
	;[628] CONST KEYPAD_ENTER			= 40
	SRCFILE "constants.bas",628
	;[629] 
	SRCFILE "constants.bas",629
	;[630] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",630
	;[631] REM Controller - Pause buttons (1+9 or 3+7 held down simultaneously).
	SRCFILE "constants.bas",631
	;[632] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",632
	;[633] REM Notes:
	SRCFILE "constants.bas",633
	;[634] REM - Key codes for 3+7 and 1+9 are the same (165).
	SRCFILE "constants.bas",634
	;[635] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",635
	;[636] CONST KEYPAD_PAUSE			= (KEYPAD_1 XOR KEYPAD_9)
	SRCFILE "constants.bas",636
	;[637] 
	SRCFILE "constants.bas",637
	;[638] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",638
	;[639] REM Controller - Side buttons.
	SRCFILE "constants.bas",639
	;[640] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",640
	;[641] CONST BUTTON_TOP_LEFT		= $A0		' Top left and top right are the same button.
	SRCFILE "constants.bas",641
	;[642] CONST BUTTON_TOP_RIGHT		= $A0		' Note: Bit 6 is low. 
	SRCFILE "constants.bas",642
	;[643] CONST BUTTON_BOTTOM_LEFT	= $60		' Note: Bit 7 is low.
	SRCFILE "constants.bas",643
	;[644] CONST BUTTON_BOTTOM_RIGHT	= $C0		' Note: Bit 5 is low
	SRCFILE "constants.bas",644
	;[645] 
	SRCFILE "constants.bas",645
	;[646] REM Abbreviated versions.
	SRCFILE "constants.bas",646
	;[647] CONST BUTTON_1				= $A0		' Top left or top right.
	SRCFILE "constants.bas",647
	;[648] CONST BUTTON_2				= $60		' Bottom left.
	SRCFILE "constants.bas",648
	;[649] CONST BUTTON_3				= $C0		' Bottom right.
	SRCFILE "constants.bas",649
	;[650] 
	SRCFILE "constants.bas",650
	;[651] REM Mask.
	SRCFILE "constants.bas",651
	;[652] CONST BUTTON_MASK			= $E0
	SRCFILE "constants.bas",652
	;[653] 
	SRCFILE "constants.bas",653
	;[654] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "constants.bas",654
	;[655] 
	SRCFILE "constants.bas",655
	;[656] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",656
	;[657] REM Programmable Sound Generator (PSG)
	SRCFILE "constants.bas",657
	;[658] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",658
	;[659] REM Notes:
	SRCFILE "constants.bas",659
	;[660] REM - For use with the SOUND command
	SRCFILE "constants.bas",660
	;[661] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",661
	;[662] 
	SRCFILE "constants.bas",662
	;[663] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",663
	;[664] REM Internal sound hardware.
	SRCFILE "constants.bas",664
	;[665] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",665
	;[666] CONST PSG_CHANNELA		=0
	SRCFILE "constants.bas",666
	;[667] CONST PSG_CHANNELB		=1
	SRCFILE "constants.bas",667
	;[668] CONST PSG_CHANNELC		=2
	SRCFILE "constants.bas",668
	;[669] CONST PSG_ENVELOPE		=3
	SRCFILE "constants.bas",669
	;[670] CONST PSG_MIXER			=4
	SRCFILE "constants.bas",670
	;[671] 
	SRCFILE "constants.bas",671
	;[672] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",672
	;[673] REM ECS sound hardware.
	SRCFILE "constants.bas",673
	;[674] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",674
	;[675] CONST PSG_ECS_CHANNELA	=5
	SRCFILE "constants.bas",675
	;[676] CONST PSG_ECS_CHANNELB	=6
	SRCFILE "constants.bas",676
	;[677] CONST PSG_ECS_CHANNELC	=7
	SRCFILE "constants.bas",677
	;[678] CONST PSG_ECS_ENVELOPE	=8
	SRCFILE "constants.bas",678
	;[679] CONST PSG_ECS_MIXER		=9
	SRCFILE "constants.bas",679
	;[680] 
	SRCFILE "constants.bas",680
	;[681] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",681
	;[682] REM PSG - Volume control.
	SRCFILE "constants.bas",682
	;[683] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",683
	;[684] REM Notes:
	SRCFILE "constants.bas",684
	;[685] REM - For use in the volume field of the SOUND command.
	SRCFILE "constants.bas",685
	;[686] REM - Internal channels: PSG_CHANNELA, PSG_CHANNELB, PSG_CHANNELC
	SRCFILE "constants.bas",686
	;[687] REM - ECS channels: PSG_ECS_CHANNELA, PSG_ECS_CHANNELB, PSG_ECS_CHANNELC
	SRCFILE "constants.bas",687
	;[688] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",688
	;[689] CONST PSG_VOLUME_MAX		=15	' Maximum channel volume.
	SRCFILE "constants.bas",689
	;[690] CONST PSG_ENVELOPE_ENABLE	=48	' Channel volume is controlled by envelope generator.
	SRCFILE "constants.bas",690
	;[691] 
	SRCFILE "constants.bas",691
	;[692] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",692
	;[693] REM PSG - Mixer control.
	SRCFILE "constants.bas",693
	;[694] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",694
	;[695] REM Notes:
	SRCFILE "constants.bas",695
	;[696] REM - Internal channel: PSG_MIXER
	SRCFILE "constants.bas",696
	;[697] REM - EXS channel: PSG_ECS_MIXER
	SRCFILE "constants.bas",697
	;[698] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",698
	;[699] CONST PSG_TONE_CHANNELA_DISABLE		=$01	' Disable channel A tone.
	SRCFILE "constants.bas",699
	;[700] CONST PSG_TONE_CHANNELB_DISABLE		=$02	' Disable channel B tone.
	SRCFILE "constants.bas",700
	;[701] CONST PSG_TONE_CHANNELC_DISABLE		=$04	' Disable channel C tone.
	SRCFILE "constants.bas",701
	;[702] CONST PSG_NOISE_CHANNELA_DISABLE	=$08	' Disable channel A noise.
	SRCFILE "constants.bas",702
	;[703] CONST PSG_NOISE_CHANNELB_DISABLE	=$10	' Disable channel B noise.
	SRCFILE "constants.bas",703
	;[704] CONST PSG_NOISE_CHANNELC_DISABLE	=$20	' Disable channel C noise.
	SRCFILE "constants.bas",704
	;[705] CONST PSG_MIXER_DEFAULT				=$38 	' All notes enabled. all noise disabled.
	SRCFILE "constants.bas",705
	;[706] 
	SRCFILE "constants.bas",706
	;[707] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",707
	;[708] REM PSG - Envelope control.
	SRCFILE "constants.bas",708
	;[709] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",709
	;[710] REM Notes:
	SRCFILE "constants.bas",710
	;[711] REM - Internal channel: PSG_ENVELOPE
	SRCFILE "constants.bas",711
	;[712] REM - EXS channel: PSG_ECS_ENVELOPE
	SRCFILE "constants.bas",712
	;[713] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",713
	;[714] CONST PSG_ENVELOPE_HOLD								=$01
	SRCFILE "constants.bas",714
	;[715] CONST PSG_ENVELOPE_ALTERNATE						=$02
	SRCFILE "constants.bas",715
	;[716] CONST PSG_ENVELOPE_ATTACK							=$04
	SRCFILE "constants.bas",716
	;[717] CONST PSG_ENVELOPE_CONTINUE							=$08
	SRCFILE "constants.bas",717
	;[718] CONST PSG_ENVELOPE_SINGLE_SHOT_RAMP_DOWN_AND_OFF	=$00 '\______
	SRCFILE "constants.bas",718
	;[719] CONST PSG_ENVELOPE_SINGLE_SHOT_RAMP_UP_AND_OFF		=$04 '/______
	SRCFILE "constants.bas",719
	;[722] CONST PSG_ENVELOPE_CYCLE_RAMP_DOWN_SAWTOOTH			=$08 '\\\\\\CONST PSG_ENVELOPE_CYCLE_RAMP_DOWN_TRIANGLE			=$0A '\/\/\/CONST PSG_ENVELOPE_SINGLE_SHOT_RAMP_DOWN_AND_MAX	=$0B '\^^^^^^
	SRCFILE "constants.bas",722
	;[723] CONST PSG_ENVELOPE_CYCLE_RAMP_UP_SAWTOOTH			=$0C '///////
	SRCFILE "constants.bas",723
	;[724] CONST PSG_ENVELOPE_SINGLE_SHOT_RAMP_UP_AND_MAX		=$0D '/^^^^^^
	SRCFILE "constants.bas",724
	;[725] CONST PSG_ENVELOPE_CYCLE_RAMP_UP_TRIANGLE			=$0E '/\/\/\/
	SRCFILE "constants.bas",725
	;[726] 
	SRCFILE "constants.bas",726
	;[727] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "constants.bas",727
	;[728] 
	SRCFILE "constants.bas",728
	;[729] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",729
	;[730] REM Useful functions.
	SRCFILE "constants.bas",730
	;[731] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",731
	;[732] DEF FN screenpos(aColumn, aRow)		= (((aRow)*BACKGROUND_COLUMNS)+(aColumn))
	SRCFILE "constants.bas",732
	;[733] DEF FN screenaddr(aColumn, aRow)	= (BACKTAB_ADDR+(((aRow)*BACKGROUND_COLUMNS)+(aColumn)))
	SRCFILE "constants.bas",733
	;[734] 
	SRCFILE "constants.bas",734
	;[735] DEF FN setspritex(aSpriteNo,anXPosition)	= #mobshadow(aSpriteNo)=(#mobshadow(aSpriteNo) and $ff00)+anXPosition
	SRCFILE "constants.bas",735
	;[736] DEF FN setspritey(aSpriteNo,aYPosition)		= #mobshadow(aSpriteNo+8)=(#mobshadow(aSpriteNo+8) and $ff80)+aYPosition
	SRCFILE "constants.bas",736
	;[737] DEF FN resetsprite(aSpriteNo)				= sprite aSpriteNo, 0, 0, 0
	SRCFILE "constants.bas",737
	;[738] 
	SRCFILE "constants.bas",738
	;[739] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "constants.bas",739
	;[740] 
	SRCFILE "constants.bas",740
	;[741] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",741
	;[742] REM END
	SRCFILE "constants.bas",742
	;[743] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",743
	;ENDFILE
	;FILE texas.bas
	;[35]     INCLUDE "input.bas"
	SRCFILE "texas.bas",35
	;FILE input.bas
	;[1] ' ===========================================================================
	SRCFILE "input.bas",1
	;[2] ' input.bas -- hand controller decoding.
	SRCFILE "input.bas",2
	;[3] '
	SRCFILE "input.bas",3
	;[4] ' Shared verbatim by every FujiNet Intellivision client (5 Card Stud, Texas
	SRCFILE "input.bas",4
	;[5] ' Hold'Em, Fujitzee, Battleship, Fujirkle). Keep the copies byte-identical.
	SRCFILE "input.bas",5
	;[6] '
	SRCFILE "input.bas",6
	;[7] ' ---------------------------------------------------------------------------
	SRCFILE "input.bas",7
	;[8] ' Why this file exists
	SRCFILE "input.bas",8
	;[9] ' ---------------------------------------------------------------------------
	SRCFILE "input.bas",9
	;[10] ' The hand controller multiplexes the disc, the three action buttons and the
	SRCFILE "input.bas",10
	;[11] ' 12-key keypad onto the same eight lines at $01FF. A keypad press grounds one
	SRCFILE "input.bas",11
	;[12] ' "row" line (bit 7/6/5) and one "column" line (bit 3/2/1/0) -- and those
	SRCFILE "input.bas",12
	;[13] ' column lines are the *same* lines the disc uses.
	SRCFILE "input.bas",13
	;[14] '
	SRCFILE "input.bas",14
	;[15] ' IntyBASIC's CONT1.LEFT / .UP / .BUTTON accessors are naive bit masks over
	SRCFILE "input.bas",15
	;[16] ' that raw byte (MVI $01FF / XORI #255 / ANDI #mask), so every keypad press
	SRCFILE "input.bas",16
	;[17] ' aliases straight onto them. Using the constants from constants.bas:
	SRCFILE "input.bas",17
	;[18] '
	SRCFILE "input.bas",18
	;[19] '   KEYPAD_CLEAR = $88 -> AND DISC_LEFT ($08) = $08 -> CONT1.LEFT   is true
	SRCFILE "input.bas",19
	;[20] '                      -> AND BUTTON_MASK($E0) = $80 -> CONT1.BUTTON is true
	SRCFILE "input.bas",20
	;[21] '   KEYPAD_ENTER = $28 -> also LEFT, also BUTTON
	SRCFILE "input.bas",21
	;[22] '   KEYPAD_1     = $81 -> DOWN + BUTTON
	SRCFILE "input.bas",22
	;[23] '   KEYPAD_4     = $82 -> RIGHT + BUTTON
	SRCFILE "input.bas",23
	;[24] '   KEYPAD_7     = $84 -> UP + BUTTON        ...and so on for all twelve keys.
	SRCFILE "input.bas",24
	;[25] '
	SRCFILE "input.bas",25
	;[26] ' That is why CLEAR used to fight the play cursor: CONT1.LEFT goes true the
	SRCFILE "input.bas",26
	;[27] ' instant the key is down, while CONT1.KEY only updates inside WAIT once three
	SRCFILE "input.bas",27
	;[28] ' consecutive frames agree, so the spurious cursor move always won the race --
	SRCFILE "input.bas",28
	;[29] ' the move handler consumed the press and re-entered its loop before the
	SRCFILE "input.bas",29
	;[30] ' CONT1.KEY test was ever reached. The IntyBASIC manual notes the hazard under
	SRCFILE "input.bas",30
	;[31] ' CONT1.KEY ("Because movements can be taken as keys, it's suggested to wait
	SRCFILE "input.bas",31
	;[32] ' for CONT1.KEY to contain 12 before waiting for a key").
	SRCFILE "input.bas",32
	;[33] '
	SRCFILE "input.bas",33
	;[34] ' ---------------------------------------------------------------------------
	SRCFILE "input.bas",34
	;[35] ' How the reading is disambiguated
	SRCFILE "input.bas",35
	;[36] ' ---------------------------------------------------------------------------
	SRCFILE "input.bas",36
	;[37] ' Count the row bits. Each of the three action buttons grounds *two* of them
	SRCFILE "input.bas",37
	;[38] ' (BUTTON_1 = $A0 top, BUTTON_2 = $60 bottom-left, BUTTON_3 = $C0
	SRCFILE "input.bas",38
	;[39] ' bottom-right); a keypad key grounds exactly *one*; the disc alone grounds
	SRCFILE "input.bas",39
	;[40] ' none. So:
	SRCFILE "input.bas",40
	;[41] '
	SRCFILE "input.bas",41
	;[42] '   no row bits      -> disc only: publish inp_dir.
	SRCFILE "input.bas",42
	;[43] '   one row bit      -> a keypad key is down: publish neither disc nor button,
	SRCFILE "input.bas",43
	;[44] '                       because both are aliases of the key itself.
	SRCFILE "input.bas",44
	;[45] '   two row bits     -> a real button, and any low bits alongside it are a
	SRCFILE "input.bas",45
	;[46] '                       genuine simultaneous disc reading, so publish both.
	SRCFILE "input.bas",46
	;[47] '
	SRCFILE "input.bas",47
	;[48] ' Testing the row-bit count this way (rather than "any low bit and any high
	SRCFILE "input.bas",48
	;[49] ' bit at once") is what keeps a real button-plus-disc hold working -- $A8 is
	SRCFILE "input.bas",49
	;[50] ' the top button with the disc held left, and battleship's ship placement
	SRCFILE "input.bas",50
	;[51] ' relies on that combination staying readable.
	SRCFILE "input.bas",51
	;[52] '
	SRCFILE "input.bas",52
	;[53] ' Two keypad keys at once still alias to a button pattern (1+9 and 3+7 both
	SRCFILE "input.bas",53
	;[54] ' give $A5, the EXEC's pause combo). That is inherent to the matrix and
	SRCFILE "input.bas",54
	;[55] ' nothing here uses it.
	SRCFILE "input.bas",55
	;[56] '
	SRCFILE "input.bas",56
	;[57] ' ---------------------------------------------------------------------------
	SRCFILE "input.bas",57
	;[58] ' Usage
	SRCFILE "input.bas",58
	;[59] ' ---------------------------------------------------------------------------
	SRCFILE "input.bas",59
	;[60] ' Call GOSUB read_input exactly once immediately after every WAIT in a loop
	SRCFILE "input.bas",60
	;[61] ' that reads input. It must follow the WAIT, because WAIT is where IntyBASIC
	SRCFILE "input.bas",61
	;[62] ' refreshes its debounced keypad decode. Then use inp_* instead of CONT1.*:
	SRCFILE "input.bas",62
	;[63] '
	SRCFILE "input.bas",63
	;[64] '   IF inp_dir AND DISC_LEFT THEN ...    ' level: disc held left
	SRCFILE "input.bas",64
	;[65] '   IF inp_btn THEN ...                  ' level: any action button held
	SRCFILE "input.bas",65
	;[66] '   IF inp_btn = BUTTON_2 THEN ...       ' level: bottom-left specifically
	SRCFILE "input.bas",66
	;[67] '   IF inp_btn_hit THEN ...              ' edge:  a button went down this frame
	SRCFILE "input.bas",67
	;[68] '   IF inp_key = 11 THEN ...             ' level: ENTER held (hold-to-view)
	SRCFILE "input.bas",68
	;[69] '   IF inp_key_hit = 10 THEN ...         ' edge:  CLEAR was just pressed
	SRCFILE "input.bas",69
	;[70] '
	SRCFILE "input.bas",70
	;[71] ' Disc reads stay level-triggered so inp_lock keeps providing auto-repeat.
	SRCFILE "input.bas",71
	;[72] ' The _hit edges fire on exactly one frame per physical press, which is what
	SRCFILE "input.bas",72
	;[73] ' the menu toggles want: a still-held CLEAR can no longer close the menu on
	SRCFILE "input.bas",73
	;[74] ' the same frame it opened it, so none of the old "spin until the key is
	SRCFILE "input.bas",74
	;[75] ' released" loops are needed any more.
	SRCFILE "input.bas",75
	;[76] '
	SRCFILE "input.bas",76
	;[77] ' Known gap: fujinet.bas's blocking WAIT loops don't call read_input, so a
	SRCFILE "input.bas",77
	;[78] ' press and release that both land inside one network round-trip is missed.
	SRCFILE "input.bas",78
	;[79] ' That is pre-existing behaviour.
	SRCFILE "input.bas",79
	;[80] ' ===========================================================================
	SRCFILE "input.bas",80
	;[81] 
	SRCFILE "input.bas",81
	;[82] CONST CONT1_PORT = $01FF
	SRCFILE "input.bas",82
	;[83] 
	SRCFILE "input.bas",83
	;[84] ' Frames the raw port must hold steady before a reading is published. The
	SRCFILE "input.bas",84
	;[85] ' keypad's row and column contacts need not close on the same frame, so the
	SRCFILE "input.bas",85
	;[86] ' first frame of a CLEAR press can read as a bare $08 -- indistinguishable
	SRCFILE "input.bas",86
	;[87] ' from disc-left -- before the row bit arrives. One frame of agreement (16ms)
	SRCFILE "input.bas",87
	;[88] ' rides that out and isn't felt on the disc. Raise it if presses still leak.
	SRCFILE "input.bas",88
	;[89] CONST INPUT_SETTLE = 1
	SRCFILE "input.bas",89
	;[90] 
	SRCFILE "input.bas",90
	;[91] ' All 8-bit on purpose: fujitzee sits at the 47 16-bit variable ceiling, so
	SRCFILE "input.bas",91
	;[92] ' nothing here may take a '#' name.
	SRCFILE "input.bas",92
	;[93]     DIM inp_raw, inp_dir, inp_btn, inp_key
	SRCFILE "input.bas",93
	;[94]     DIM inp_btn_hit, inp_key_hit
	SRCFILE "input.bas",94
	;[95]     DIM inp_btn_prev, inp_key_prev
	SRCFILE "input.bas",95
	;[96]     DIM inp_new, inp_seen, inp_settle, inp_row, inp_iskey
	SRCFILE "input.bas",96
	;[97]     DIM inp_lock
	SRCFILE "input.bas",97
	;[98] 
	SRCFILE "input.bas",98
	;[99] read_input: PROCEDURE
	SRCFILE "input.bas",99
	; READ_INPUT
label_READ_INPUT:	PROC
	BEGIN
	;[100]     ' One snapshot per frame. Reading the port once (rather than letting each
	SRCFILE "input.bas",100
	;[101]     ' CONT1.x accessor re-read it) also means every field below is decoded
	SRCFILE "input.bas",101
	;[102]     ' from the same instant.
	SRCFILE "input.bas",102
	;[103]     inp_new = PEEK(CONT1_PORT) XOR 255
	SRCFILE "input.bas",103
	MVI 511,R0
	XORI #255,R0
	MVO R0,var_INP_NEW
	;[104]     IF inp_new <> inp_seen THEN
	SRCFILE "input.bas",104
	MVI var_INP_NEW,R0
	CMP var_INP_SEEN,R0
	BEQ T1
	;[105]         inp_seen = inp_new
	SRCFILE "input.bas",105
	MVO R0,var_INP_SEEN
	;[106]         inp_settle = INPUT_SETTLE
	SRCFILE "input.bas",106
	MVII #1,R0
	MVO R0,var_INP_SETTLE
	;[107]     ELSE
	SRCFILE "input.bas",107
	B T2
T1:
	;[108]         IF inp_settle > 0 THEN
	SRCFILE "input.bas",108
	MVI var_INP_SETTLE,R0
	CMPI #0,R0
	BLE T3
	;[109]             inp_settle = inp_settle - 1
	SRCFILE "input.bas",109
	DECR R0
	MVO R0,var_INP_SETTLE
	;[110]             IF inp_settle = 0 THEN inp_raw = inp_new
	SRCFILE "input.bas",110
	MVI var_INP_SETTLE,R0
	TSTR R0
	BNE T4
	MVI var_INP_NEW,R0
	MVO R0,var_INP_RAW
T4:
	;[111]         END IF
	SRCFILE "input.bas",111
T3:
	;[112]     END IF
	SRCFILE "input.bas",112
T2:
	;[113] 
	SRCFILE "input.bas",113
	;[114]     inp_row = inp_raw AND BUTTON_MASK
	SRCFILE "input.bas",114
	MVI var_INP_RAW,R0
	ANDI #224,R0
	MVO R0,var_INP_ROW
	;[115]     inp_dir = 0
	SRCFILE "input.bas",115
	CLRR R0
	MVO R0,var_INP_DIR
	;[116]     inp_btn = 0
	SRCFILE "input.bas",116
	MVO R0,var_INP_BTN
	;[117]     ' Exactly one row bit means a keypad key is down. Written as separate IFs
	SRCFILE "input.bas",117
	;[118]     ' rather than one chained OR -- multi-condition one-liners have bitten
	SRCFILE "input.bas",118
	;[119]     ' this compiler before.
	SRCFILE "input.bas",119
	;[120]     inp_iskey = 0
	SRCFILE "input.bas",120
	NOP
	MVO R0,var_INP_ISKEY
	;[121]     IF inp_row = $20 THEN inp_iskey = 1
	SRCFILE "input.bas",121
	MVI var_INP_ROW,R0
	CMPI #32,R0
	BNE T5
	MVII #1,R0
	MVO R0,var_INP_ISKEY
T5:
	;[122]     IF inp_row = $40 THEN inp_iskey = 1
	SRCFILE "input.bas",122
	MVI var_INP_ROW,R0
	CMPI #64,R0
	BNE T6
	MVII #1,R0
	MVO R0,var_INP_ISKEY
T6:
	;[123]     IF inp_row = $80 THEN inp_iskey = 1
	SRCFILE "input.bas",123
	MVI var_INP_ROW,R0
	CMPI #128,R0
	BNE T7
	MVII #1,R0
	MVO R0,var_INP_ISKEY
T7:
	;[124]     IF inp_iskey = 0 THEN
	SRCFILE "input.bas",124
	MVI var_INP_ISKEY,R0
	TSTR R0
	BNE T8
	;[125]         inp_btn = inp_row
	SRCFILE "input.bas",125
	MVI var_INP_ROW,R0
	MVO R0,var_INP_BTN
	;[126]         inp_dir = inp_raw AND DISK_MASK
	SRCFILE "input.bas",126
	MVI var_INP_RAW,R0
	ANDI #31,R0
	MVO R0,var_INP_DIR
	;[127]     END IF
	SRCFILE "input.bas",127
T8:
	;[128] 
	SRCFILE "input.bas",128
	;[129]     ' IntyBASIC's own debounced decode: 0-9 digits, 10 = CLEAR, 11 = ENTER,
	SRCFILE "input.bas",129
	;[130]     ' 12 = nothing pressed. Reads a variable, not the port, so it can't
	SRCFILE "input.bas",130
	;[131]     ' disagree with the snapshot above.
	SRCFILE "input.bas",131
	;[132]     inp_key = CONT1.KEY
	SRCFILE "input.bas",132
	MVI _cnt1_key,R0
	MVO R0,var_INP_KEY
	;[133] 
	SRCFILE "input.bas",133
	;[134]     ' Edge flags. inp_key_hit carries 12 ("no key") when nothing changed, so
	SRCFILE "input.bas",134
	;[135]     ' both "no edge" and "released back to idle" read as non-actionable.
	SRCFILE "input.bas",135
	;[136]     inp_key_hit = 12
	SRCFILE "input.bas",136
	MVII #12,R0
	MVO R0,var_INP_KEY_HIT
	;[137]     IF inp_key <> inp_key_prev THEN
	SRCFILE "input.bas",137
	MVI var_INP_KEY,R0
	CMP var_INP_KEY_PREV,R0
	BEQ T9
	;[138]         inp_key_prev = inp_key
	SRCFILE "input.bas",138
	MVO R0,var_INP_KEY_PREV
	;[139]         inp_key_hit = inp_key
	SRCFILE "input.bas",139
	MVO R0,var_INP_KEY_HIT
	;[140]     END IF
	SRCFILE "input.bas",140
T9:
	;[141]     inp_btn_hit = 0
	SRCFILE "input.bas",141
	CLRR R0
	MVO R0,var_INP_BTN_HIT
	;[142]     IF inp_btn <> inp_btn_prev THEN
	SRCFILE "input.bas",142
	MVI var_INP_BTN,R0
	CMP var_INP_BTN_PREV,R0
	BEQ T10
	;[143]         inp_btn_prev = inp_btn
	SRCFILE "input.bas",143
	MVO R0,var_INP_BTN_PREV
	;[144]         inp_btn_hit = inp_btn
	SRCFILE "input.bas",144
	MVO R0,var_INP_BTN_HIT
	;[145]     END IF
	SRCFILE "input.bas",145
T10:
	;[146] END
	SRCFILE "input.bas",146
	RETURN
	ENDP
	;ENDFILE
	;FILE texas.bas
	;[36]     INCLUDE "fujinet.bas"
	SRCFILE "texas.bas",36
	;FILE fujinet.bas
	;[1] ' fujinet.bas -- FujiNet mailbox transport + network/appkey primitives.
	SRCFILE "fujinet.bas",1
	;[2] '
	SRCFILE "fujinet.bas",2
	;[3] ' Mailbox layout is the hand-synchronized copy of
	SRCFILE "fujinet.bas",3
	;[4] ' fujinet-firmware/pico/intellivision/firmware/fuji_mailbox.h, exactly as
	SRCFILE "fujinet.bas",4
	;[5] ' proven working by intv/fujitest.bas in that repo. Do not change these
	SRCFILE "fujinet.bas",5
	;[6] ' addresses without re-checking that file.
	SRCFILE "fujinet.bas",6
	;[7] '
	SRCFILE "fujinet.bas",7
	;[8] ' MEMATTR intentionally stops at $9BFF, short of the $9C00-$9FFF mailbox
	SRCFILE "fujinet.bas",8
	;[9] ' itself: on real PiRTO II hardware the RP2040 maps that whole window as
	SRCFILE "fujinet.bas",9
	;[10] ' RAM unconditionally (inty_cart.c hardcodes it, independent of what this
	SRCFILE "fujinet.bas",10
	;[11] ' .cfg says), so declaring less here doesn't affect real hardware or what
	SRCFILE "fujinet.bas",11
	;[12] ' POKE can reach at runtime. But jzIntv's --fujinet peripheral emulation
	SRCFILE "fujinet.bas",12
	;[13] ' registers its own handler for $9C00-$9FFF *after* the cart's generic
	SRCFILE "fujinet.bas",13
	;[14] ' MEMATTR RAM, and its layered bus dispatch lets whichever peripheral
	SRCFILE "fujinet.bas",14
	;[15] ' registered first answer a given address -- so declaring the full
	SRCFILE "fujinet.bas",15
	;[16] ' $8000-$9FFF range here (as fujitest.bas does) silently shadows the
	SRCFILE "fujinet.bas",16
	;[17] ' emulator's FujiNet peripheral with inert RAM, and the mailbox never
	SRCFILE "fujinet.bas",17
	;[18] ' comes up under --fujinet even though it works on real hardware.
	SRCFILE "fujinet.bas",18
	;[19]     ASM MEMATTR $8000, $9BFF, "+RWN"
	SRCFILE "fujinet.bas",19
 MEMATTR $8000, $9BFF, "+RWN"
	;[20] 
	SRCFILE "fujinet.bas",20
	;[21]     CONST FN_MAGIC0     = $9C00
	SRCFILE "fujinet.bas",21
	;[22]     CONST FN_MAGIC1     = $9C01
	SRCFILE "fujinet.bas",22
	;[23]     CONST FN_SEQ        = $9C03
	SRCFILE "fujinet.bas",23
	;[24]     CONST FN_ACKSEQ     = $9C04
	SRCFILE "fujinet.bas",24
	;[25]     CONST FN_DEVICE     = $9C05
	SRCFILE "fujinet.bas",25
	;[26]     CONST FN_CMD        = $9C06
	SRCFILE "fujinet.bas",26
	;[27]     CONST FN_NPARAM     = $9C07
	SRCFILE "fujinet.bas",27
	;[28]     CONST FN_TXLEN_LO   = $9C08
	SRCFILE "fujinet.bas",28
	;[29]     CONST FN_TXLEN_HI   = $9C09
	SRCFILE "fujinet.bas",29
	;[30]     CONST FN_ERR        = $9C0B
	SRCFILE "fujinet.bas",30
	;[31]     CONST FN_RXLEN_LO   = $9C0C
	SRCFILE "fujinet.bas",31
	;[32]     CONST FN_RXLEN_HI   = $9C0D
	SRCFILE "fujinet.bas",32
	;[33]     CONST FN_REPLY_CMD  = $9C0E
	SRCFILE "fujinet.bas",33
	;[34]     CONST FN_PARAM_SIZE = $9C10
	SRCFILE "fujinet.bas",34
	;[35]     CONST FN_PARAM_VAL  = $9C20
	SRCFILE "fujinet.bas",35
	;[36]     CONST FN_TX         = $9C40
	SRCFILE "fujinet.bas",36
	;[37]     CONST FN_RX         = $9D40
	SRCFILE "fujinet.bas",37
	;[38] 
	SRCFILE "fujinet.bas",38
	;[39]     CONST FUJICMD_ACK = $06
	SRCFILE "fujinet.bas",39
	;[40]     CONST FUJICMD_NAK = $15
	SRCFILE "fujinet.bas",40
	;[41] 
	SRCFILE "fujinet.bas",41
	;[42]     ' Fuji device (config/appkey) commands.
	SRCFILE "fujinet.bas",42
	;[43]     CONST FUJI_DEVICEID       = $70
	SRCFILE "fujinet.bas",43
	;[44]     CONST FUJICMD_OPEN_APPKEY  = $DC
	SRCFILE "fujinet.bas",44
	;[45]     CONST FUJICMD_CLOSE_APPKEY = $DB
	SRCFILE "fujinet.bas",45
	;[46]     CONST FUJICMD_WRITE_APPKEY = $DE
	SRCFILE "fujinet.bas",46
	;[47]     CONST FUJICMD_READ_APPKEY  = $DD
	SRCFILE "fujinet.bas",47
	;[48] 
	SRCFILE "fujinet.bas",48
	;[49]     ' Network device (N1:) commands.
	SRCFILE "fujinet.bas",49
	;[50]     CONST NET_DEVICEID = $71
	SRCFILE "fujinet.bas",50
	;[51]     CONST NETCMD_OPEN   = $4F
	SRCFILE "fujinet.bas",51
	;[52]     CONST NETCMD_CLOSE  = $43
	SRCFILE "fujinet.bas",52
	;[53]     CONST NETCMD_READ   = $52
	SRCFILE "fujinet.bas",53
	;[54]     CONST NETCMD_STATUS = $53
	SRCFILE "fujinet.bas",54
	;[55] 
	SRCFILE "fujinet.bas",55
	;[56]     CONST OPEN_MODE_HTTP_GET_H = $0C
	SRCFILE "fujinet.bas",56
	;[57]     CONST OPEN_TRANS_NONE = $00
	SRCFILE "fujinet.bas",57
	;[58] 
	SRCFILE "fujinet.bas",58
	;[59]     ' Scratch RAM ($9000-$97FF) -- ours, outside the mailbox proper. Holds
	SRCFILE "fujinet.bas",59
	;[60]     ' state that must survive across multiple mailbox transactions (the
	SRCFILE "fujinet.bas",60
	;[61]     ' mailbox's own TX/RX buffers get overwritten by every call).
	SRCFILE "fujinet.bas",61
	;[62]     CONST SC_NAME    = $9100 ' playerName, 9 bytes (8 + NUL)
	SRCFILE "fujinet.bas",62
	;[63]     CONST SC_ENDPT   = $9110 ' serverEndpoint, 64 bytes
	SRCFILE "fujinet.bas",63
	;[64]     CONST SC_QUERY   = $9150 ' query (?table=...&player=...), 48 bytes
	SRCFILE "fujinet.bas",64
	;[65] 
	SRCFILE "fujinet.bas",65
	;[66]     ' fn_ok: 1 = last transaction produced ACK, 0 = timeout or NAK.
	SRCFILE "fujinet.bas",66
	;[67]     ' mb_err: FN_ERR value on failure (0 on timeout, since the RP2040 never answered).
	SRCFILE "fujinet.bas",67
	;[68]     DIM fn_ok, mb_err
	SRCFILE "fujinet.bas",68
	;[69]     DIM mb_dev, mb_cmd, mb_nparam, mb_seq
	SRCFILE "fujinet.bas",69
	;[70]     DIM #fn_txlen
	SRCFILE "fujinet.bas",70
	;[71]     DIM #fn_t          ' generic frame-count timeout counter
	SRCFILE "fujinet.bas",71
	;[72]     DIM #fn_src         ' VARPTR source for putstr/getstr
	SRCFILE "fujinet.bas",72
	;[73]     DIM fn_len, fn_i    ' generic length/index for putstr/getstr
	SRCFILE "fujinet.bas",73
	;[74] 
	SRCFILE "fujinet.bas",74
	;[75] ' ---------------------------------------------------------------------------
	SRCFILE "fujinet.bas",75
	;[76] ' fn_wait_mailbox: bounded wait for the RP2040 magic bytes at boot.
	SRCFILE "fujinet.bas",76
	;[77] ' Sets fn_ok = 1 if the mailbox came up within 180 frames (3s), else 0.
	SRCFILE "fujinet.bas",77
	;[78] ' ---------------------------------------------------------------------------
	SRCFILE "fujinet.bas",78
	;[79] fn_wait_mailbox: PROCEDURE
	SRCFILE "fujinet.bas",79
	; FN_WAIT_MAILBOX
label_FN_WAIT_MAILBOX:	PROC
	BEGIN
	;[80]     #fn_t = 0
	SRCFILE "fujinet.bas",80
	CLRR R0
	MVO R0,var_&FN_T
	;[81]     WHILE ((PEEK(FN_MAGIC0) AND 255) <> 70) AND ((PEEK(FN_MAGIC1) AND 255) <> 78) AND (#fn_t < 180)
	SRCFILE "fujinet.bas",81
T11:
	MVI 39936,R0
	ANDI #255,R0
	CMPI #70,R0
	MVII #65535,R0
	BNE T13
	INCR R0
T13:
	MVI 39937,R1
	ANDI #255,R1
	CMPI #78,R1
	MVII #65535,R1
	BNE T14
	INCR R1
T14:
	ANDR R1,R0
	MVI var_&FN_T,R1
	CMPI #180,R1
	MVII #65535,R1
	BLT T15
	INCR R1
T15:
	ANDR R1,R0
	BEQ T12
	;[82]         #fn_t = #fn_t + 1
	SRCFILE "fujinet.bas",82
	MVI var_&FN_T,R0
	INCR R0
	MVO R0,var_&FN_T
	;[83]         WAIT
	SRCFILE "fujinet.bas",83
	CALL _wait
	;[84]     WEND
	SRCFILE "fujinet.bas",84
	B T11
T12:
	;[85]     IF #fn_t >= 180 THEN
	SRCFILE "fujinet.bas",85
	MVI var_&FN_T,R0
	CMPI #180,R0
	BLT T16
	;[86]         fn_ok = 0
	SRCFILE "fujinet.bas",86
	CLRR R0
	MVO R0,var_FN_OK
	;[87]     ELSE
	SRCFILE "fujinet.bas",87
	B T17
T16:
	;[88]         fn_ok = 1
	SRCFILE "fujinet.bas",88
	MVII #1,R0
	MVO R0,var_FN_OK
	;[89]     END IF
	SRCFILE "fujinet.bas",89
T17:
	;[90] END
	SRCFILE "fujinet.bas",90
	RETURN
	ENDP
	;[91] 
	SRCFILE "fujinet.bas",91
	;[92] ' ---------------------------------------------------------------------------
	SRCFILE "fujinet.bas",92
	;[93] ' fn_transact: issue the transaction described by mb_dev/mb_cmd/mb_nparam/
	SRCFILE "fujinet.bas",93
	;[94] ' #fn_txlen (payload already staged at FN_TX) and block for the reply.
	SRCFILE "fujinet.bas",94
	;[95] ' seq is ALWAYS derived from the RP2040's own FN_ACKSEQ, never from a local
	SRCFILE "fujinet.bas",95
	;[96] ' counter -- a console reset zeroes IntyBASIC vars but not the RP2040, so a
	SRCFILE "fujinet.bas",96
	;[97] ' locally incrementing seq would recompute the same value forever and never
	SRCFILE "fujinet.bas",97
	;[98] ' trigger a second transaction after the first boot.
	SRCFILE "fujinet.bas",98
	;[99] ' Sets fn_ok = 1 on ACK, 0 on timeout/NAK (mb_err holds the reason).
	SRCFILE "fujinet.bas",99
	;[100] ' ---------------------------------------------------------------------------
	SRCFILE "fujinet.bas",100
	;[101] fn_transact: PROCEDURE
	SRCFILE "fujinet.bas",101
	; FN_TRANSACT
label_FN_TRANSACT:	PROC
	BEGIN
	;[102]     POKE (FN_DEVICE), mb_dev
	SRCFILE "fujinet.bas",102
	MVI var_MB_DEV,R0
	MVO R0,39941
	;[103]     POKE (FN_CMD), mb_cmd
	SRCFILE "fujinet.bas",103
	MVI var_MB_CMD,R0
	MVO R0,39942
	;[104]     POKE (FN_NPARAM), mb_nparam
	SRCFILE "fujinet.bas",104
	MVI var_MB_NPARAM,R0
	MVO R0,39943
	;[105]     POKE (FN_TXLEN_LO), #fn_txlen AND 255
	SRCFILE "fujinet.bas",105
	MVI var_&FN_TXLEN,R0
	ANDI #255,R0
	MVO R0,39944
	;[106]     POKE (FN_TXLEN_HI), #fn_txlen / 256
	SRCFILE "fujinet.bas",106
	MVI var_&FN_TXLEN,R0
	SWAP R0
	ANDI #255,R0
	MVO R0,39945
	;[107] 
	SRCFILE "fujinet.bas",107
	;[108]     mb_seq = (PEEK(FN_ACKSEQ) AND 255) + 1
	SRCFILE "fujinet.bas",108
	MVI 39940,R0
	ANDI #255,R0
	INCR R0
	MVO R0,var_MB_SEQ
	;[109]     IF mb_seq = 0 THEN mb_seq = 1
	SRCFILE "fujinet.bas",109
	MVI var_MB_SEQ,R0
	TSTR R0
	BNE T18
	MVII #1,R0
	MVO R0,var_MB_SEQ
T18:
	;[110]     POKE (FN_SEQ), mb_seq
	SRCFILE "fujinet.bas",110
	MVI var_MB_SEQ,R0
	MVO R0,39939
	;[111] 
	SRCFILE "fujinet.bas",111
	;[112]     #fn_t = 0
	SRCFILE "fujinet.bas",112
	CLRR R0
	MVO R0,var_&FN_T
	;[113]     WHILE ((PEEK(FN_ACKSEQ) AND 255) <> mb_seq) AND (#fn_t < 900)
	SRCFILE "fujinet.bas",113
T19:
	MVI 39940,R0
	ANDI #255,R0
	CMP var_MB_SEQ,R0
	MVII #65535,R0
	BNE T21
	INCR R0
T21:
	MVI var_&FN_T,R1
	CMPI #900,R1
	MVII #65535,R1
	BLT T22
	INCR R1
T22:
	ANDR R1,R0
	BEQ T20
	;[114]         #fn_t = #fn_t + 1
	SRCFILE "fujinet.bas",114
	MVI var_&FN_T,R0
	INCR R0
	MVO R0,var_&FN_T
	;[115]         WAIT
	SRCFILE "fujinet.bas",115
	CALL _wait
	;[116]     WEND
	SRCFILE "fujinet.bas",116
	B T19
T20:
	;[117] 
	SRCFILE "fujinet.bas",117
	;[118]     IF #fn_t >= 900 THEN
	SRCFILE "fujinet.bas",118
	MVI var_&FN_T,R0
	CMPI #900,R0
	BLT T23
	;[119]         fn_ok = 0
	SRCFILE "fujinet.bas",119
	CLRR R0
	MVO R0,var_FN_OK
	;[120]         mb_err = 0
	SRCFILE "fujinet.bas",120
	MVO R0,var_MB_ERR
	;[121]         RETURN
	SRCFILE "fujinet.bas",121
	RETURN
	;[122]     END IF
	SRCFILE "fujinet.bas",122
T23:
	;[123] 
	SRCFILE "fujinet.bas",123
	;[124]     IF (PEEK(FN_REPLY_CMD) AND 255) <> FUJICMD_ACK THEN
	SRCFILE "fujinet.bas",124
	MVI 39950,R0
	ANDI #255,R0
	CMPI #6,R0
	BEQ T24
	;[125]         fn_ok = 0
	SRCFILE "fujinet.bas",125
	CLRR R0
	MVO R0,var_FN_OK
	;[126]         mb_err = PEEK(FN_ERR) AND 255
	SRCFILE "fujinet.bas",126
	MVI 39947,R0
	MVO R0,var_MB_ERR
	;[127]         RETURN
	SRCFILE "fujinet.bas",127
	RETURN
	;[128]     END IF
	SRCFILE "fujinet.bas",128
T24:
	;[129] 
	SRCFILE "fujinet.bas",129
	;[130]     fn_ok = 1
	SRCFILE "fujinet.bas",130
	MVII #1,R0
	MVO R0,var_FN_OK
	;[131] END
	SRCFILE "fujinet.bas",131
	RETURN
	ENDP
	;[132] 
	SRCFILE "fujinet.bas",132
	;[133] ' ---------------------------------------------------------------------------
	SRCFILE "fujinet.bas",133
	;[134] ' fn_param: stage transaction parameter #pm_i (0-based), #pm_size bytes
	SRCFILE "fujinet.bas",134
	;[135] ' (1 or 2), value #pm_val, little-endian, into the mailbox's param table.
	SRCFILE "fujinet.bas",135
	;[136] ' ---------------------------------------------------------------------------
	SRCFILE "fujinet.bas",136
	;[137] DIM pm_i, pm_size
	SRCFILE "fujinet.bas",137
	;[138] DIM #pm_val
	SRCFILE "fujinet.bas",138
	;[139] fn_param: PROCEDURE
	SRCFILE "fujinet.bas",139
	; FN_PARAM
label_FN_PARAM:	PROC
	BEGIN
	;[140]     POKE (FN_PARAM_SIZE + pm_i), pm_size
	SRCFILE "fujinet.bas",140
	MVI var_PM_SIZE,R0
	MVI var_PM_I,R1
	ADDI #39952,R1
	MVO@ R0,R1
	;[141]     POKE (FN_PARAM_VAL + pm_i * 4), #pm_val AND 255
	SRCFILE "fujinet.bas",141
	MVI var_&PM_VAL,R0
	ANDI #255,R0
	MVI var_PM_I,R1
	SLL R1,2
	ADDI #39968,R1
	MVO@ R0,R1
	;[142]     IF pm_size > 1 THEN POKE (FN_PARAM_VAL + pm_i * 4 + 1), #pm_val / 256
	SRCFILE "fujinet.bas",142
	MVI var_PM_SIZE,R0
	CMPI #1,R0
	BLE T25
	MVI var_&PM_VAL,R0
	SWAP R0
	ANDI #255,R0
	MVI var_PM_I,R1
	SLL R1,2
	ADDI #39969,R1
	MVO@ R0,R1
T25:
	;[143] END
	SRCFILE "fujinet.bas",143
	RETURN
	ENDP
	;[144] 
	SRCFILE "fujinet.bas",144
	;[145] ' ---------------------------------------------------------------------------
	SRCFILE "fujinet.bas",145
	;[146] ' fn_putstr: append fn_len ASCII bytes into FN_TX, starting at the current
	SRCFILE "fujinet.bas",146
	;[147] ' #fn_txlen, from the address in #fn_src -- either VARPTR of a ROM DATA
	SRCFILE "fujinet.bas",147
	;[148] ' label (a literal like lit_tables(0)) or a RAM address (a scratch buffer
	SRCFILE "fujinet.bas",148
	;[149] ' like SC_NAME, or even FN_RX). PEEK is uniform across ROM/RAM on the
	SRCFILE "fujinet.bas",149
	;[150] ' CP-1610's unified address space, so one procedure covers both. Advances
	SRCFILE "fujinet.bas",150
	;[151] ' #fn_txlen.
	SRCFILE "fujinet.bas",151
	;[152] ' ---------------------------------------------------------------------------
	SRCFILE "fujinet.bas",152
	;[153] fn_putstr: PROCEDURE
	SRCFILE "fujinet.bas",153
	; FN_PUTSTR
label_FN_PUTSTR:	PROC
	BEGIN
	;[154]     FOR fn_i = 0 TO fn_len - 1
	SRCFILE "fujinet.bas",154
	CLRR R0
	MVO R0,var_FN_I
T26:
	;[155]         POKE (FN_TX + #fn_txlen + fn_i), PEEK(#fn_src + fn_i) AND 255
	SRCFILE "fujinet.bas",155
	MVI var_&FN_SRC,R1
	ADD var_FN_I,R1
	MVI@ R1,R0
	ANDI #255,R0
	MVI var_&FN_TXLEN,R1
	ADDI #40000,R1
	ADD var_FN_I,R1
	MVO@ R0,R1
	;[156]     NEXT fn_i
	SRCFILE "fujinet.bas",156
	MVI var_FN_I,R0
	INCR R0
	MVO R0,var_FN_I
	MVI var_FN_LEN,R1
	DECR R1
	CMPR R1,R0
	BLE T26
	;[157]     #fn_txlen = #fn_txlen + fn_len
	SRCFILE "fujinet.bas",157
	MVI var_&FN_TXLEN,R0
	ADD var_FN_LEN,R0
	MVO R0,var_&FN_TXLEN
	;[158] END
	SRCFILE "fujinet.bas",158
	RETURN
	ENDP
	;[159] 
	SRCFILE "fujinet.bas",159
	;[160] ' ---------------------------------------------------------------------------
	SRCFILE "fujinet.bas",160
	;[161] ' fn_strlen: scan the NUL-padded field at #fn_src (max ls_max bytes) and set
	SRCFILE "fujinet.bas",161
	;[162] ' fn_len to the length up to (but not including) the first NUL. Use this
	SRCFILE "fujinet.bas",162
	;[163] ' before fn_putstr whenever the source is a fixed-width padded field (table
	SRCFILE "fujinet.bas",163
	;[164] ' id, player name) -- putstr has no idea where the real string ends, and
	SRCFILE "fujinet.bas",164
	;[165] ' blindly copying the full padded width embeds a literal $00 byte plus
	SRCFILE "fujinet.bas",165
	;[166] ' whatever garbage follows it into the URL, which is sent as-is (the URL's
	SRCFILE "fujinet.bas",166
	;[167] ' length is a byte count, not NUL-terminated, so nothing downstream stops
	SRCFILE "fujinet.bas",167
	;[168] ' at that NUL either -- it corrupts the HTTP request on the wire).
	SRCFILE "fujinet.bas",168
	;[169] ' ---------------------------------------------------------------------------
	SRCFILE "fujinet.bas",169
	;[170] DIM ls_max
	SRCFILE "fujinet.bas",170
	;[171] fn_strlen: PROCEDURE
	SRCFILE "fujinet.bas",171
	; FN_STRLEN
label_FN_STRLEN:	PROC
	BEGIN
	;[172]     fn_len = 0
	SRCFILE "fujinet.bas",172
	CLRR R0
	MVO R0,var_FN_LEN
	;[173]     WHILE (fn_len < ls_max) AND ((PEEK(#fn_src + fn_len) AND 255) <> 0)
	SRCFILE "fujinet.bas",173
T27:
	MVI var_FN_LEN,R0
	CMP var_LS_MAX,R0
	MVII #65535,R0
	BLT T29
	INCR R0
T29:
	MVI var_&FN_SRC,R1
	ADD var_FN_LEN,R1
	MVI@ R1,R1
	ANDI #255,R1
	MVII #65535,R1
	BNE T30
	INCR R1
T30:
	ANDR R1,R0
	BEQ T28
	;[174]         fn_len = fn_len + 1
	SRCFILE "fujinet.bas",174
	MVI var_FN_LEN,R0
	INCR R0
	MVO R0,var_FN_LEN
	;[175]     WEND
	SRCFILE "fujinet.bas",175
	B T27
T28:
	;[176] END
	SRCFILE "fujinet.bas",176
	RETURN
	ENDP
	;[177] 
	SRCFILE "fujinet.bas",177
	;[178] ' ---------------------------------------------------------------------------
	SRCFILE "fujinet.bas",178
	;[179] ' net_open: open devicespec (ASCII bytes already staged at FN_TX, length in
	SRCFILE "fujinet.bas",179
	;[180] ' #fn_txlen) for HTTP GET. Leaves fn_ok set.
	SRCFILE "fujinet.bas",180
	;[181] ' ---------------------------------------------------------------------------
	SRCFILE "fujinet.bas",181
	;[182] net_open: PROCEDURE
	SRCFILE "fujinet.bas",182
	; NET_OPEN
label_NET_OPEN:	PROC
	BEGIN
	;[183]     mb_dev = NET_DEVICEID
	SRCFILE "fujinet.bas",183
	MVII #113,R0
	MVO R0,var_MB_DEV
	;[184]     mb_cmd = NETCMD_OPEN
	SRCFILE "fujinet.bas",184
	MVII #79,R0
	MVO R0,var_MB_CMD
	;[185]     mb_nparam = 2
	SRCFILE "fujinet.bas",185
	MVII #2,R0
	MVO R0,var_MB_NPARAM
	;[186]     pm_i = 0 : pm_size = 1 : #pm_val = OPEN_MODE_HTTP_GET_H : GOSUB fn_param
	SRCFILE "fujinet.bas",186
	CLRR R0
	MVO R0,var_PM_I
	MVII #1,R0
	MVO R0,var_PM_SIZE
	MVII #12,R0
	MVO R0,var_&PM_VAL
	CALL label_FN_PARAM
	;[187]     pm_i = 1 : pm_size = 1 : #pm_val = OPEN_TRANS_NONE : GOSUB fn_param
	SRCFILE "fujinet.bas",187
	MVII #1,R0
	MVO R0,var_PM_I
	MVO R0,var_PM_SIZE
	CLRR R0
	MVO R0,var_&PM_VAL
	CALL label_FN_PARAM
	;[188]     GOSUB fn_transact
	SRCFILE "fujinet.bas",188
	CALL label_FN_TRANSACT
	;[189] END
	SRCFILE "fujinet.bas",189
	RETURN
	ENDP
	;[190] 
	SRCFILE "fujinet.bas",190
	;[191] ' ---------------------------------------------------------------------------
	SRCFILE "fujinet.bas",191
	;[192] ' net_status: query byte count available. Result in #net_avail; fn_ok as usual.
	SRCFILE "fujinet.bas",192
	;[193] ' ---------------------------------------------------------------------------
	SRCFILE "fujinet.bas",193
	;[194] DIM #net_avail
	SRCFILE "fujinet.bas",194
	;[195] ' net_err: the 4th byte of the NDeviceStatus reply (nDevStatus_t). 1 =
	SRCFILE "fujinet.bas",195
	;[196] ' SUCCESS. For an HTTP-backed devicespec, the *actual* GET is deferred
	SRCFILE "fujinet.bas",196
	;[197] ' until this first STATUS call (see NetworkProtocolHTTP::status_file()/
	SRCFILE "fujinet.bas",197
	;[198] ' http_transaction() in fujinet-firmware) and its result code lands here
	SRCFILE "fujinet.bas",198
	;[199] ' -- an HTTP error response (e.g. a 400) still has a real, readable body
	SRCFILE "fujinet.bas",199
	;[200] ' (the error page), so `avail` alone can't tell it apart from a good
	SRCFILE "fujinet.bas",200
	;[201] ' response. Checking net_err is what actually can.
	SRCFILE "fujinet.bas",201
	;[202] DIM net_err
	SRCFILE "fujinet.bas",202
	;[203] net_status: PROCEDURE
	SRCFILE "fujinet.bas",203
	; NET_STATUS
label_NET_STATUS:	PROC
	BEGIN
	;[204]     mb_dev = NET_DEVICEID
	SRCFILE "fujinet.bas",204
	MVII #113,R0
	MVO R0,var_MB_DEV
	;[205]     mb_cmd = NETCMD_STATUS
	SRCFILE "fujinet.bas",205
	MVII #83,R0
	MVO R0,var_MB_CMD
	;[206]     mb_nparam = 2
	SRCFILE "fujinet.bas",206
	MVII #2,R0
	MVO R0,var_MB_NPARAM
	;[207]     pm_i = 0 : pm_size = 1 : #pm_val = 0 : GOSUB fn_param
	SRCFILE "fujinet.bas",207
	CLRR R0
	MVO R0,var_PM_I
	MVII #1,R0
	MVO R0,var_PM_SIZE
	CLRR R0
	MVO R0,var_&PM_VAL
	CALL label_FN_PARAM
	;[208]     pm_i = 1 : pm_size = 1 : #pm_val = 0 : GOSUB fn_param
	SRCFILE "fujinet.bas",208
	MVII #1,R0
	MVO R0,var_PM_I
	MVO R0,var_PM_SIZE
	CLRR R0
	MVO R0,var_&PM_VAL
	CALL label_FN_PARAM
	;[209]     #fn_txlen = 0
	SRCFILE "fujinet.bas",209
	CLRR R0
	MVO R0,var_&FN_TXLEN
	;[210]     GOSUB fn_transact
	SRCFILE "fujinet.bas",210
	CALL label_FN_TRANSACT
	;[211]     IF fn_ok THEN
	SRCFILE "fujinet.bas",211
	MVI var_FN_OK,R0
	TSTR R0
	BEQ T31
	;[212]         #net_avail = (PEEK(FN_RX) AND 255) + (PEEK(FN_RX + 1) AND 255) * 256
	SRCFILE "fujinet.bas",212
	MVI 40256,R0
	ANDI #255,R0
	MVI 40257,R1
	ANDI #255,R1
	SWAP R1
	ANDI #65280,R1
	ADDR R1,R0
	MVO R0,var_&NET_AVAIL
	;[213]         net_err = PEEK(FN_RX + 3) AND 255
	SRCFILE "fujinet.bas",213
	MVI 40259,R0
	MVO R0,var_NET_ERR
	;[214]         IF net_err <> 1 THEN fn_ok = 0
	SRCFILE "fujinet.bas",214
	MVI var_NET_ERR,R0
	CMPI #1,R0
	BEQ T32
	CLRR R0
	MVO R0,var_FN_OK
T32:
	;[215]     ELSE
	SRCFILE "fujinet.bas",215
	B T33
T31:
	;[216]         #net_avail = 0
	SRCFILE "fujinet.bas",216
	CLRR R0
	MVO R0,var_&NET_AVAIL
	;[217]     END IF
	SRCFILE "fujinet.bas",217
T33:
	;[218] END
	SRCFILE "fujinet.bas",218
	RETURN
	ENDP
	;[219] 
	SRCFILE "fujinet.bas",219
	;[220] ' ---------------------------------------------------------------------------
	SRCFILE "fujinet.bas",220
	;[221] ' net_read: read #net_readlen bytes into FN_RX (reply payload lands there
	SRCFILE "fujinet.bas",221
	;[222] ' directly -- callers PEEK it in place, per the "never buffer in IntyBASIC
	SRCFILE "fujinet.bas",222
	;[223] ' variables" rule). fn_ok as usual.
	SRCFILE "fujinet.bas",223
	;[224] ' ---------------------------------------------------------------------------
	SRCFILE "fujinet.bas",224
	;[225] DIM #net_readlen
	SRCFILE "fujinet.bas",225
	;[226] ' #net_gotlen: the actual byte count the RP2040/FujiNet peripheral reported
	SRCFILE "fujinet.bas",226
	;[227] ' receiving (RXLEN), captured here because the CLOSE transaction that
	SRCFILE "fujinet.bas",227
	;[228] ' follows in api_call overwrites FN_RXLEN_LO/HI with its own (always 0)
	SRCFILE "fujinet.bas",228
	;[229] ' reply length -- callers need this checked before that happens.
	SRCFILE "fujinet.bas",229
	;[230] DIM #net_gotlen
	SRCFILE "fujinet.bas",230
	;[231] net_read: PROCEDURE
	SRCFILE "fujinet.bas",231
	; NET_READ
label_NET_READ:	PROC
	BEGIN
	;[232]     mb_dev = NET_DEVICEID
	SRCFILE "fujinet.bas",232
	MVII #113,R0
	MVO R0,var_MB_DEV
	;[233]     mb_cmd = NETCMD_READ
	SRCFILE "fujinet.bas",233
	MVII #82,R0
	MVO R0,var_MB_CMD
	;[234]     mb_nparam = 1
	SRCFILE "fujinet.bas",234
	MVII #1,R0
	MVO R0,var_MB_NPARAM
	;[235]     pm_i = 0 : pm_size = 2 : #pm_val = #net_readlen : GOSUB fn_param
	SRCFILE "fujinet.bas",235
	CLRR R0
	MVO R0,var_PM_I
	MVII #2,R0
	MVO R0,var_PM_SIZE
	MVI var_&NET_READLEN,R0
	MVO R0,var_&PM_VAL
	CALL label_FN_PARAM
	;[236]     #fn_txlen = 0
	SRCFILE "fujinet.bas",236
	CLRR R0
	MVO R0,var_&FN_TXLEN
	;[237]     GOSUB fn_transact
	SRCFILE "fujinet.bas",237
	CALL label_FN_TRANSACT
	;[238]     IF fn_ok THEN
	SRCFILE "fujinet.bas",238
	MVI var_FN_OK,R0
	TSTR R0
	BEQ T34
	;[239]         #net_gotlen = (PEEK(FN_RXLEN_LO) AND 255) + (PEEK(FN_RXLEN_HI) AND 255) * 256
	SRCFILE "fujinet.bas",239
	MVI 39948,R0
	ANDI #255,R0
	MVI 39949,R1
	ANDI #255,R1
	SWAP R1
	ANDI #65280,R1
	ADDR R1,R0
	MVO R0,var_&NET_GOTLEN
	;[240]     ELSE
	SRCFILE "fujinet.bas",240
	B T35
T34:
	;[241]         #net_gotlen = 0
	SRCFILE "fujinet.bas",241
	CLRR R0
	MVO R0,var_&NET_GOTLEN
	;[242]     END IF
	SRCFILE "fujinet.bas",242
T35:
	;[243] END
	SRCFILE "fujinet.bas",243
	RETURN
	ENDP
	;[244] 
	SRCFILE "fujinet.bas",244
	;[245] ' ---------------------------------------------------------------------------
	SRCFILE "fujinet.bas",245
	;[246] ' net_close
	SRCFILE "fujinet.bas",246
	;[247] ' ---------------------------------------------------------------------------
	SRCFILE "fujinet.bas",247
	;[248] net_close: PROCEDURE
	SRCFILE "fujinet.bas",248
	; NET_CLOSE
label_NET_CLOSE:	PROC
	BEGIN
	;[249]     mb_dev = NET_DEVICEID
	SRCFILE "fujinet.bas",249
	MVII #113,R0
	MVO R0,var_MB_DEV
	;[250]     mb_cmd = NETCMD_CLOSE
	SRCFILE "fujinet.bas",250
	MVII #67,R0
	MVO R0,var_MB_CMD
	;[251]     mb_nparam = 0
	SRCFILE "fujinet.bas",251
	CLRR R0
	MVO R0,var_MB_NPARAM
	;[252]     #fn_txlen = 0
	SRCFILE "fujinet.bas",252
	MVO R0,var_&FN_TXLEN
	;[253]     GOSUB fn_transact
	SRCFILE "fujinet.bas",253
	CALL label_FN_TRANSACT
	;[254] END
	SRCFILE "fujinet.bas",254
	RETURN
	ENDP
	;[255] 
	SRCFILE "fujinet.bas",255
	;[256] ' ---------------------------------------------------------------------------
	SRCFILE "fujinet.bas",256
	;[257] ' api_call: full round trip -- open the URL staged at FN_TX/#fn_txlen,
	SRCFILE "fujinet.bas",257
	;[258] ' check status, read up to #net_readlen bytes (caller sets this to the max
	SRCFILE "fujinet.bas",258
	;[259] ' expected reply size, e.g. 418 for /state, 361 for /tables), close.
	SRCFILE "fujinet.bas",259
	;[260] ' Leaves fn_ok = 1 and the reply in FN_RX on success.
	SRCFILE "fujinet.bas",260
	;[261] ' ---------------------------------------------------------------------------
	SRCFILE "fujinet.bas",261
	;[262] ' ac_i/#ac_prev: loop counter and previous STATUS reading for api_call's
	SRCFILE "fujinet.bas",262
	;[263] ' stabilization poll (see below).
	SRCFILE "fujinet.bas",263
	;[264] DIM ac_i
	SRCFILE "fujinet.bas",264
	;[265] DIM #ac_prev
	SRCFILE "fujinet.bas",265
	;[266] api_call: PROCEDURE
	SRCFILE "fujinet.bas",266
	; API_CALL
label_API_CALL:	PROC
	BEGIN
	;[267]     GOSUB net_open
	SRCFILE "fujinet.bas",267
	CALL label_NET_OPEN
	;[268]     IF fn_ok = 0 THEN RETURN
	SRCFILE "fujinet.bas",268
	MVI var_FN_OK,R0
	TSTR R0
	BNE T36
	RETURN
T36:
	;[269] 
	SRCFILE "fujinet.bas",269
	;[270]     ' The RP2040/ESP32 can report STATUS as soon as *some* bytes of the
	SRCFILE "fujinet.bas",270
	;[271]     ' real internet response have arrived, well before the full response
	SRCFILE "fujinet.bas",271
	;[272]     ' does -- open+status+read all happening within the same poll can
	SRCFILE "fujinet.bas",272
	;[273]     ' easily race ahead of that. Rather than guess a fixed delay, poll
	SRCFILE "fujinet.bas",273
	;[274]     ' STATUS repeatedly and treat two consecutive equal (nonzero)
	SRCFILE "fujinet.bas",274
	;[275]     ' readings as "the download has settled" before committing to a
	SRCFILE "fujinet.bas",275
	;[276]     ' read length. Bounded to ~20 frames (~0.33s) of polling so a
	SRCFILE "fujinet.bas",276
	;[277]     ' genuinely stuck connection still falls through to the normal
	SRCFILE "fujinet.bas",277
	;[278]     ' fn_ok=0/timeout handling instead of hanging here.
	SRCFILE "fujinet.bas",278
	;[279]     #ac_prev = 0
	SRCFILE "fujinet.bas",279
	CLRR R0
	MVO R0,var_&AC_PREV
	;[280]     FOR ac_i = 0 TO 19
	SRCFILE "fujinet.bas",280
	MVO R0,var_AC_I
T37:
	;[281]         WAIT
	SRCFILE "fujinet.bas",281
	CALL _wait
	;[282]         GOSUB net_status
	SRCFILE "fujinet.bas",282
	CALL label_NET_STATUS
	;[283]         IF fn_ok = 0 THEN RETURN
	SRCFILE "fujinet.bas",283
	MVI var_FN_OK,R0
	TSTR R0
	BNE T38
	RETURN
T38:
	;[284]         IF #net_avail > 0 AND #net_avail = #ac_prev THEN EXIT FOR
	SRCFILE "fujinet.bas",284
	MVI var_&NET_AVAIL,R0
	CMPI #0,R0
	MVII #65535,R0
	BGT T40
	INCR R0
T40:
	MVI var_&NET_AVAIL,R1
	CMP var_&AC_PREV,R1
	MVII #65535,R1
	BEQ T41
	INCR R1
T41:
	ANDR R1,R0
	BNE T42
	;[285]         #ac_prev = #net_avail
	SRCFILE "fujinet.bas",285
	MVI var_&NET_AVAIL,R0
	MVO R0,var_&AC_PREV
	;[286]     NEXT ac_i
	SRCFILE "fujinet.bas",286
	MVI var_AC_I,R0
	INCR R0
	MVO R0,var_AC_I
	CMPI #19,R0
	BLE T37
T42:
	;[287] 
	SRCFILE "fujinet.bas",287
	;[288]     IF #net_avail < #net_readlen THEN #net_readlen = #net_avail
	SRCFILE "fujinet.bas",288
	MVI var_&NET_AVAIL,R0
	CMP var_&NET_READLEN,R0
	BGE T43
	MVO R0,var_&NET_READLEN
T43:
	;[289] 
	SRCFILE "fujinet.bas",289
	;[290]     GOSUB net_read
	SRCFILE "fujinet.bas",290
	CALL label_NET_READ
	;[291]     GOSUB net_close   ' close regardless of read result
	SRCFILE "fujinet.bas",291
	CALL label_NET_CLOSE
	;[292] END
	SRCFILE "fujinet.bas",292
	RETURN
	ENDP
	;[293] 
	SRCFILE "fujinet.bas",293
	;[294] ' ---------------------------------------------------------------------------
	SRCFILE "fujinet.bas",294
	;[295] ' AppKey. The wire struct (fujiDevice.h's `struct appkey`, packed) is 6
	SRCFILE "fujinet.bas",295
	;[296] ' bytes: creator_lo, creator_hi, app, key, mode, reserved. mode: 0=read,
	SRCFILE "fujinet.bas",296
	;[297] ' 1=write. Sending only 5 bytes (omitting reserved) leaves the firmware's
	SRCFILE "fujinet.bas",297
	;[298] ' transaction_get() blocked waiting for a byte that never arrives, which
	SRCFILE "fujinet.bas",298
	;[299] ' reads back as a timeout, not a protocol error -- easy to misdiagnose.
	SRCFILE "fujinet.bas",299
	;[300] ' appkey_open must be followed by appkey_read or appkey_write, then
	SRCFILE "fujinet.bas",300
	;[301] ' appkey_close, mirroring the C client's read_appkey()/write_appkey().
	SRCFILE "fujinet.bas",301
	;[302] ' ---------------------------------------------------------------------------
	SRCFILE "fujinet.bas",302
	;[303] DIM ak_creator_lo, ak_creator_hi, ak_app, ak_key, ak_mode
	SRCFILE "fujinet.bas",303
	;[304] 
	SRCFILE "fujinet.bas",304
	;[305] appkey_open: PROCEDURE
	SRCFILE "fujinet.bas",305
	; APPKEY_OPEN
label_APPKEY_OPEN:	PROC
	BEGIN
	;[306]     mb_dev = FUJI_DEVICEID
	SRCFILE "fujinet.bas",306
	MVII #112,R0
	MVO R0,var_MB_DEV
	;[307]     mb_cmd = FUJICMD_OPEN_APPKEY
	SRCFILE "fujinet.bas",307
	MVII #220,R0
	MVO R0,var_MB_CMD
	;[308]     mb_nparam = 0
	SRCFILE "fujinet.bas",308
	CLRR R0
	MVO R0,var_MB_NPARAM
	;[309]     POKE (FN_TX + 0), ak_creator_lo
	SRCFILE "fujinet.bas",309
	MVI var_AK_CREATOR_LO,R0
	MVO R0,40000
	;[310]     POKE (FN_TX + 1), ak_creator_hi
	SRCFILE "fujinet.bas",310
	MVI var_AK_CREATOR_HI,R0
	MVO R0,40001
	;[311]     POKE (FN_TX + 2), ak_app
	SRCFILE "fujinet.bas",311
	MVI var_AK_APP,R0
	MVO R0,40002
	;[312]     POKE (FN_TX + 3), ak_key
	SRCFILE "fujinet.bas",312
	MVI var_AK_KEY,R0
	MVO R0,40003
	;[313]     POKE (FN_TX + 4), ak_mode
	SRCFILE "fujinet.bas",313
	MVI var_AK_MODE,R0
	MVO R0,40004
	;[314]     POKE (FN_TX + 5), 0 ' reserved
	SRCFILE "fujinet.bas",314
	CLRR R0
	MVO R0,40005
	;[315]     #fn_txlen = 6
	SRCFILE "fujinet.bas",315
	MVII #6,R0
	MVO R0,var_&FN_TXLEN
	;[316]     GOSUB fn_transact
	SRCFILE "fujinet.bas",316
	CALL label_FN_TRANSACT
	;[317] END
	SRCFILE "fujinet.bas",317
	RETURN
	ENDP
	;[318] 
	SRCFILE "fujinet.bas",318
	;[319] ' Reads into SC_ names buffer at address #fn_src (caller sets), up to
	SRCFILE "fujinet.bas",319
	;[320] ' fn_len bytes. Actual byte count returned in fn_len after the call (from
	SRCFILE "fujinet.bas",320
	;[321] ' RXLEN); callers should NUL-terminate at that offset.
	SRCFILE "fujinet.bas",321
	;[322] ' Caller sets #fn_src (destination) and ls_max (destination buffer size,
	SRCFILE "fujinet.bas",322
	;[323] ' including room for the NUL this always writes at fn_len). Clamps to
	SRCFILE "fujinet.bas",323
	;[324] ' ls_max-1 bytes copied -- appkeys can be up to 64 bytes but destinations
	SRCFILE "fujinet.bas",324
	;[325] ' like SC_NAME are much smaller, and always NUL-terminates at fn_len so a
	SRCFILE "fujinet.bas",325
	;[326] ' short stored value doesn't leave trailing bytes undefined for callers
	SRCFILE "fujinet.bas",326
	;[327] ' (like compose_url via fn_strlen) that scan for the terminator.
	SRCFILE "fujinet.bas",327
	;[328] appkey_read: PROCEDURE
	SRCFILE "fujinet.bas",328
	; APPKEY_READ
label_APPKEY_READ:	PROC
	BEGIN
	;[329]     mb_dev = FUJI_DEVICEID
	SRCFILE "fujinet.bas",329
	MVII #112,R0
	MVO R0,var_MB_DEV
	;[330]     mb_cmd = FUJICMD_READ_APPKEY
	SRCFILE "fujinet.bas",330
	MVII #221,R0
	MVO R0,var_MB_CMD
	;[331]     mb_nparam = 0
	SRCFILE "fujinet.bas",331
	CLRR R0
	MVO R0,var_MB_NPARAM
	;[332]     #fn_txlen = 0
	SRCFILE "fujinet.bas",332
	MVO R0,var_&FN_TXLEN
	;[333]     GOSUB fn_transact
	SRCFILE "fujinet.bas",333
	CALL label_FN_TRANSACT
	;[334]     IF fn_ok THEN
	SRCFILE "fujinet.bas",334
	MVI var_FN_OK,R0
	TSTR R0
	BEQ T44
	;[335]         ' The rs232 transport (rs232Fuji::fujicore_read_app_key, verified
	SRCFILE "fujinet.bas",335
	;[336]         ' against fujinet-firmware source and a live byte dump) prepends
	SRCFILE "fujinet.bas",336
	;[337]         ' a 2-byte little-endian length ahead of the actual appkey bytes
	SRCFILE "fujinet.bas",337
	;[338]         ' -- unlike a network READ, an appkey READ takes no length
	SRCFILE "fujinet.bas",338
	;[339]         ' parameter, so the firmware makes the reply self-describing
	SRCFILE "fujinet.bas",339
	;[340]         ' instead. This is specific to appkey reads on this transport;
	SRCFILE "fujinet.bas",340
	;[341]         ' network reads carry no such prefix. RXLEN (FN_RXLEN_LO/HI)
	SRCFILE "fujinet.bas",341
	;[342]         ' covers the prefix + data together, so use the embedded prefix
	SRCFILE "fujinet.bas",342
	;[343]         ' itself as the real data length and skip past it.
	SRCFILE "fujinet.bas",343
	;[344]         fn_len = (PEEK(FN_RX) AND 255) + (PEEK(FN_RX + 1) AND 255) * 256
	SRCFILE "fujinet.bas",344
	MVI 40256,R0
	ANDI #255,R0
	MVI 40257,R1
	ANDI #255,R1
	SWAP R1
	ANDI #65280,R1
	ADDR R1,R0
	MVO R0,var_FN_LEN
	;[345]         IF fn_len > ls_max - 1 THEN fn_len = ls_max - 1
	SRCFILE "fujinet.bas",345
	MVI var_FN_LEN,R0
	MVI var_LS_MAX,R1
	DECR R1
	CMPR R1,R0
	BLE T45
	MVI var_LS_MAX,R0
	DECR R0
	MVO R0,var_FN_LEN
T45:
	;[346]         FOR fn_i = 0 TO fn_len - 1
	SRCFILE "fujinet.bas",346
	CLRR R0
	MVO R0,var_FN_I
T46:
	;[347]             POKE (#fn_src + fn_i), PEEK(FN_RX + 2 + fn_i) AND 255
	SRCFILE "fujinet.bas",347
	MVI var_FN_I,R1
	ADDI #40258,R1
	MVI@ R1,R0
	ANDI #255,R0
	MVI var_&FN_SRC,R1
	ADD var_FN_I,R1
	MVO@ R0,R1
	;[348]         NEXT fn_i
	SRCFILE "fujinet.bas",348
	MVI var_FN_I,R0
	INCR R0
	MVO R0,var_FN_I
	MVI var_FN_LEN,R1
	DECR R1
	CMPR R1,R0
	BLE T46
	;[349]         POKE (#fn_src + fn_len), 0
	SRCFILE "fujinet.bas",349
	CLRR R0
	MVI var_&FN_SRC,R1
	ADD var_FN_LEN,R1
	MVO@ R0,R1
	;[350]     ELSE
	SRCFILE "fujinet.bas",350
	B T47
T44:
	;[351]         fn_len = 0
	SRCFILE "fujinet.bas",351
	CLRR R0
	MVO R0,var_FN_LEN
	;[352]     END IF
	SRCFILE "fujinet.bas",352
T47:
	;[353] END
	SRCFILE "fujinet.bas",353
	RETURN
	ENDP
	;[354] 
	SRCFILE "fujinet.bas",354
	;[355] ' Writes fn_len bytes from #fn_src (an SC_ buffer) as the appkey payload.
	SRCFILE "fujinet.bas",355
	;[356] appkey_write: PROCEDURE
	SRCFILE "fujinet.bas",356
	; APPKEY_WRITE
label_APPKEY_WRITE:	PROC
	BEGIN
	;[357]     mb_dev = FUJI_DEVICEID
	SRCFILE "fujinet.bas",357
	MVII #112,R0
	MVO R0,var_MB_DEV
	;[358]     mb_cmd = FUJICMD_WRITE_APPKEY
	SRCFILE "fujinet.bas",358
	MVII #222,R0
	MVO R0,var_MB_CMD
	;[359]     mb_nparam = 0
	SRCFILE "fujinet.bas",359
	CLRR R0
	MVO R0,var_MB_NPARAM
	;[360]     FOR fn_i = 0 TO fn_len - 1
	SRCFILE "fujinet.bas",360
	MVO R0,var_FN_I
T48:
	;[361]         POKE (FN_TX + fn_i), PEEK(#fn_src + fn_i) AND 255
	SRCFILE "fujinet.bas",361
	MVI var_&FN_SRC,R1
	ADD var_FN_I,R1
	MVI@ R1,R0
	ANDI #255,R0
	MVI var_FN_I,R1
	ADDI #40000,R1
	MVO@ R0,R1
	;[362]     NEXT fn_i
	SRCFILE "fujinet.bas",362
	MVI var_FN_I,R0
	INCR R0
	MVO R0,var_FN_I
	MVI var_FN_LEN,R1
	DECR R1
	CMPR R1,R0
	BLE T48
	;[363]     #fn_txlen = fn_len
	SRCFILE "fujinet.bas",363
	MVI var_FN_LEN,R0
	MVO R0,var_&FN_TXLEN
	;[364]     GOSUB fn_transact
	SRCFILE "fujinet.bas",364
	CALL label_FN_TRANSACT
	;[365] END
	SRCFILE "fujinet.bas",365
	RETURN
	ENDP
	;[366] 
	SRCFILE "fujinet.bas",366
	;[367] appkey_close: PROCEDURE
	SRCFILE "fujinet.bas",367
	; APPKEY_CLOSE
label_APPKEY_CLOSE:	PROC
	BEGIN
	;[368]     mb_dev = FUJI_DEVICEID
	SRCFILE "fujinet.bas",368
	MVII #112,R0
	MVO R0,var_MB_DEV
	;[369]     mb_cmd = FUJICMD_CLOSE_APPKEY
	SRCFILE "fujinet.bas",369
	MVII #219,R0
	MVO R0,var_MB_CMD
	;[370]     mb_nparam = 0
	SRCFILE "fujinet.bas",370
	CLRR R0
	MVO R0,var_MB_NPARAM
	;[371]     #fn_txlen = 0
	SRCFILE "fujinet.bas",371
	MVO R0,var_&FN_TXLEN
	;[372]     GOSUB fn_transact
	SRCFILE "fujinet.bas",372
	CALL label_FN_TRANSACT
	;[373] END
	SRCFILE "fujinet.bas",373
	RETURN
	ENDP
	;ENDFILE
	;FILE texas.bas
	;[37]     INCLUDE "gfx.bas"
	SRCFILE "texas.bas",37
	;FILE gfx.bas
	;[1] ' gfx.bas -- card GRAM bitmaps and draw routines.
	SRCFILE "gfx.bas",1
	;[2] '
	SRCFILE "gfx.bas",2
	;[3] ' Card faces and the print_card/foreground_color rendering logic are ported
	SRCFILE "gfx.bas",3
	;[4] ' verbatim from carlsson's intv/5card-test-display.bas mock. cardtop holds
	SRCFILE "gfx.bas",4
	;[5] ' 14 GRAM images (index 0 = card back/blank, 1-13 = ranks 2..A), cardbot
	SRCFILE "gfx.bas",5
	;[6] ' holds 7 (index 0 = blank, 1-4 = suit bottoms for DIAMONDS/HEARTS/CLUBS/
	SRCFILE "gfx.bas",6
	;[7] ' SPADES, plus 2 more finishing the set) -- see print_card for the exact
	SRCFILE "gfx.bas",7
	;[8] ' index math. DEFINE loads these into GRAM slots 0-13 (screen codes 256-269)
	SRCFILE "gfx.bas",8
	;[9] ' and 14-20 (screen codes 270-276) respectively.
	SRCFILE "gfx.bas",9
	;[10] 
	SRCFILE "gfx.bas",10
	;[11]     CONST DIAMONDS = 1
	SRCFILE "gfx.bas",11
	;[12]     CONST HEARTS = 2
	SRCFILE "gfx.bas",12
	;[13]     CONST CLUBS = 3
	SRCFILE "gfx.bas",13
	;[14]     CONST SPADES = 4
	SRCFILE "gfx.bas",14
	;[15] 
	SRCFILE "gfx.bas",15
	;[16] ' ---------------------------------------------------------------------------
	SRCFILE "gfx.bas",16
	;[17] ' gfx_init: load both GRAM sets. Must run once at startup, each DEFINE
	SRCFILE "gfx.bas",17
	;[18] ' followed by a WAIT (GRAM loads take effect on the next video frame; a
	SRCFILE "gfx.bas",18
	;[19] ' second DEFINE in the same frame would silently overwrite the first).
	SRCFILE "gfx.bas",19
	;[20] ' ---------------------------------------------------------------------------
	SRCFILE "gfx.bas",20
	;[21] gfx_init: PROCEDURE
	SRCFILE "gfx.bas",21
	; GFX_INIT
label_GFX_INIT:	PROC
	BEGIN
	;[22]     DEFINE 0, 14, cardtop : WAIT
	SRCFILE "gfx.bas",22
	CLRR R0
	MVO R0,_gram_target
	MVII #14,R0
	MVO R0,_gram_total
	MVII #label_CARDTOP,R0
	MVO R0,_gram_bitmap
	CALL _wait
	;[23]     DEFINE 14, 7, cardbot : WAIT
	SRCFILE "gfx.bas",23
	MVII #14,R0
	MVO R0,_gram_target
	MVII #7,R0
	MVO R0,_gram_total
	MVII #label_CARDBOT,R0
	MVO R0,_gram_bitmap
	CALL _wait
	;[24] END
	SRCFILE "gfx.bas",24
	RETURN
	ENDP
	;[25] 
	SRCFILE "gfx.bas",25
	;[26] ' ---------------------------------------------------------------------------
	SRCFILE "gfx.bas",26
	;[27] ' print_card: draw one card at screen cell p (top half) / p+20 (bottom
	SRCFILE "gfx.bas",27
	;[28] ' half). Inputs: p (top-left cell), card (1-13, 0 = hidden/back), suit
	SRCFILE "gfx.bas",28
	;[29] ' (1-4, DIAMONDS/HEARTS/CLUBS/SPADES).
	SRCFILE "gfx.bas",29
	;[30] ' ---------------------------------------------------------------------------
	SRCFILE "gfx.bas",30
	;[31] print_card: PROCEDURE
	SRCFILE "gfx.bas",31
	; PRINT_CARD
label_PRINT_CARD:	PROC
	BEGIN
	;[32]     #col = BG_WHITE
	SRCFILE "gfx.bas",32
	MVII #9728,R0
	MVO R0,var_&COL
	;[33]     GOSUB foreground_color
	SRCFILE "gfx.bas",33
	CALL label_FOREGROUND_COLOR
	;[34]     #BACKTAB(p) = #col + (card + 256) * 8
	SRCFILE "gfx.bas",34
	MVI var_CARD,R0
	ADDI #256,R0
	SLL R0,2
	ADDR R0,R0
	ADD var_&COL,R0
	MVII #Q2,R3
	ADD var_P,R3
	MVO@ R0,R3
	;[35]     #BACKTAB(p + 20) = #col + (suit + 270) * 8
	SRCFILE "gfx.bas",35
	MVI var_SUIT,R0
	ADDI #270,R0
	SLL R0,2
	ADDR R0,R0
	ADD var_&COL,R0
	ADDI #20,R3
	MVO@ R0,R3
	;[36] END
	SRCFILE "gfx.bas",36
	RETURN
	ENDP
	;[37] 
	SRCFILE "gfx.bas",37
	;[38] ' ---------------------------------------------------------------------------
	SRCFILE "gfx.bas",38
	;[39] ' foreground_color: pick #col's foreground bits for the card being drawn
	SRCFILE "gfx.bas",39
	;[40] ' (red for D/H, black for C/S, blue for a hidden card), and adjusts `card`
	SRCFILE "gfx.bas",40
	;[41] ' from its wire value (2-14) down to the 1-13 GRAM index.
	SRCFILE "gfx.bas",41
	;[42] ' ---------------------------------------------------------------------------
	SRCFILE "gfx.bas",42
	;[43] foreground_color: PROCEDURE
	SRCFILE "gfx.bas",43
	; FOREGROUND_COLOR
label_FOREGROUND_COLOR:	PROC
	BEGIN
	;[44]     IF card > 0 THEN
	SRCFILE "gfx.bas",44
	MVI var_CARD,R0
	CMPI #0,R0
	BLE T49
	;[45]         card = card - 1 ' compensate for suit runs 23456789TJQKA
	SRCFILE "gfx.bas",45
	DECR R0
	MVO R0,var_CARD
	;[46]         IF suit = DIAMONDS OR suit = HEARTS THEN
	SRCFILE "gfx.bas",46
	MVI var_SUIT,R0
	CMPI #1,R0
	MVII #65535,R0
	BEQ T51
	INCR R0
T51:
	MVI var_SUIT,R1
	CMPI #2,R1
	MVII #65535,R1
	BEQ T52
	INCR R1
T52:
	COMR R1
	ANDR R1,R0
	COMR R1
	XORR R1,R0
	BEQ T50
	;[47]             #col = #col + FG_RED
	SRCFILE "gfx.bas",47
	MVI var_&COL,R0
	ADDI #2,R0
	MVO R0,var_&COL
	;[48]         ELSE
	SRCFILE "gfx.bas",48
	B T53
T50:
	;[49]             #col = #col + FG_BLACK
	SRCFILE "gfx.bas",49
	MVI var_&COL,R0
	MVO R0,var_&COL
	;[50]         END IF
	SRCFILE "gfx.bas",50
T53:
	;[51]     ELSE
	SRCFILE "gfx.bas",51
	B T54
T49:
	;[52]         #col = #col + FG_BLUE
	SRCFILE "gfx.bas",52
	MVI var_&COL,R0
	INCR R0
	MVO R0,var_&COL
	;[53]     END IF
	SRCFILE "gfx.bas",53
T54:
	;[54] END
	SRCFILE "gfx.bas",54
	RETURN
	ENDP
	;[55] 
	SRCFILE "gfx.bas",55
	;[56] cardtop:
	SRCFILE "gfx.bas",56
	; CARDTOP
label_CARDTOP:	;[57] 	BITMAP "oooooooo"
	SRCFILE "gfx.bas",57
	;[58]     BITMAP "oo..o..o"
	SRCFILE "gfx.bas",58
	DECLE 51711
	;[59] 	BITMAP "o.o..o.."
	SRCFILE "gfx.bas",59
	;[60] 	BITMAP "o..o..o."
	SRCFILE "gfx.bas",60
	DECLE 37540
	;[61] 	BITMAP "oo..o..o"
	SRCFILE "gfx.bas",61
	;[62] 	BITMAP "o.o..o.."
	SRCFILE "gfx.bas",62
	DECLE 42185
	;[63] 	BITMAP "o..o..o."
	SRCFILE "gfx.bas",63
	;[64] 	BITMAP "oo..o..o"
	SRCFILE "gfx.bas",64
	DECLE 51602
	;[65] 
	SRCFILE "gfx.bas",65
	;[66] 	BITMAP "oooooooo"
	SRCFILE "gfx.bas",66
	;[67]     BITMAP "o......."
	SRCFILE "gfx.bas",67
	DECLE 33023
	;[68] 	BITMAP "o.oooo.."
	SRCFILE "gfx.bas",68
	;[69] 	BITMAP "o.....o."
	SRCFILE "gfx.bas",69
	DECLE 33468
	;[70] 	BITMAP "o..ooo.."
	SRCFILE "gfx.bas",70
	;[71] 	BITMAP "o.o....."
	SRCFILE "gfx.bas",71
	DECLE 41116
	;[72] 	BITMAP "o.ooooo."
	SRCFILE "gfx.bas",72
	;[73] 	BITMAP "o......."
	SRCFILE "gfx.bas",73
	DECLE 32958
	;[74] 	
	SRCFILE "gfx.bas",74
	;[75] 	BITMAP "oooooooo"
	SRCFILE "gfx.bas",75
	;[76]     BITMAP "o......."
	SRCFILE "gfx.bas",76
	DECLE 33023
	;[77] 	BITMAP "o.oooo.."
	SRCFILE "gfx.bas",77
	;[78] 	BITMAP "o.....o."
	SRCFILE "gfx.bas",78
	DECLE 33468
	;[79] 	BITMAP "o..ooo.."
	SRCFILE "gfx.bas",79
	;[80] 	BITMAP "o.....o."
	SRCFILE "gfx.bas",80
	DECLE 33436
	;[81] 	BITMAP "o.oooo.."
	SRCFILE "gfx.bas",81
	;[82] 	BITMAP "o......."
	SRCFILE "gfx.bas",82
	DECLE 32956
	;[83] 
	SRCFILE "gfx.bas",83
	;[84] 	BITMAP "oooooooo"
	SRCFILE "gfx.bas",84
	;[85]     BITMAP "o......."
	SRCFILE "gfx.bas",85
	DECLE 33023
	;[86] 	BITMAP "o.o...o."
	SRCFILE "gfx.bas",86
	;[87] 	BITMAP "o.o...o."
	SRCFILE "gfx.bas",87
	DECLE 41634
	;[88] 	BITMAP "o.ooooo."
	SRCFILE "gfx.bas",88
	;[89] 	BITMAP "o.....o."
	SRCFILE "gfx.bas",89
	DECLE 33470
	;[90] 	BITMAP "o.....o."
	SRCFILE "gfx.bas",90
	;[91] 	BITMAP "o......."
	SRCFILE "gfx.bas",91
	DECLE 32898
	;[92] 
	SRCFILE "gfx.bas",92
	;[93] 	BITMAP "oooooooo"
	SRCFILE "gfx.bas",93
	;[94]     BITMAP "o......."
	SRCFILE "gfx.bas",94
	DECLE 33023
	;[95] 	BITMAP "o.ooooo."
	SRCFILE "gfx.bas",95
	;[96] 	BITMAP "o.o....."
	SRCFILE "gfx.bas",96
	DECLE 41150
	;[97] 	BITMAP "o.oooo.."
	SRCFILE "gfx.bas",97
	;[98] 	BITMAP "o.....o."
	SRCFILE "gfx.bas",98
	DECLE 33468
	;[99] 	BITMAP "o.oooo.."
	SRCFILE "gfx.bas",99
	;[100] 	BITMAP "o......."
	SRCFILE "gfx.bas",100
	DECLE 32956
	;[101] 
	SRCFILE "gfx.bas",101
	;[102] 	BITMAP "oooooooo"
	SRCFILE "gfx.bas",102
	;[103]     BITMAP "o......."
	SRCFILE "gfx.bas",103
	DECLE 33023
	;[104] 	BITMAP "o...oo.."
	SRCFILE "gfx.bas",104
	;[105] 	BITMAP "o..o...."
	SRCFILE "gfx.bas",105
	DECLE 37004
	;[106] 	BITMAP "o.oooo.."
	SRCFILE "gfx.bas",106
	;[107] 	BITMAP "o.o...o."
	SRCFILE "gfx.bas",107
	DECLE 41660
	;[108] 	BITMAP "o..ooo.."
	SRCFILE "gfx.bas",108
	;[109] 	BITMAP "o......."
	SRCFILE "gfx.bas",109
	DECLE 32924
	;[110] 
	SRCFILE "gfx.bas",110
	;[111] 	BITMAP "oooooooo"
	SRCFILE "gfx.bas",111
	;[112]     BITMAP "o......."
	SRCFILE "gfx.bas",112
	DECLE 33023
	;[113] 	BITMAP "o.ooooo."
	SRCFILE "gfx.bas",113
	;[114] 	BITMAP "o.....o."
	SRCFILE "gfx.bas",114
	DECLE 33470
	;[115] 	BITMAP "o....o.."
	SRCFILE "gfx.bas",115
	;[116] 	BITMAP "o...o..."
	SRCFILE "gfx.bas",116
	DECLE 34948
	;[117] 	BITMAP "o...o..."
	SRCFILE "gfx.bas",117
	;[118] 	BITMAP "o......."
	SRCFILE "gfx.bas",118
	DECLE 32904
	;[119] 
	SRCFILE "gfx.bas",119
	;[120] 	BITMAP "oooooooo"
	SRCFILE "gfx.bas",120
	;[121]     BITMAP "o......."
	SRCFILE "gfx.bas",121
	DECLE 33023
	;[122] 	BITMAP "o..ooo.."
	SRCFILE "gfx.bas",122
	;[123] 	BITMAP "o.o...o."
	SRCFILE "gfx.bas",123
	DECLE 41628
	;[124] 	BITMAP "o..ooo.."
	SRCFILE "gfx.bas",124
	;[125] 	BITMAP "o.o...o."
	SRCFILE "gfx.bas",125
	DECLE 41628
	;[126] 	BITMAP "o..ooo.."
	SRCFILE "gfx.bas",126
	;[127] 	BITMAP "o......."
	SRCFILE "gfx.bas",127
	DECLE 32924
	;[128] 
	SRCFILE "gfx.bas",128
	;[129] 	BITMAP "oooooooo"
	SRCFILE "gfx.bas",129
	;[130]     BITMAP "o......."
	SRCFILE "gfx.bas",130
	DECLE 33023
	;[131] 	BITMAP "o..ooo.."
	SRCFILE "gfx.bas",131
	;[132] 	BITMAP "o.o...o."
	SRCFILE "gfx.bas",132
	DECLE 41628
	;[133] 	BITMAP "o..oooo."
	SRCFILE "gfx.bas",133
	;[134] 	BITMAP "o.....o."
	SRCFILE "gfx.bas",134
	DECLE 33438
	;[135] 	BITMAP "o..ooo.."
	SRCFILE "gfx.bas",135
	;[136] 	BITMAP "o......."
	SRCFILE "gfx.bas",136
	DECLE 32924
	;[137] 
	SRCFILE "gfx.bas",137
	;[138] 	BITMAP "oooooooo"
	SRCFILE "gfx.bas",138
	;[139]     BITMAP "o......."
	SRCFILE "gfx.bas",139
	DECLE 33023
	;[140] 	BITMAP "o.o..o.."
	SRCFILE "gfx.bas",140
	;[141] 	BITMAP "o.o.o.o."
	SRCFILE "gfx.bas",141
	DECLE 43684
	;[142] 	BITMAP "o.o.o.o."
	SRCFILE "gfx.bas",142
	;[143] 	BITMAP "o.o.o.o."
	SRCFILE "gfx.bas",143
	DECLE 43690
	;[144] 	BITMAP "o.o..o.."
	SRCFILE "gfx.bas",144
	;[145] 	BITMAP "o......."
	SRCFILE "gfx.bas",145
	DECLE 32932
	;[146] 
	SRCFILE "gfx.bas",146
	;[147] 	BITMAP "oooooooo"
	SRCFILE "gfx.bas",147
	;[148]     BITMAP "o......."
	SRCFILE "gfx.bas",148
	DECLE 33023
	;[149] 	BITMAP "o.....o."
	SRCFILE "gfx.bas",149
	;[150] 	BITMAP "o.....o."
	SRCFILE "gfx.bas",150
	DECLE 33410
	;[151] 	BITMAP "o.....o."
	SRCFILE "gfx.bas",151
	;[152] 	BITMAP "o.o...o."
	SRCFILE "gfx.bas",152
	DECLE 41602
	;[153] 	BITMAP "o..ooo.."
	SRCFILE "gfx.bas",153
	;[154] 	BITMAP "o......."
	SRCFILE "gfx.bas",154
	DECLE 32924
	;[155] 
	SRCFILE "gfx.bas",155
	;[156] 	BITMAP "oooooooo"
	SRCFILE "gfx.bas",156
	;[157]     BITMAP "o......."
	SRCFILE "gfx.bas",157
	DECLE 33023
	;[158] 	BITMAP "o..ooo.."
	SRCFILE "gfx.bas",158
	;[159] 	BITMAP "o.o...o."
	SRCFILE "gfx.bas",159
	DECLE 41628
	;[160] 	BITMAP "o.o.o.o."
	SRCFILE "gfx.bas",160
	;[161] 	BITMAP "o.o..o.."
	SRCFILE "gfx.bas",161
	DECLE 42154
	;[162] 	BITMAP "o..oo.o."
	SRCFILE "gfx.bas",162
	;[163]     BITMAP "o......."
	SRCFILE "gfx.bas",163
	DECLE 32922
	;[164] 
	SRCFILE "gfx.bas",164
	;[165] 	BITMAP "oooooooo"
	SRCFILE "gfx.bas",165
	;[166]     BITMAP "o......."
	SRCFILE "gfx.bas",166
	DECLE 33023
	;[167] 	BITMAP "o.o...o."
	SRCFILE "gfx.bas",167
	;[168] 	BITMAP "o.o..o.."
	SRCFILE "gfx.bas",168
	DECLE 42146
	;[169] 	BITMAP "o.ooo..."
	SRCFILE "gfx.bas",169
	;[170] 	BITMAP "o.o..o.."
	SRCFILE "gfx.bas",170
	DECLE 42168
	;[171] 	BITMAP "o.o...o."
	SRCFILE "gfx.bas",171
	;[172]     BITMAP "o......."	
	SRCFILE "gfx.bas",172
	DECLE 32930
	;[173] 
	SRCFILE "gfx.bas",173
	;[174] 	BITMAP "oooooooo"
	SRCFILE "gfx.bas",174
	;[175] 	BITMAP "o......."
	SRCFILE "gfx.bas",175
	DECLE 33023
	;[176] 	BITMAP "o..ooo.."
	SRCFILE "gfx.bas",176
	;[177] 	BITMAP "o.o...o."
	SRCFILE "gfx.bas",177
	DECLE 41628
	;[178] 	BITMAP "o.ooooo."
	SRCFILE "gfx.bas",178
	;[179] 	BITMAP "o.o...o."
	SRCFILE "gfx.bas",179
	DECLE 41662
	;[180] 	BITMAP "o.o...o."
	SRCFILE "gfx.bas",180
	;[181] 	BITMAP "o......."	
	SRCFILE "gfx.bas",181
	DECLE 32930
	;[182] 
	SRCFILE "gfx.bas",182
	;[183] cardbot:
	SRCFILE "gfx.bas",183
	; CARDBOT
label_CARDBOT:	;[184] 	BITMAP "o.o..o.."
	SRCFILE "gfx.bas",184
	;[185]     BITMAP "o..o..o."
	SRCFILE "gfx.bas",185
	DECLE 37540
	;[186] 	BITMAP "oo..o..o"
	SRCFILE "gfx.bas",186
	;[187] 	BITMAP "o.o..o.."
	SRCFILE "gfx.bas",187
	DECLE 42185
	;[188] 	BITMAP "o..o..o."
	SRCFILE "gfx.bas",188
	;[189] 	BITMAP "oo..o..o"
	SRCFILE "gfx.bas",189
	DECLE 51602
	;[190] 	BITMAP "o.o..o.."
	SRCFILE "gfx.bas",190
	;[191] 	BITMAP "oooooooo"
	SRCFILE "gfx.bas",191
	DECLE 65444
	;[192] 
	SRCFILE "gfx.bas",192
	;[193] 	BITMAP "o......."
	SRCFILE "gfx.bas",193
	;[194]     BITMAP "o...o..."
	SRCFILE "gfx.bas",194
	DECLE 34944
	;[195] 	BITMAP "o..ooo.."
	SRCFILE "gfx.bas",195
	;[196] 	BITMAP "o.ooooo."
	SRCFILE "gfx.bas",196
	DECLE 48796
	;[197] 	BITMAP "o..ooo.."
	SRCFILE "gfx.bas",197
	;[198] 	BITMAP "o...o..."
	SRCFILE "gfx.bas",198
	DECLE 34972
	;[199] 	BITMAP "o......."
	SRCFILE "gfx.bas",199
	;[200] 	BITMAP "oooooooo"
	SRCFILE "gfx.bas",200
	DECLE 65408
	;[201] 
	SRCFILE "gfx.bas",201
	;[202] 	BITMAP "o......."
	SRCFILE "gfx.bas",202
	;[203]     BITMAP "o..o.o.."
	SRCFILE "gfx.bas",203
	DECLE 38016
	;[204] 	BITMAP "o.ooooo."
	SRCFILE "gfx.bas",204
	;[205] 	BITMAP "o.ooooo."
	SRCFILE "gfx.bas",205
	DECLE 48830
	;[206] 	BITMAP "o..ooo.."
	SRCFILE "gfx.bas",206
	;[207] 	BITMAP "o...o..."
	SRCFILE "gfx.bas",207
	DECLE 34972
	;[208] 	BITMAP "o......."
	SRCFILE "gfx.bas",208
	;[209] 	BITMAP "oooooooo"
	SRCFILE "gfx.bas",209
	DECLE 65408
	;[210] 
	SRCFILE "gfx.bas",210
	;[211] 	BITMAP "o......."
	SRCFILE "gfx.bas",211
	;[212]     BITMAP "o..ooo.."
	SRCFILE "gfx.bas",212
	DECLE 40064
	;[213] 	BITMAP "o.o.o.o."
	SRCFILE "gfx.bas",213
	;[214] 	BITMAP "o.ooooo."
	SRCFILE "gfx.bas",214
	DECLE 48810
	;[215] 	BITMAP "o.o.o.o."
	SRCFILE "gfx.bas",215
	;[216] 	BITMAP "o...o..."
	SRCFILE "gfx.bas",216
	DECLE 34986
	;[217] 	BITMAP "o......."
	SRCFILE "gfx.bas",217
	;[218] 	BITMAP "oooooooo"
	SRCFILE "gfx.bas",218
	DECLE 65408
	;[219] 
	SRCFILE "gfx.bas",219
	;[220] 	BITMAP "o......."
	SRCFILE "gfx.bas",220
	;[221]     BITMAP "o..ooo.."
	SRCFILE "gfx.bas",221
	DECLE 40064
	;[222] 	BITMAP "o.ooooo."
	SRCFILE "gfx.bas",222
	;[223] 	BITMAP "o.ooooo."
	SRCFILE "gfx.bas",223
	DECLE 48830
	;[224] 	BITMAP "o...o..."
	SRCFILE "gfx.bas",224
	;[225] 	BITMAP "o...o..."
	SRCFILE "gfx.bas",225
	DECLE 34952
	;[226] 	BITMAP "o......."
	SRCFILE "gfx.bas",226
	;[227] 	BITMAP "oooooooo"
	SRCFILE "gfx.bas",227
	DECLE 65408
	;[228] 
	SRCFILE "gfx.bas",228
	;[229] 	BITMAP "o......."
	SRCFILE "gfx.bas",229
	;[230] 	BITMAP "o......."
	SRCFILE "gfx.bas",230
	DECLE 32896
	;[231] 	BITMAP "o......."
	SRCFILE "gfx.bas",231
	;[232] 	BITMAP "o......."
	SRCFILE "gfx.bas",232
	DECLE 32896
	;[233] 	BITMAP "o......."
	SRCFILE "gfx.bas",233
	;[234] 	BITMAP "o......."
	SRCFILE "gfx.bas",234
	DECLE 32896
	;[235] 	BITMAP "o......."
	SRCFILE "gfx.bas",235
	;[236] 	BITMAP "o......."
	SRCFILE "gfx.bas",236
	DECLE 32896
	;[237] 
	SRCFILE "gfx.bas",237
	;[238] 	BITMAP ".ooooo.."
	SRCFILE "gfx.bas",238
	;[239] 	BITMAP "ooo.ooo."
	SRCFILE "gfx.bas",239
	DECLE 61052
	;[240] 	BITMAP "ooo.ooo."
	SRCFILE "gfx.bas",240
	;[241] 	BITMAP "ooo...o."
	SRCFILE "gfx.bas",241
	DECLE 58094
	;[242] 	BITMAP "ooooooo."
	SRCFILE "gfx.bas",242
	;[243] 	BITMAP "ooooooo."
	SRCFILE "gfx.bas",243
	DECLE 65278
	;[244] 	BITMAP ".ooooo.."
	SRCFILE "gfx.bas",244
	;[245] 	BITMAP "........"
	SRCFILE "gfx.bas",245
	DECLE 124
	;[246] 
	SRCFILE "gfx.bas",246
	;ENDFILE
	;FILE texas.bas
	;[38]     INCLUDE "state.bas"
	SRCFILE "texas.bas",38
	;FILE state.bas
	;[1] ' state.bas -- binary Game/Tables wire format, read in place out of FN_RX.
	SRCFILE "state.bas",1
	;[2] '
	SRCFILE "state.bas",2
	;[3] ' Per the plan: never copy the reply into IntyBASIC variables. These are
	SRCFILE "state.bas",3
	;[4] ' just fixed offsets (matching server/util.go's appendFixedLengthString
	SRCFILE "state.bas",4
	;[5] ' binary layout, requested with ?bin=1 -- uint16 fields are little-endian,
	SRCFILE "state.bas",5
	;[6] ' the server's default; &be=1 was dropped after pot/bet started showing
	SRCFILE "state.bas",6
	;[7] ' up as an exact multiple of 256, the signature of a byte-order mismatch
	SRCFILE "state.bas",7
	;[8] ' on the server's binary.BigEndian path, which is exercised by only one
	SRCFILE "state.bas",8
	;[9] ' other client in the whole family (CoCo/6809) versus everything else
	SRCFILE "state.bas",9
	;[10] ' being little-endian x86/6502/Z80)
	SRCFILE "state.bas",10
	;[11] ' plus small DEF FN accessors that PEEK straight out of FN_RX.
	SRCFILE "state.bas",11
	;[12] '
	SRCFILE "state.bas",12
	;[13] ' Texas Hold'em delta from 5 Card Stud: community[11] is inserted right
	SRCFILE "state.bas",13
	;[14] ' after viewing (offset 87), shifting everything from validMoveCount on
	SRCFILE "state.bas",14
	;[15] ' by +11. Offsets locked by the _Static_asserts in
	SRCFILE "state.bas",15
	;[16] ' support/host-test/holdem_host_test.c against src/misc.h.
	SRCFILE "state.bas",16
	;[17] '
	SRCFILE "state.bas",17
	;[18] ' /state, /move/XX, /leave -> Game struct, up to 429 bytes:
	SRCFILE "state.bas",18
	;[19] '   0   lastResult[81]
	SRCFILE "state.bas",19
	;[20] '  81   round (1)              0=waiting 1=PRE-FLOP 2=FLOP 3=TURN 4=RIVER 5=SHOWDOWN
	SRCFILE "state.bas",20
	;[21] '  82   pot (u16 LE)
	SRCFILE "state.bas",21
	;[22] '  84   activePlayer (signed, $FF = -1)
	SRCFILE "state.bas",22
	;[23] '  85   moveTime (1, seconds)
	SRCFILE "state.bas",23
	;[24] '  86   viewing (1, 0/1)
	SRCFILE "state.bas",24
	;[25] '  87   community (11)         up to 5 cards x 2 chars + NUL; "" pre-flop,
	SRCFILE "state.bas",25
	;[26] '                              6/8/10 chars at flop/turn/river-showdown
	SRCFILE "state.bas",26
	;[27] '  98   validMoveCount (1)
	SRCFILE "state.bas",27
	;[28] '  99   validMoves[5] -- always 5 slots, 13 bytes each: move[3] + name[10]
	SRCFILE "state.bas",28
	;[29] ' 164   playerCount (1)
	SRCFILE "state.bas",29
	;[30] ' 165   players[N] -- N = playerCount, 33 bytes each:
	SRCFILE "state.bas",30
	;[31] '         name[9] status(1) bet(u16 LE) move[8] purse(u16 LE) hand[11]
	SRCFILE "state.bas",31
	;[32] '         hand holds the 2 hole cards: "????" masked, "??" folded, 4 real
	SRCFILE "state.bas",32
	;[33] '         chars at showdown (the field keeps 5 Card Stud's 11-byte width)
	SRCFILE "state.bas",33
	;[34] '
	SRCFILE "state.bas",34
	;[35] ' /tables -> Tables struct:
	SRCFILE "state.bas",35
	;[36] '   0   count (1)
	SRCFILE "state.bas",36
	;[37] '   then N x 36 bytes: table[9] name[21] players[6] (literal "cur / max")
	SRCFILE "state.bas",37
	;[38] 
	SRCFILE "state.bas",38
	;[39]     CONST GAME_LASTRESULT     = 0
	SRCFILE "state.bas",39
	;[40]     CONST GAME_ROUND          = 81
	SRCFILE "state.bas",40
	;[41]     CONST GAME_POT            = 82
	SRCFILE "state.bas",41
	;[42]     CONST GAME_ACTIVEPLAYER   = 84
	SRCFILE "state.bas",42
	;[43]     CONST GAME_MOVETIME       = 85
	SRCFILE "state.bas",43
	;[44]     CONST GAME_VIEWING        = 86
	SRCFILE "state.bas",44
	;[45]     CONST GAME_COMMUNITY      = 87
	SRCFILE "state.bas",45
	;[46]     CONST GAME_VALIDMOVECOUNT = 98
	SRCFILE "state.bas",46
	;[47]     CONST GAME_VALIDMOVES     = 99
	SRCFILE "state.bas",47
	;[48]     CONST GAME_PLAYERCOUNT    = 164
	SRCFILE "state.bas",48
	;[49]     CONST GAME_PLAYERS        = 165
	SRCFILE "state.bas",49
	;[50] 
	SRCFILE "state.bas",50
	;[51]     CONST MOVE_STRIDE  = 13
	SRCFILE "state.bas",51
	;[52]     CONST MOVE_CODE    = 0   ' 3 bytes
	SRCFILE "state.bas",52
	;[53]     CONST MOVE_NAME    = 3   ' 10 bytes
	SRCFILE "state.bas",53
	;[54] 
	SRCFILE "state.bas",54
	;[55]     CONST PLAYER_STRIDE = 33
	SRCFILE "state.bas",55
	;[56]     CONST PL_NAME   = 0      ' 9 bytes
	SRCFILE "state.bas",56
	;[57]     CONST PL_STATUS = 9      ' 1 byte: 0 waiting, 1 playing, 2 folded, 3 left, 4 all-in
	SRCFILE "state.bas",57
	;[58]     CONST PL_BET    = 10     ' u16 LE
	SRCFILE "state.bas",58
	;[59]     CONST PL_MOVE   = 12     ' 8 bytes
	SRCFILE "state.bas",59
	;[60]     CONST PL_PURSE  = 20     ' u16 LE
	SRCFILE "state.bas",60
	;[61]     CONST PL_HAND   = 22     ' 11 bytes (2 hole cards x 2 chars + NUL)
	SRCFILE "state.bas",61
	;[62] 
	SRCFILE "state.bas",62
	;[63]     CONST TABLE_STRIDE = 36
	SRCFILE "state.bas",63
	;[64]     CONST TBL_ID      = 0    ' 9 bytes
	SRCFILE "state.bas",64
	;[65]     CONST TBL_NAME    = 9    ' 21 bytes
	SRCFILE "state.bas",65
	;[66]     CONST TBL_PLAYERS = 30   ' 6 bytes, literal "cur / max"
	SRCFILE "state.bas",66
	;[67] 
	SRCFILE "state.bas",67
	;[68]     CONST GAME_MAXLEN   = 429
	SRCFILE "state.bas",68
	;[69]     CONST GAME_MINLEN   = 165  ' fixed prefix through playerCount, 0 players
	SRCFILE "state.bas",69
	;[70]     CONST TABLES_MAXLEN = 361
	SRCFILE "state.bas",70
	;[71] 
	SRCFILE "state.bas",71
	;[72] ' u16be: read a little-endian uint16 at RAM address `addr` (see header note
	SRCFILE "state.bas",72
	;[73] ' on why this is LE despite the name -- kept as u16be to avoid renaming
	SRCFILE "state.bas",73
	;[74] ' every call site for what's ultimately a one-line fix).
	SRCFILE "state.bas",74
	;[75]     DEF FN u16be(addr) = (PEEK(addr + 1) AND 255) * 256 + (PEEK(addr) AND 255)
	SRCFILE "state.bas",75
	;[76] 
	SRCFILE "state.bas",76
	;[77] ' player_addr(i): address of player i's 33-byte record in FN_RX.
	SRCFILE "state.bas",77
	;[78]     DEF FN player_addr(i) = FN_RX + GAME_PLAYERS + i * PLAYER_STRIDE
	SRCFILE "state.bas",78
	;[79] 
	SRCFILE "state.bas",79
	;[80] ' move_addr(i): address of valid-move slot i's 13-byte record in FN_RX.
	SRCFILE "state.bas",80
	;[81]     DEF FN move_addr(i) = FN_RX + GAME_VALIDMOVES + i * MOVE_STRIDE
	SRCFILE "state.bas",81
	;[82] 
	SRCFILE "state.bas",82
	;[83] ' table_addr(i): address of table i's 36-byte record in FN_RX (i is 0-based,
	SRCFILE "state.bas",83
	;[84] ' the record right after the leading count byte).
	SRCFILE "state.bas",84
	;[85]     DEF FN table_addr(i) = FN_RX + 1 + i * TABLE_STRIDE
	SRCFILE "state.bas",85
	;[86] 
	SRCFILE "state.bas",86
	;[87] ' active_player: activePlayer as a signed value (-1..7), converting the
	SRCFILE "state.bas",87
	;[88] ' wire's $FF sentinel. Called as plain `active_player` (no parens -- DEF FN
	SRCFILE "state.bas",88
	;[89] ' with no arguments is defined and invoked without them).
	SRCFILE "state.bas",89
	;[90]     DEF FN active_player = ((PEEK(FN_RX + GAME_ACTIVEPLAYER) AND 255) = 255) * -256 + (PEEK(FN_RX + GAME_ACTIVEPLAYER) AND 255)
	SRCFILE "state.bas",90
	;[91] 
	SRCFILE "state.bas",91
	;[92] ' draw_field is in texas.bas -- it renders a field straight from FN_RX (or
	SRCFILE "state.bas",92
	;[93] ' any RAM address) onto the screen in one pass (uppercase, NUL/pad-stop,
	SRCFILE "state.bas",93
	;[94] ' ASCII->card-code), so there's no need to stage a separate ASCII copy here.
	SRCFILE "state.bas",94
	;ENDFILE
	;FILE texas.bas
	;[39]     INCLUDE "sound.bas"
	SRCFILE "texas.bas",39
	;FILE sound.bas
	;[1] ' sound.bas -- sound effects, modeled on the C clients' platform-specific
	SRCFILE "sound.bas",1
	;[2] ' sound.c implementations (src/msx/sound.c and src/plus4/sound.c gave the
	SRCFILE "sound.bas",2
	;[3] ' clearest Hz-based reference; other platforms use raw PSG period/noise
	SRCFILE "sound.bas",3
	;[4] ' values that amount to the same tones). Every effect there is built from
	SRCFILE "sound.bas",4
	;[5] ' plain square-wave tones (SOUND channel 0-2, no envelope/noise), which is
	SRCFILE "sound.bas",5
	;[6] ' exactly IntyBASIC's SOUND statement, so this is a direct transcription
	SRCFILE "sound.bas",6
	;[7] ' rather than a reinterpretation.
	SRCFILE "sound.bas",7
	;[8] '
	SRCFILE "sound.bas",8
	;[9] ' All effects play on PSG channel 0 -- the game is turn-based and effects
	SRCFILE "sound.bas",9
	;[10] ' are triggered at distinct, non-overlapping UI events, so there's no need
	SRCFILE "sound.bas",10
	;[11] ' for polyphony (and SOUND's channel argument must be a compile-time
	SRCFILE "sound.bas",11
	;[12] ' constant anyway, which would rule out a single generic multi-channel
	SRCFILE "sound.bas",12
	;[13] ' helper).
	SRCFILE "sound.bas",13
	;[14] '
	SRCFILE "sound.bas",14
	;[15] ' SOUND's frequency argument is a 12-bit PSG divisor, computed as
	SRCFILE "sound.bas",15
	;[16] ' round(3579545/32/hz) for NTSC (the manual's documented formula;
	SRCFILE "sound.bas",16
	;[17] ' IntyBASIC exposes no runtime PAL/NTSC query outside the MUSIC/PLAY
	SRCFILE "sound.bas",17
	;[18] ' engine, and this project has only ever been built/tested NTSC). These
	SRCFILE "sound.bas",18
	;[19] ' are precomputed here rather than divided at runtime: 3579545/32 alone
	SRCFILE "sound.bas",19
	;[20] ' is ~111861, which doesn't fit IntyBASIC's 16-bit variables (max 65535),
	SRCFILE "sound.bas",20
	;[21] ' so it only works as a compile-time-folded literal division (a fixed Hz
	SRCFILE "sound.bas",21
	;[22] ' baked into the expression) -- not as CONST-divided-by-a-runtime-variable,
	SRCFILE "sound.bas",22
	;[23] ' which is what a single reusable "play Hz X" helper would need. Since
	SRCFILE "sound.bas",23
	;[24] ' every effect here uses fixed, known-in-advance frequencies anyway,
	SRCFILE "sound.bas",24
	;[25] ' precomputing sidesteps the overflow entirely and is cheaper besides.
	SRCFILE "sound.bas",25
	;[26] '   50Hz->2237  60Hz->1864  70Hz->1598  80Hz->1398  100Hz->1119
	SRCFILE "sound.bas",26
	;[27] '  150Hz->746  300Hz->373  311Hz->360  330Hz->339  340Hz->329
	SRCFILE "sound.bas",27
	;[28] '  350Hz->320  392Hz->285  415Hz->270  430Hz->260  500Hz->224
	SRCFILE "sound.bas",28
	;[29]     CONST SND_VOL = 12
	SRCFILE "sound.bas",29
	;[30] 
	SRCFILE "sound.bas",30
	;[31]     DIM #snd_val, snd_gate, snd_post, snd_i
	SRCFILE "sound.bas",31
	;[32] 
	SRCFILE "sound.bas",32
	;[33] ' ---------------------------------------------------------------------------
	SRCFILE "sound.bas",33
	;[34] ' play_tone: one square-wave note on channel 0. #snd_val = precomputed PSG
	SRCFILE "sound.bas",34
	;[35] ' divisor (see table above), snd_gate = frames the tone sounds, snd_post =
	SRCFILE "sound.bas",35
	;[36] ' frames of silence after (both "vblank" counts, taken directly from the
	SRCFILE "sound.bas",36
	;[37] ' reference implementations since they're already frame units at ~60Hz).
	SRCFILE "sound.bas",37
	;[38] ' ---------------------------------------------------------------------------
	SRCFILE "sound.bas",38
	;[39] play_tone: PROCEDURE
	SRCFILE "sound.bas",39
	; PLAY_TONE
label_PLAY_TONE:	PROC
	BEGIN
	;[40]     SOUND 0, #snd_val, SND_VOL
	SRCFILE "sound.bas",40
	MVI var_&SND_VAL,R0
	MVO R0,496
	SWAP R0
	MVO R0,500
	MVII #12,R0
	MVO R0,507
	;[41]     FOR snd_i = 1 TO snd_gate
	SRCFILE "sound.bas",41
	MVII #1,R0
	MVO R0,var_SND_I
T55:
	;[42]         WAIT
	SRCFILE "sound.bas",42
	CALL _wait
	;[43]     NEXT snd_i
	SRCFILE "sound.bas",43
	MVI var_SND_I,R0
	INCR R0
	MVO R0,var_SND_I
	CMP var_SND_GATE,R0
	BLE T55
	;[44]     SOUND 0, 0, 0
	SRCFILE "sound.bas",44
	CLRR R0
	MVO R0,496
	SWAP R0
	MVO R0,500
	CLRR R0
	MVO R0,507
	;[45]     FOR snd_i = 1 TO snd_post
	SRCFILE "sound.bas",45
	MVII #1,R0
	MVO R0,var_SND_I
T56:
	;[46]         WAIT
	SRCFILE "sound.bas",46
	CALL _wait
	;[47]     NEXT snd_i
	SRCFILE "sound.bas",47
	MVI var_SND_I,R0
	INCR R0
	MVO R0,var_SND_I
	CMP var_SND_POST,R0
	BLE T56
	;[48] END
	SRCFILE "sound.bas",48
	RETURN
	ENDP
	;[49] 
	SRCFILE "sound.bas",49
	;[50] ' sound_join: sit down at a table (3-tone rising figure: 430,340,500 Hz).
	SRCFILE "sound.bas",50
	;[51] sound_join: PROCEDURE
	SRCFILE "sound.bas",51
	; SOUND_JOIN
label_SOUND_JOIN:	PROC
	BEGIN
	;[52]     #snd_val = 260 : snd_gate = 5 : snd_post = 8 : GOSUB play_tone
	SRCFILE "sound.bas",52
	MVII #260,R0
	MVO R0,var_&SND_VAL
	MVII #5,R0
	MVO R0,var_SND_GATE
	MVII #8,R0
	MVO R0,var_SND_POST
	CALL label_PLAY_TONE
	;[53]     #snd_val = 329 : snd_gate = 5 : snd_post = 0 : GOSUB play_tone
	SRCFILE "sound.bas",53
	MVII #329,R0
	MVO R0,var_&SND_VAL
	MVII #5,R0
	MVO R0,var_SND_GATE
	CLRR R0
	MVO R0,var_SND_POST
	CALL label_PLAY_TONE
	;[54]     #snd_val = 224 : snd_gate = 5 : snd_post = 0 : GOSUB play_tone
	SRCFILE "sound.bas",54
	MVII #224,R0
	MVO R0,var_&SND_VAL
	MVII #5,R0
	MVO R0,var_SND_GATE
	CLRR R0
	MVO R0,var_SND_POST
	CALL label_PLAY_TONE
	;[55] END
	SRCFILE "sound.bas",55
	RETURN
	ENDP
	;[56] 
	SRCFILE "sound.bas",56
	;[57] ' sound_myturn: it's your turn to move (double beep, 430,430 Hz).
	SRCFILE "sound.bas",57
	;[58] sound_myturn: PROCEDURE
	SRCFILE "sound.bas",58
	; SOUND_MYTURN
label_SOUND_MYTURN:	PROC
	BEGIN
	;[59]     #snd_val = 260 : snd_gate = 4 : snd_post = 2 : GOSUB play_tone
	SRCFILE "sound.bas",59
	MVII #260,R0
	MVO R0,var_&SND_VAL
	MVII #4,R0
	MVO R0,var_SND_GATE
	MVII #2,R0
	MVO R0,var_SND_POST
	CALL label_PLAY_TONE
	;[60]     #snd_val = 260 : snd_gate = 4 : snd_post = 2 : GOSUB play_tone
	SRCFILE "sound.bas",60
	MVII #260,R0
	MVO R0,var_&SND_VAL
	MVII #4,R0
	MVO R0,var_SND_GATE
	MVII #2,R0
	MVO R0,var_SND_POST
	CALL label_PLAY_TONE
	;[61] END
	SRCFILE "sound.bas",61
	RETURN
	ENDP
	;[62] 
	SRCFILE "sound.bas",62
	;[63] ' sound_gamedone: round/showdown result just landed (4-tone rising
	SRCFILE "sound.bas",63
	;[64] ' fanfare: 311,330,392,415 Hz).
	SRCFILE "sound.bas",64
	;[65] sound_gamedone: PROCEDURE
	SRCFILE "sound.bas",65
	; SOUND_GAMEDONE
label_SOUND_GAMEDONE:	PROC
	BEGIN
	;[66]     #snd_val = 360 : snd_gate = 10 : snd_post = 0 : GOSUB play_tone
	SRCFILE "sound.bas",66
	MVII #360,R0
	MVO R0,var_&SND_VAL
	MVII #10,R0
	MVO R0,var_SND_GATE
	CLRR R0
	MVO R0,var_SND_POST
	CALL label_PLAY_TONE
	;[67]     #snd_val = 339 : snd_gate = 20 : snd_post = 0 : GOSUB play_tone
	SRCFILE "sound.bas",67
	MVII #339,R0
	MVO R0,var_&SND_VAL
	MVII #20,R0
	MVO R0,var_SND_GATE
	CLRR R0
	MVO R0,var_SND_POST
	CALL label_PLAY_TONE
	;[68]     #snd_val = 285 : snd_gate = 10 : snd_post = 0 : GOSUB play_tone
	SRCFILE "sound.bas",68
	MVII #285,R0
	MVO R0,var_&SND_VAL
	MVII #10,R0
	MVO R0,var_SND_GATE
	CLRR R0
	MVO R0,var_SND_POST
	CALL label_PLAY_TONE
	;[69]     #snd_val = 270 : snd_gate = 20 : snd_post = 0 : GOSUB play_tone
	SRCFILE "sound.bas",69
	MVII #270,R0
	MVO R0,var_&SND_VAL
	MVII #20,R0
	MVO R0,var_SND_GATE
	CLRR R0
	MVO R0,var_SND_POST
	CALL label_PLAY_TONE
	;[70] END
	SRCFILE "sound.bas",70
	RETURN
	ENDP
	;[71] 
	SRCFILE "sound.bas",71
	;[72] ' sound_deal: a new hand's cards have arrived (150 Hz click). The C clients
	SRCFILE "sound.bas",72
	;[73] ' click once per card as each is dealt; we don't track per-card deal
	SRCFILE "sound.bas",73
	;[74] ' state (cards just render as soon as they're in the fetched hand), so
	SRCFILE "sound.bas",74
	;[75] ' this plays once per new deal instead of per card.
	SRCFILE "sound.bas",75
	;[76] sound_deal: PROCEDURE
	SRCFILE "sound.bas",76
	; SOUND_DEAL
label_SOUND_DEAL:	PROC
	BEGIN
	;[77]     #snd_val = 746 : snd_gate = 1 : snd_post = 5 : GOSUB play_tone
	SRCFILE "sound.bas",77
	MVII #746,R0
	MVO R0,var_&SND_VAL
	MVII #1,R0
	MVO R0,var_SND_GATE
	MVII #5,R0
	MVO R0,var_SND_POST
	CALL label_PLAY_TONE
	;[78] END
	SRCFILE "sound.bas",78
	RETURN
	ENDP
	;[79] 
	SRCFILE "sound.bas",79
	;[80] ' sound_player_join: another player sits down mid-game (5-tone rising
	SRCFILE "sound.bas",80
	;[81] ' sweep: 50,60,70,80 Hz).
	SRCFILE "sound.bas",81
	;[82] sound_player_join: PROCEDURE
	SRCFILE "sound.bas",82
	; SOUND_PLAYER_JOIN
label_SOUND_PLAYER_JOIN:	PROC
	BEGIN
	;[83]     #snd_val = 2237 : snd_gate = 2 : snd_post = 15 : GOSUB play_tone
	SRCFILE "sound.bas",83
	MVII #2237,R0
	MVO R0,var_&SND_VAL
	MVII #2,R0
	MVO R0,var_SND_GATE
	MVII #15,R0
	MVO R0,var_SND_POST
	CALL label_PLAY_TONE
	;[84]     #snd_val = 1864 : snd_gate = 2 : snd_post = 15 : GOSUB play_tone
	SRCFILE "sound.bas",84
	MVII #1864,R0
	MVO R0,var_&SND_VAL
	MVII #2,R0
	MVO R0,var_SND_GATE
	MVII #15,R0
	MVO R0,var_SND_POST
	CALL label_PLAY_TONE
	;[85]     #snd_val = 1598 : snd_gate = 2 : snd_post = 15 : GOSUB play_tone
	SRCFILE "sound.bas",85
	MVII #1598,R0
	MVO R0,var_&SND_VAL
	MVII #2,R0
	MVO R0,var_SND_GATE
	MVII #15,R0
	MVO R0,var_SND_POST
	CALL label_PLAY_TONE
	;[86]     #snd_val = 1398 : snd_gate = 2 : snd_post = 15 : GOSUB play_tone
	SRCFILE "sound.bas",86
	MVII #1398,R0
	MVO R0,var_&SND_VAL
	MVII #2,R0
	MVO R0,var_SND_GATE
	MVII #15,R0
	MVO R0,var_SND_POST
	CALL label_PLAY_TONE
	;[87] END
	SRCFILE "sound.bas",87
	RETURN
	ENDP
	;[88] 
	SRCFILE "sound.bas",88
	;[89] ' sound_player_left: a player leaves mid-game (falling sweep, mirror of join).
	SRCFILE "sound.bas",89
	;[90] sound_player_left: PROCEDURE
	SRCFILE "sound.bas",90
	; SOUND_PLAYER_LEFT
label_SOUND_PLAYER_LEFT:	PROC
	BEGIN
	;[91]     #snd_val = 1398 : snd_gate = 2 : snd_post = 15 : GOSUB play_tone
	SRCFILE "sound.bas",91
	MVII #1398,R0
	MVO R0,var_&SND_VAL
	MVII #2,R0
	MVO R0,var_SND_GATE
	MVII #15,R0
	MVO R0,var_SND_POST
	CALL label_PLAY_TONE
	;[92]     #snd_val = 1598 : snd_gate = 2 : snd_post = 15 : GOSUB play_tone
	SRCFILE "sound.bas",92
	MVII #1598,R0
	MVO R0,var_&SND_VAL
	MVII #2,R0
	MVO R0,var_SND_GATE
	MVII #15,R0
	MVO R0,var_SND_POST
	CALL label_PLAY_TONE
	;[93]     #snd_val = 1864 : snd_gate = 2 : snd_post = 15 : GOSUB play_tone
	SRCFILE "sound.bas",93
	MVII #1864,R0
	MVO R0,var_&SND_VAL
	MVII #2,R0
	MVO R0,var_SND_GATE
	MVII #15,R0
	MVO R0,var_SND_POST
	CALL label_PLAY_TONE
	;[94]     #snd_val = 2237 : snd_gate = 2 : snd_post = 15 : GOSUB play_tone
	SRCFILE "sound.bas",94
	MVII #2237,R0
	MVO R0,var_&SND_VAL
	MVII #2,R0
	MVO R0,var_SND_GATE
	MVII #15,R0
	MVO R0,var_SND_POST
	CALL label_PLAY_TONE
	;[95] END
	SRCFILE "sound.bas",95
	RETURN
	ENDP
	;[96] 
	SRCFILE "sound.bas",96
	;[97] ' sound_select: a move or table selection was confirmed (2-tone rising
	SRCFILE "sound.bas",97
	;[98] ' chirp: 300,350 Hz).
	SRCFILE "sound.bas",98
	;[99] sound_select: PROCEDURE
	SRCFILE "sound.bas",99
	; SOUND_SELECT
label_SOUND_SELECT:	PROC
	BEGIN
	;[100]     #snd_val = 373 : snd_gate = 3 : snd_post = 1 : GOSUB play_tone
	SRCFILE "sound.bas",100
	MVII #373,R0
	MVO R0,var_&SND_VAL
	MVII #3,R0
	MVO R0,var_SND_GATE
	MVII #1,R0
	MVO R0,var_SND_POST
	CALL label_PLAY_TONE
	;[101]     #snd_val = 320 : snd_gate = 3 : snd_post = 0 : GOSUB play_tone
	SRCFILE "sound.bas",101
	MVII #320,R0
	MVO R0,var_&SND_VAL
	MVII #3,R0
	MVO R0,var_SND_GATE
	CLRR R0
	MVO R0,var_SND_POST
	CALL label_PLAY_TONE
	;[102] END
	SRCFILE "sound.bas",102
	RETURN
	ENDP
	;[103] 
	SRCFILE "sound.bas",103
	;[104] ' sound_cursor: menu/move cursor moved one position (300 Hz).
	SRCFILE "sound.bas",104
	;[105] sound_cursor: PROCEDURE
	SRCFILE "sound.bas",105
	; SOUND_CURSOR
label_SOUND_CURSOR:	PROC
	BEGIN
	;[106]     #snd_val = 373 : snd_gate = 2 : snd_post = 0 : GOSUB play_tone
	SRCFILE "sound.bas",106
	MVII #373,R0
	MVO R0,var_&SND_VAL
	MVII #2,R0
	MVO R0,var_SND_GATE
	CLRR R0
	MVO R0,var_SND_POST
	CALL label_PLAY_TONE
	;[107] END
	SRCFILE "sound.bas",107
	RETURN
	ENDP
	;[108] 
	SRCFILE "sound.bas",108
	;[109] ' sound_chip: pot value increased (a bet/call/raise landed, 50 Hz). The C
	SRCFILE "sound.bas",109
	;[110] ' clients play one ascending tone per player as chips sweep into the pot
	SRCFILE "sound.bas",110
	;[111] ' during a dedicated collection animation; we don't animate that (pot just
	SRCFILE "sound.bas",111
	;[112] ' updates), so this plays their first-player tone once per pot increase
	SRCFILE "sound.bas",112
	;[113] ' as a stand-in "chip clink."
	SRCFILE "sound.bas",113
	;[114] sound_chip: PROCEDURE
	SRCFILE "sound.bas",114
	; SOUND_CHIP
label_SOUND_CHIP:	PROC
	BEGIN
	;[115]     #snd_val = 2237 : snd_gate = 2 : snd_post = 2 : GOSUB play_tone
	SRCFILE "sound.bas",115
	MVII #2237,R0
	MVO R0,var_&SND_VAL
	MVII #2,R0
	MVO R0,var_SND_GATE
	MVO R0,var_SND_POST
	CALL label_PLAY_TONE
	;[116] END
	SRCFILE "sound.bas",116
	RETURN
	ENDP
	;ENDFILE
	;FILE texas.bas
	;[40] 
	SRCFILE "texas.bas",40
	;[41]     CONST ROWCELLS = 20
	SRCFILE "texas.bas",41
	;[42]     CONST STATUS_ROW = 220
	SRCFILE "texas.bas",42
	;[43] 
	SRCFILE "texas.bas",43
	;[44]     CONST COL_NAME  = FG_WHITE + BG_DARKGREEN
	SRCFILE "texas.bas",44
	;[45]     CONST COL_HILITE = FG_YELLOW + BG_DARKGREEN
	SRCFILE "texas.bas",45
	;[46]     CONST COL_STATUS = FG_WHITE + BG_BLACK
	SRCFILE "texas.bas",46
	;[47] 
	SRCFILE "texas.bas",47
	;[48] ' Seat base offsets (name row), seat 0 is always you (bottom-center).
	SRCFILE "texas.bas",48
	;[49] seat_name_off:
	SRCFILE "texas.bas",49
	; SEAT_NAME_OFF
label_SEAT_NAME_OFF:	;[50]     DATA 167, 140, 80, 20, 7, 34, 94, 154
	SRCFILE "texas.bas",50
	DECLE 167
	DECLE 140
	DECLE 80
	DECLE 20
	DECLE 7
	DECLE 34
	DECLE 94
	DECLE 154
	;[51] 
	SRCFILE "texas.bas",51
	;[52] ' playerCountIndex: for a given playerCount (2-8, row = playerCount-2),
	SRCFILE "texas.bas",52
	;[53] ' the seat assigned to server player index i (array position i). 255 =
	SRCFILE "texas.bas",53
	;[54] ' unused. Ported unchanged from the C client's seat-assignment table.
	SRCFILE "texas.bas",54
	;[55] seatmap:
	SRCFILE "texas.bas",55
	; SEATMAP
label_SEATMAP:	;[56]     DATA 0,4,255,255,255,255,255,255       ' 2 players
	SRCFILE "texas.bas",56
	DECLE 0
	DECLE 4
	DECLE 255
	DECLE 255
	DECLE 255
	DECLE 255
	DECLE 255
	DECLE 255
	;[57]     DATA 0,2,6,255,255,255,255,255         ' 3
	SRCFILE "texas.bas",57
	DECLE 0
	DECLE 2
	DECLE 6
	DECLE 255
	DECLE 255
	DECLE 255
	DECLE 255
	DECLE 255
	;[58]     DATA 0,2,4,6,255,255,255,255           ' 4
	SRCFILE "texas.bas",58
	DECLE 0
	DECLE 2
	DECLE 4
	DECLE 6
	DECLE 255
	DECLE 255
	DECLE 255
	DECLE 255
	;[59]     DATA 0,2,3,5,6,255,255,255             ' 5
	SRCFILE "texas.bas",59
	DECLE 0
	DECLE 2
	DECLE 3
	DECLE 5
	DECLE 6
	DECLE 255
	DECLE 255
	DECLE 255
	;[60]     DATA 0,2,3,4,5,6,255,255               ' 6
	SRCFILE "texas.bas",60
	DECLE 0
	DECLE 2
	DECLE 3
	DECLE 4
	DECLE 5
	DECLE 6
	DECLE 255
	DECLE 255
	;[61]     DATA 0,2,3,4,5,6,7,255                 ' 7
	SRCFILE "texas.bas",61
	DECLE 0
	DECLE 2
	DECLE 3
	DECLE 4
	DECLE 5
	DECLE 6
	DECLE 7
	DECLE 255
	;[62]     DATA 0,1,2,3,4,5,6,7                   ' 8
	SRCFILE "texas.bas",62
	DECLE 0
	DECLE 1
	DECLE 2
	DECLE 3
	DECLE 4
	DECLE 5
	DECLE 6
	DECLE 7
	;[63] 
	SRCFILE "texas.bas",63
	;[64] lit_n_colon: DATA 78,58
	SRCFILE "texas.bas",64
	; LIT_N_COLON
label_LIT_N_COLON:		DECLE 78
	DECLE 58
	;[65] ' "https://th.carr-designs.com/" -- the public Texas Hold'em server
	SRCFILE "texas.bas",65
	;[66] ' (src/main.c's serverEndpoint default).
	SRCFILE "texas.bas",66
	;[67] lit_https: DATA 104,116,116,112,115,58,47,47,116,104,46,99,97,114,114,45,100,101,115,105,103,110,115,46,99,111,109,47
	SRCFILE "texas.bas",67
	; LIT_HTTPS
label_LIT_HTTPS:		DECLE 104
	DECLE 116
	DECLE 116
	DECLE 112
	DECLE 115
	DECLE 58
	DECLE 47
	DECLE 47
	DECLE 116
	DECLE 104
	DECLE 46
	DECLE 99
	DECLE 97
	DECLE 114
	DECLE 114
	DECLE 45
	DECLE 100
	DECLE 101
	DECLE 115
	DECLE 105
	DECLE 103
	DECLE 110
	DECLE 115
	DECLE 46
	DECLE 99
	DECLE 111
	DECLE 109
	DECLE 47
	;[68] lit_tables: DATA 116,97,98,108,101,115
	SRCFILE "texas.bas",68
	; LIT_TABLES
label_LIT_TABLES:		DECLE 116
	DECLE 97
	DECLE 98
	DECLE 108
	DECLE 101
	DECLE 115
	;[69] lit_state: DATA 115,116,97,116,101
	SRCFILE "texas.bas",69
	; LIT_STATE
label_LIT_STATE:		DECLE 115
	DECLE 116
	DECLE 97
	DECLE 116
	DECLE 101
	;[70] lit_move: DATA 109,111,118,101,47
	SRCFILE "texas.bas",70
	; LIT_MOVE
label_LIT_MOVE:		DECLE 109
	DECLE 111
	DECLE 118
	DECLE 101
	DECLE 47
	;[71] lit_leave: DATA 108,101,97,118,101
	SRCFILE "texas.bas",71
	; LIT_LEAVE
label_LIT_LEAVE:		DECLE 108
	DECLE 101
	DECLE 97
	DECLE 118
	DECLE 101
	;[72] ' "&be=1" (big-endian) dropped: the Go server's binary.BigEndian path is
	SRCFILE "texas.bas",72
	;[73] ' the road much less travelled (CoCo, 6809, is the only other client that
	SRCFILE "texas.bas",73
	;[74] ' ever requests it -- everything else in this client family is little-
	SRCFILE "texas.bas",74
	;[75] ' endian x86/6502/Z80), and pot/bet corruption that always landed on
	SRCFILE "texas.bas",75
	;[76] ' exact multiples of 256 (i.e. a real small value sitting in the high
	SRCFILE "texas.bas",76
	;[77] ' byte, low byte zero) pointed straight at a byte-order mismatch on that
	SRCFILE "texas.bas",77
	;[78] ' path specifically. Little-endian is what the rest of the ecosystem
	SRCFILE "texas.bas",78
	;[79] ' exercises constantly.
	SRCFILE "texas.bas",79
	;[80] lit_qbin: DATA 63,98,105,110,61,49
	SRCFILE "texas.bas",80
	; LIT_QBIN
label_LIT_QBIN:		DECLE 63
	DECLE 98
	DECLE 105
	DECLE 110
	DECLE 61
	DECLE 49
	;[81] lit_abin: DATA 38,98,105,110,61,49
	SRCFILE "texas.bas",81
	; LIT_ABIN
label_LIT_ABIN:		DECLE 38
	DECLE 98
	DECLE 105
	DECLE 110
	DECLE 61
	DECLE 49
	;[82] lit_qtable: DATA 63,116,97,98,108,101,61
	SRCFILE "texas.bas",82
	; LIT_QTABLE
label_LIT_QTABLE:		DECLE 63
	DECLE 116
	DECLE 97
	DECLE 98
	DECLE 108
	DECLE 101
	DECLE 61
	;[83] lit_aplayer: DATA 38,112,108,97,121,101,114,61
	SRCFILE "texas.bas",83
	; LIT_APLAYER
label_LIT_APLAYER:		DECLE 38
	DECLE 112
	DECLE 108
	DECLE 97
	DECLE 121
	DECLE 101
	DECLE 114
	DECLE 61
	;[84] 
	SRCFILE "texas.bas",84
	;[85] ' Street labels, 8 space-padded ASCII bytes per round value (round*8
	SRCFILE "texas.bas",85
	;[86] ' indexes straight into this), drawn via draw_field like every other
	SRCFILE "texas.bas",86
	;[87] ' text field. Row 0 (round=0, waiting) is deliberately blank so the
	SRCFILE "texas.bas",87
	;[88] ' label cell range self-clears between hands without special-casing.
	SRCFILE "texas.bas",88
	;[89] street_names:
	SRCFILE "texas.bas",89
	; STREET_NAMES
label_STREET_NAMES:	;[90]     DATA 32,32,32,32,32,32,32,32           ' 0 waiting
	SRCFILE "texas.bas",90
	DECLE 32
	DECLE 32
	DECLE 32
	DECLE 32
	DECLE 32
	DECLE 32
	DECLE 32
	DECLE 32
	;[91]     DATA 80,82,69,45,70,76,79,80           ' 1 PRE-FLOP
	SRCFILE "texas.bas",91
	DECLE 80
	DECLE 82
	DECLE 69
	DECLE 45
	DECLE 70
	DECLE 76
	DECLE 79
	DECLE 80
	;[92]     DATA 70,76,79,80,32,32,32,32           ' 2 FLOP
	SRCFILE "texas.bas",92
	DECLE 70
	DECLE 76
	DECLE 79
	DECLE 80
	DECLE 32
	DECLE 32
	DECLE 32
	DECLE 32
	;[93]     DATA 84,85,82,78,32,32,32,32           ' 3 TURN
	SRCFILE "texas.bas",93
	DECLE 84
	DECLE 85
	DECLE 82
	DECLE 78
	DECLE 32
	DECLE 32
	DECLE 32
	DECLE 32
	;[94]     DATA 82,73,86,69,82,32,32,32           ' 4 RIVER
	SRCFILE "texas.bas",94
	DECLE 82
	DECLE 73
	DECLE 86
	DECLE 69
	DECLE 82
	DECLE 32
	DECLE 32
	DECLE 32
	;[95]     DATA 83,72,79,87,68,79,87,78           ' 5 SHOWDOWN
	SRCFILE "texas.bas",95
	DECLE 83
	DECLE 72
	DECLE 79
	DECLE 87
	DECLE 68
	DECLE 79
	DECLE 87
	DECLE 78
	;[96] 
	SRCFILE "texas.bas",96
	;[97]     CONST LEN_HTTPS = 28
	SRCFILE "texas.bas",97
	;[98] 
	SRCFILE "texas.bas",98
	;[99]     ' Lobby appkey: creator 1 / app 1, key = this game's registered slot.
	SRCFILE "texas.bas",99
	;[100]     ' Texas Hold'em is lobby appkey 8 (see fujinet-texasHoldEm/src/misc.h
	SRCFILE "texas.bas",100
	;[101]     ' AK_LOBBY_KEY_SERVER -- 5 Card Stud's was 1; using 8 here means table
	SRCFILE "texas.bas",101
	;[102]     ' selection can't overwrite the 5CS lobby hand-off URL). The name key
	SRCFILE "texas.bas",102
	;[103]     ' (creator 1 / app 1 / key 0) is the lobby-shared username, unchanged.
	SRCFILE "texas.bas",103
	;[104]     ' The C clients' prefs appkey (creator $BEBE / app 1) only stores
	SRCFILE "texas.bas",104
	;[105]     ' help-seen/color-mode flags for screens this client doesn't have, so
	SRCFILE "texas.bas",105
	;[106]     ' it's deliberately unused here.
	SRCFILE "texas.bas",106
	;[107]     CONST AK_LOBBY_KEY_SERVER = 8
	SRCFILE "texas.bas",107
	;[108] 
	SRCFILE "texas.bas",108
	;[109]     ' Selected table id, 9 bytes (8 + NUL). SC_ENDPT used to double as this
	SRCFILE "texas.bas",109
	;[110]     ' buffer, but it's now needed for the full lobby-supplied endpoint, so
	SRCFILE "texas.bas",110
	;[111]     ' the table id gets its own slot -- free RAM just past fujinet.bas's
	SRCFILE "texas.bas",111
	;[112]     ' own SC_* buffers (which stop at SC_QUERY $9150 + 48 = $9180) and
	SRCFILE "texas.bas",112
	;[113]     ' well below the $9C00 mailbox.
	SRCFILE "texas.bas",113
	;[114]     CONST SC_TABLE = $9180
	SRCFILE "texas.bas",114
	;[115] 
	SRCFILE "texas.bas",115
	;[116] ' ---------------------------------------------------------------------------
	SRCFILE "texas.bas",116
	;[117] ' Globals
	SRCFILE "texas.bas",117
	;[118] ' ---------------------------------------------------------------------------
	SRCFILE "texas.bas",118
	;[119]     DIM gs_i, gs_j, #gs_c
	SRCFILE "texas.bas",119
	;[120]     DIM ne_cur, ne_len
	SRCFILE "texas.bas",120
	;[121]     DIM ne_buf(8)
	SRCFILE "texas.bas",121
	;[122]     DIM tbl_count, tbl_sel
	SRCFILE "texas.bas",122
	;[123]     DIM sel_seat, sel_i
	SRCFILE "texas.bas",123
	;[124]     DIM poll_wait
	SRCFILE "texas.bas",124
	;[125]     DIM mv_sel, mv_count
	SRCFILE "texas.bas",125
	;[126]     DIM mv_col(5)
	SRCFILE "texas.bas",126
	;[127]     DIM mvcode_a, mvcode_b
	SRCFILE "texas.bas",127
	;[128]     DIM has_move
	SRCFILE "texas.bas",128
	;[129]     DIM #tmp_addr
	SRCFILE "texas.bas",129
	;[130]     DIM #tmp_num
	SRCFILE "texas.bas",130
	;[131]     DIM #prev_pot
	SRCFILE "texas.bas",131
	;[132]     DIM #prev_purse
	SRCFILE "texas.bas",132
	;[133]     DIM prev_bet(8)
	SRCFILE "texas.bas",133
	;[134]     DIM prev_cards(8)
	SRCFILE "texas.bas",134
	;[135]     DIM prev_community
	SRCFILE "texas.bas",135
	;[136]     DIM street_redraw
	SRCFILE "texas.bas",136
	;[137]     DIM deal_count
	SRCFILE "texas.bas",137
	;[138]     DIM #tmp_expect
	SRCFILE "texas.bas",138
	;[139]     DIM #tmp_hash
	SRCFILE "texas.bas",139
	;[140]     DIM #prev_result_hash
	SRCFILE "texas.bas",140
	;[141]     DIM first_poll
	SRCFILE "texas.bas",141
	;[142]     DIM prev_active, turn_changed
	SRCFILE "texas.bas",142
	;[143] 
	SRCFILE "texas.bas",143
	;[144]     DIM df_pos, df_len, #df_color, df_i, df_c, df_stop
	SRCFILE "texas.bas",144
	;[145]     DIM #df_src
	SRCFILE "texas.bas",145
	;[146] 
	SRCFILE "texas.bas",146
	;[147]     ' split_room_url locals (see procedure below)
	SRCFILE "texas.bas",147
	;[148]     DIM sp_i, sp_found, sp_ok, sp_j, sp_k, sp_c, sp_valid, sp_m
	SRCFILE "texas.bas",148
	;[149] 
	SRCFILE "texas.bas",149
	;[150] ' ---------------------------------------------------------------------------
	SRCFILE "texas.bas",150
	;[151] ' draw_field: render df_len ASCII bytes from #df_src onto the screen at
	SRCFILE "texas.bas",151
	;[152] ' BACKTAB offset df_pos, in color #df_color. Uppercases (MODE 1 has no
	SRCFILE "texas.bas",152
	;[153] ' lowercase GROM; the wire is lowercase anyway), stops at a NUL and pads
	SRCFILE "texas.bas",153
	;[154] ' the rest of the field with spaces, and clamps anything outside the
	SRCFILE "texas.bas",154
	;[155] ' printable GROM range (32-95) to a space rather than drawing garbage.
	SRCFILE "texas.bas",155
	;[156] ' ---------------------------------------------------------------------------
	SRCFILE "texas.bas",156
	;[157] ' ---------------------------------------------------------------------------
	SRCFILE "texas.bas",157
	;[158] ' fill_bg: felt-table background -- green everywhere except the status row
	SRCFILE "texas.bas",158
	;[159] ' (which stays black). Call right after every CLS.
	SRCFILE "texas.bas",159
	;[160] ' ---------------------------------------------------------------------------
	SRCFILE "texas.bas",160
	;[161] fill_bg: PROCEDURE
	SRCFILE "texas.bas",161
	; FILL_BG
label_FILL_BG:	PROC
	BEGIN
	;[162]     FOR gs_i = 0 TO STATUS_ROW - 1
	SRCFILE "texas.bas",162
	CLRR R0
	MVO R0,var_GS_I
T57:
	;[163]         #BACKTAB(gs_i) = COL_NAME
	SRCFILE "texas.bas",163
	MVII #8199,R0
	MVII #Q2,R3
	ADD var_GS_I,R3
	MVO@ R0,R3
	;[164]     NEXT gs_i
	SRCFILE "texas.bas",164
	MVI var_GS_I,R0
	INCR R0
	MVO R0,var_GS_I
	CMPI #219,R0
	BLE T57
	;[165] END
	SRCFILE "texas.bas",165
	RETURN
	ENDP
	;[166] 
	SRCFILE "texas.bas",166
	;[167] draw_field: PROCEDURE
	SRCFILE "texas.bas",167
	; DRAW_FIELD
label_DRAW_FIELD:	PROC
	BEGIN
	;[168]     df_stop = 0
	SRCFILE "texas.bas",168
	CLRR R0
	MVO R0,var_DF_STOP
	;[169]     FOR df_i = 0 TO df_len - 1
	SRCFILE "texas.bas",169
	MVO R0,var_DF_I
T58:
	;[170]         df_c = PEEK(#df_src + df_i) AND 255
	SRCFILE "texas.bas",170
	MVI var_&DF_SRC,R1
	ADD var_DF_I,R1
	MVI@ R1,R0
	MVO R0,var_DF_C
	;[171]         IF df_c = 0 THEN df_stop = 1
	SRCFILE "texas.bas",171
	MVI var_DF_C,R0
	TSTR R0
	BNE T59
	MVII #1,R0
	MVO R0,var_DF_STOP
T59:
	;[172]         IF df_stop THEN
	SRCFILE "texas.bas",172
	MVI var_DF_STOP,R0
	TSTR R0
	BEQ T60
	;[173]             df_c = 32
	SRCFILE "texas.bas",173
	MVII #32,R0
	MVO R0,var_DF_C
	;[174]         ELSEIF df_c >= 97 AND df_c <= 122 THEN
	SRCFILE "texas.bas",174
	B T61
T60:
	MVI var_DF_C,R0
	CMPI #97,R0
	MVII #65535,R0
	BGE T63
	INCR R0
T63:
	MVI var_DF_C,R1
	CMPI #122,R1
	MVII #65535,R1
	BLE T64
	INCR R1
T64:
	ANDR R1,R0
	BEQ T62
	;[175]             df_c = df_c - 32
	SRCFILE "texas.bas",175
	MVI var_DF_C,R0
	SUBI #32,R0
	MVO R0,var_DF_C
	;[176]         END IF
	SRCFILE "texas.bas",176
T61:
T62:
	;[177]         IF df_c < 32 OR df_c > 95 THEN df_c = 32
	SRCFILE "texas.bas",177
	MVI var_DF_C,R0
	CMPI #32,R0
	MVII #65535,R0
	BLT T66
	INCR R0
T66:
	MVI var_DF_C,R1
	CMPI #95,R1
	MVII #65535,R1
	BGT T67
	INCR R1
T67:
	COMR R1
	ANDR R1,R0
	COMR R1
	XORR R1,R0
	BEQ T65
	MVII #32,R0
	MVO R0,var_DF_C
T65:
	;[178]         #BACKTAB(df_pos + df_i) = (df_c - 32) * 8 + #df_color
	SRCFILE "texas.bas",178
	MVII #Q2,R0
	MVI var_DF_POS,R1
	ADD var_DF_I,R1
	ADDR R1,R0
	MVI var_DF_C,R1
	SUBI #32,R1
	SLL R1,2
	ADDR R1,R1
	ADD var_&DF_COLOR,R1
	MOVR R0,R4
	MVO@ R1,R4
	;[179]     NEXT df_i
	SRCFILE "texas.bas",179
	MVI var_DF_I,R0
	INCR R0
	MVO R0,var_DF_I
	MVI var_DF_LEN,R1
	DECR R1
	CMPR R1,R0
	BLE T58
	;[180] END
	SRCFILE "texas.bas",180
	RETURN
	ENDP
	;[181] 
	SRCFILE "texas.bas",181
	;[182] ' ---------------------------------------------------------------------------
	SRCFILE "texas.bas",182
	;[183] ' compose_url: build "N:<endpoint><path...><suffix>" directly into FN_TX.
	SRCFILE "texas.bas",183
	;[184] ' Callers set gs_path (0=tables 1=state 2=move 3=leave) and, for move,
	SRCFILE "texas.bas",184
	;[185] ' mvcode_a/mvcode_b (the 2-char move code) beforehand.
	SRCFILE "texas.bas",185
	;[186] ' ---------------------------------------------------------------------------
	SRCFILE "texas.bas",186
	;[187]     DIM gs_path
	SRCFILE "texas.bas",187
	;[188] compose_url: PROCEDURE
	SRCFILE "texas.bas",188
	; COMPOSE_URL
label_COMPOSE_URL:	PROC
	BEGIN
	;[189]     #fn_txlen = 0
	SRCFILE "texas.bas",189
	CLRR R0
	MVO R0,var_&FN_TXLEN
	;[190]     #fn_src = VARPTR lit_n_colon(0) : fn_len = 2 : GOSUB fn_putstr
	SRCFILE "texas.bas",190
	MVII #label_LIT_N_COLON,R0
	MVO R0,var_&FN_SRC
	MVII #2,R0
	MVO R0,var_FN_LEN
	CALL label_FN_PUTSTR
	;[191]     #fn_src = SC_ENDPT : ls_max = 65 : GOSUB fn_strlen : GOSUB fn_putstr
	SRCFILE "texas.bas",191
	MVII #37136,R0
	MVO R0,var_&FN_SRC
	MVII #65,R0
	MVO R0,var_LS_MAX
	CALL label_FN_STRLEN
	CALL label_FN_PUTSTR
	;[192] 
	SRCFILE "texas.bas",192
	;[193]     IF gs_path = 0 THEN
	SRCFILE "texas.bas",193
	MVI var_GS_PATH,R0
	TSTR R0
	BNE T68
	;[194]         #fn_src = VARPTR lit_tables(0) : fn_len = 6 : GOSUB fn_putstr
	SRCFILE "texas.bas",194
	MVII #label_LIT_TABLES,R0
	MVO R0,var_&FN_SRC
	MVII #6,R0
	MVO R0,var_FN_LEN
	CALL label_FN_PUTSTR
	;[195]         #fn_src = VARPTR lit_qbin(0) : fn_len = 6 : GOSUB fn_putstr
	SRCFILE "texas.bas",195
	MVII #label_LIT_QBIN,R0
	MVO R0,var_&FN_SRC
	MVII #6,R0
	MVO R0,var_FN_LEN
	CALL label_FN_PUTSTR
	;[196]     ELSE
	SRCFILE "texas.bas",196
	B T69
T68:
	;[197]         IF gs_path = 1 THEN
	SRCFILE "texas.bas",197
	MVI var_GS_PATH,R0
	CMPI #1,R0
	BNE T70
	;[198]             #fn_src = VARPTR lit_state(0) : fn_len = 5 : GOSUB fn_putstr
	SRCFILE "texas.bas",198
	MVII #label_LIT_STATE,R0
	MVO R0,var_&FN_SRC
	MVII #5,R0
	MVO R0,var_FN_LEN
	CALL label_FN_PUTSTR
	;[199]         ELSEIF gs_path = 2 THEN
	SRCFILE "texas.bas",199
	B T71
T70:
	MVI var_GS_PATH,R0
	CMPI #2,R0
	BNE T72
	;[200]             #fn_src = VARPTR lit_move(0) : fn_len = 5 : GOSUB fn_putstr
	SRCFILE "texas.bas",200
	MVII #label_LIT_MOVE,R0
	MVO R0,var_&FN_SRC
	MVII #5,R0
	MVO R0,var_FN_LEN
	CALL label_FN_PUTSTR
	;[201]             POKE (FN_TX + #fn_txlen), mvcode_a : #fn_txlen = #fn_txlen + 1
	SRCFILE "texas.bas",201
	MVI var_MVCODE_A,R0
	MVI var_&FN_TXLEN,R1
	ADDI #40000,R1
	MVO@ R0,R1
	MVI var_&FN_TXLEN,R0
	INCR R0
	MVO R0,var_&FN_TXLEN
	;[202]             POKE (FN_TX + #fn_txlen), mvcode_b : #fn_txlen = #fn_txlen + 1
	SRCFILE "texas.bas",202
	MVI var_MVCODE_B,R0
	MVI var_&FN_TXLEN,R1
	ADDI #40000,R1
	MVO@ R0,R1
	MVI var_&FN_TXLEN,R0
	INCR R0
	MVO R0,var_&FN_TXLEN
	;[203]         ELSE
	SRCFILE "texas.bas",203
	B T71
T72:
	;[204]             #fn_src = VARPTR lit_leave(0) : fn_len = 5 : GOSUB fn_putstr
	SRCFILE "texas.bas",204
	MVII #label_LIT_LEAVE,R0
	MVO R0,var_&FN_SRC
	MVII #5,R0
	MVO R0,var_FN_LEN
	CALL label_FN_PUTSTR
	;[205]         END IF
	SRCFILE "texas.bas",205
T71:
	;[206] 
	SRCFILE "texas.bas",206
	;[207]         #fn_src = VARPTR lit_qtable(0) : fn_len = 7 : GOSUB fn_putstr
	SRCFILE "texas.bas",207
	MVII #label_LIT_QTABLE,R0
	MVO R0,var_&FN_SRC
	MVII #7,R0
	MVO R0,var_FN_LEN
	CALL label_FN_PUTSTR
	;[208]         #fn_src = SC_TABLE : ls_max = 9 : GOSUB fn_strlen : GOSUB fn_putstr   ' table id, NUL-terminated within its 9-byte field
	SRCFILE "texas.bas",208
	MVII #37248,R0
	MVO R0,var_&FN_SRC
	MVII #9,R0
	MVO R0,var_LS_MAX
	CALL label_FN_STRLEN
	CALL label_FN_PUTSTR
	;[209]         #fn_src = VARPTR lit_aplayer(0) : fn_len = 8 : GOSUB fn_putstr
	SRCFILE "texas.bas",209
	MVII #label_LIT_APLAYER,R0
	MVO R0,var_&FN_SRC
	MVII #8,R0
	MVO R0,var_FN_LEN
	CALL label_FN_PUTSTR
	;[210]         #fn_src = SC_NAME : ls_max = 9 : GOSUB fn_strlen : GOSUB fn_putstr    ' player name, likewise
	SRCFILE "texas.bas",210
	MVII #37120,R0
	MVO R0,var_&FN_SRC
	MVII #9,R0
	MVO R0,var_LS_MAX
	CALL label_FN_STRLEN
	CALL label_FN_PUTSTR
	;[211]         #fn_src = VARPTR lit_abin(0) : fn_len = 6 : GOSUB fn_putstr
	SRCFILE "texas.bas",211
	MVII #label_LIT_ABIN,R0
	MVO R0,var_&FN_SRC
	MVII #6,R0
	MVO R0,var_FN_LEN
	CALL label_FN_PUTSTR
	;[212]     END IF
	SRCFILE "texas.bas",212
T69:
	;[213] END
	SRCFILE "texas.bas",213
	RETURN
	ENDP
	;[214] 
	SRCFILE "texas.bas",214
	;[215] ' ---------------------------------------------------------------------------
	SRCFILE "texas.bas",215
	;[216] ' split_room_url: given a lobby-supplied "https://host/?table=xyz" value
	SRCFILE "texas.bas",216
	;[217] ' already sitting in SC_ENDPT with its length in fn_len (as left by
	SRCFILE "texas.bas",217
	;[218] ' appkey_read), split it into the bare endpoint (SC_ENDPT, truncated at
	SRCFILE "texas.bas",218
	;[219] ' the '?') and the table id (SC_TABLE). Mirrors the C clients'
	SRCFILE "texas.bas",219
	;[220] ' welcomeActionVerifyServerDetails() '?' scan. Leaves SC_TABLE empty (a
	SRCFILE "texas.bas",220
	;[221] ' leading NUL) if there's no '?', the query isn't "table=...", or the id
	SRCFILE "texas.bas",221
	;[222] ' contains anything other than A-Z/a-z/0-9 -- it goes straight into a
	SRCFILE "texas.bas",222
	;[223] ' rebuilt query string unescaped, same reasoning as the username check
	SRCFILE "texas.bas",223
	;[224] ' above.
	SRCFILE "texas.bas",224
	;[225] ' ---------------------------------------------------------------------------
	SRCFILE "texas.bas",225
	;[226] split_room_url: PROCEDURE
	SRCFILE "texas.bas",226
	; SPLIT_ROOM_URL
label_SPLIT_ROOM_URL:	PROC
	BEGIN
	;[227]     POKE SC_TABLE, 0
	SRCFILE "texas.bas",227
	CLRR R0
	MVO R0,37248
	;[228] 
	SRCFILE "texas.bas",228
	;[229]     sp_found = 255 ' sentinel: not found (mirrors st_boot.bas's bt_slash convention)
	SRCFILE "texas.bas",229
	MVII #255,R0
	MVO R0,var_SP_FOUND
	;[230]     sp_i = 0
	SRCFILE "texas.bas",230
	CLRR R0
	MVO R0,var_SP_I
	;[231]     WHILE sp_i < fn_len
	SRCFILE "texas.bas",231
T73:
	MVI var_SP_I,R0
	CMP var_FN_LEN,R0
	BGE T74
	;[232]         IF (PEEK(SC_ENDPT + sp_i) AND 255) = 63 THEN ' '?'
	SRCFILE "texas.bas",232
	MOVR R0,R1
	ADDI #37136,R1
	MVI@ R1,R0
	ANDI #255,R0
	CMPI #63,R0
	BNE T75
	;[233]             sp_found = sp_i
	SRCFILE "texas.bas",233
	MVI var_SP_I,R0
	MVO R0,var_SP_FOUND
	;[234]             EXIT WHILE
	SRCFILE "texas.bas",234
	B T74
	;[235]         END IF
	SRCFILE "texas.bas",235
T75:
	;[236]         sp_i = sp_i + 1
	SRCFILE "texas.bas",236
	MVI var_SP_I,R0
	INCR R0
	MVO R0,var_SP_I
	;[237]     WEND
	SRCFILE "texas.bas",237
	B T73
T74:
	;[238]     IF sp_found = 255 THEN RETURN
	SRCFILE "texas.bas",238
	MVI var_SP_FOUND,R0
	CMPI #255,R0
	BNE T76
	RETURN
T76:
	;[239] 
	SRCFILE "texas.bas",239
	;[240]     ' Truncate the endpoint at the '?' regardless of what follows.
	SRCFILE "texas.bas",240
	;[241]     POKE (SC_ENDPT + sp_found), 0
	SRCFILE "texas.bas",241
	CLRR R0
	MVI var_SP_FOUND,R1
	ADDI #37136,R1
	MVO@ R0,R1
	;[242] 
	SRCFILE "texas.bas",242
	;[243]     ' Require "table=" (6 bytes) right after the '?'.
	SRCFILE "texas.bas",243
	;[244]     sp_ok = 0
	SRCFILE "texas.bas",244
	MVO R0,var_SP_OK
	;[245]     IF sp_found + 7 <= fn_len THEN
	SRCFILE "texas.bas",245
	MVI var_SP_FOUND,R0
	ADDI #7,R0
	CMP var_FN_LEN,R0
	BGT T77
	;[246]         sp_ok = 1
	SRCFILE "texas.bas",246
	MVII #1,R0
	MVO R0,var_SP_OK
	;[247]         IF (PEEK(SC_ENDPT + sp_found + 1) AND 255) <> 116 THEN sp_ok = 0 ' t
	SRCFILE "texas.bas",247
	MVI var_SP_FOUND,R1
	ADDI #37137,R1
	MVI@ R1,R0
	ANDI #255,R0
	CMPI #116,R0
	BEQ T78
	CLRR R0
	MVO R0,var_SP_OK
T78:
	;[248]         IF (PEEK(SC_ENDPT + sp_found + 2) AND 255) <> 97  THEN sp_ok = 0 ' a
	SRCFILE "texas.bas",248
	MVI var_SP_FOUND,R1
	ADDI #37138,R1
	MVI@ R1,R0
	ANDI #255,R0
	CMPI #97,R0
	BEQ T79
	CLRR R0
	MVO R0,var_SP_OK
T79:
	;[249]         IF (PEEK(SC_ENDPT + sp_found + 3) AND 255) <> 98  THEN sp_ok = 0 ' b
	SRCFILE "texas.bas",249
	MVI var_SP_FOUND,R1
	ADDI #37139,R1
	MVI@ R1,R0
	ANDI #255,R0
	CMPI #98,R0
	BEQ T80
	CLRR R0
	MVO R0,var_SP_OK
T80:
	;[250]         IF (PEEK(SC_ENDPT + sp_found + 4) AND 255) <> 108 THEN sp_ok = 0 ' l
	SRCFILE "texas.bas",250
	MVI var_SP_FOUND,R1
	ADDI #37140,R1
	MVI@ R1,R0
	ANDI #255,R0
	CMPI #108,R0
	BEQ T81
	CLRR R0
	MVO R0,var_SP_OK
T81:
	;[251]         IF (PEEK(SC_ENDPT + sp_found + 5) AND 255) <> 101 THEN sp_ok = 0 ' e
	SRCFILE "texas.bas",251
	MVI var_SP_FOUND,R1
	ADDI #37141,R1
	MVI@ R1,R0
	ANDI #255,R0
	CMPI #101,R0
	BEQ T82
	CLRR R0
	MVO R0,var_SP_OK
T82:
	;[252]         IF (PEEK(SC_ENDPT + sp_found + 6) AND 255) <> 61  THEN sp_ok = 0 ' =
	SRCFILE "texas.bas",252
	MVI var_SP_FOUND,R1
	ADDI #37142,R1
	MVI@ R1,R0
	ANDI #255,R0
	CMPI #61,R0
	BEQ T83
	CLRR R0
	MVO R0,var_SP_OK
T83:
	;[253]     END IF
	SRCFILE "texas.bas",253
T77:
	;[254]     IF sp_ok = 0 THEN RETURN
	SRCFILE "texas.bas",254
	MVI var_SP_OK,R0
	TSTR R0
	BNE T84
	RETURN
T84:
	;[255] 
	SRCFILE "texas.bas",255
	;[256]     ' Copy the id: up to 8 bytes, stopping at NUL or '&'.
	SRCFILE "texas.bas",256
	;[257]     sp_j = sp_found + 7
	SRCFILE "texas.bas",257
	MVI var_SP_FOUND,R0
	ADDI #7,R0
	MVO R0,var_SP_J
	;[258]     sp_k = 0
	SRCFILE "texas.bas",258
	CLRR R0
	MVO R0,var_SP_K
	;[259]     WHILE sp_k < 8 AND sp_j < fn_len
	SRCFILE "texas.bas",259
T85:
	MVI var_SP_K,R0
	CMPI #8,R0
	MVII #65535,R0
	BLT T87
	INCR R0
T87:
	MVI var_SP_J,R1
	CMP var_FN_LEN,R1
	MVII #65535,R1
	BLT T88
	INCR R1
T88:
	ANDR R1,R0
	BEQ T86
	;[260]         sp_c = PEEK(SC_ENDPT + sp_j) AND 255
	SRCFILE "texas.bas",260
	MVI var_SP_J,R1
	ADDI #37136,R1
	MVI@ R1,R0
	MVO R0,var_SP_C
	;[261]         IF sp_c = 0 OR sp_c = 38 THEN EXIT WHILE ' NUL or '&'
	SRCFILE "texas.bas",261
	MVI var_SP_C,R0
	TSTR R0
	MVII #65535,R0
	BEQ T90
	INCR R0
T90:
	MVI var_SP_C,R1
	CMPI #38,R1
	MVII #65535,R1
	BEQ T91
	INCR R1
T91:
	COMR R1
	ANDR R1,R0
	COMR R1
	XORR R1,R0
	BNE T86
	;[262]         POKE (SC_TABLE + sp_k), sp_c
	SRCFILE "texas.bas",262
	MVI var_SP_C,R0
	MVI var_SP_K,R1
	ADDI #37248,R1
	MVO@ R0,R1
	;[263]         sp_k = sp_k + 1
	SRCFILE "texas.bas",263
	MVI var_SP_K,R0
	INCR R0
	MVO R0,var_SP_K
	;[264]         sp_j = sp_j + 1
	SRCFILE "texas.bas",264
	MVI var_SP_J,R0
	INCR R0
	MVO R0,var_SP_J
	;[265]     WEND
	SRCFILE "texas.bas",265
	B T85
T86:
	;[266]     POKE (SC_TABLE + sp_k), 0
	SRCFILE "texas.bas",266
	CLRR R0
	MVI var_SP_K,R1
	ADDI #37248,R1
	MVO@ R0,R1
	;[267] 
	SRCFILE "texas.bas",267
	;[268]     ' Validate: A-Z/a-z/0-9 only.
	SRCFILE "texas.bas",268
	;[269]     sp_valid = 1
	SRCFILE "texas.bas",269
	MVII #1,R0
	MVO R0,var_SP_VALID
	;[270]     FOR sp_m = 0 TO sp_k - 1
	SRCFILE "texas.bas",270
	CLRR R0
	MVO R0,var_SP_M
T92:
	;[271]         sp_c = PEEK(SC_TABLE + sp_m) AND 255
	SRCFILE "texas.bas",271
	MVI var_SP_M,R1
	ADDI #37248,R1
	MVI@ R1,R0
	MVO R0,var_SP_C
	;[272]         IF (sp_c < 65 OR sp_c > 90) AND (sp_c < 97 OR sp_c > 122) AND (sp_c < 48 OR sp_c > 57) THEN sp_valid = 0
	SRCFILE "texas.bas",272
	MVI var_SP_C,R0
	CMPI #65,R0
	MVII #65535,R0
	BLT T94
	INCR R0
T94:
	MVI var_SP_C,R1
	CMPI #90,R1
	MVII #65535,R1
	BGT T95
	INCR R1
T95:
	COMR R1
	ANDR R1,R0
	COMR R1
	XORR R1,R0
	MVI var_SP_C,R1
	CMPI #97,R1
	MVII #65535,R1
	BLT T96
	INCR R1
T96:
	MVI var_SP_C,R2
	CMPI #122,R2
	MVII #65535,R2
	BGT T97
	INCR R2
T97:
	COMR R2
	ANDR R2,R1
	COMR R2
	XORR R2,R1
	ANDR R1,R0
	MVI var_SP_C,R1
	CMPI #48,R1
	MVII #65535,R1
	BLT T98
	INCR R1
T98:
	MVI var_SP_C,R2
	CMPI #57,R2
	MVII #65535,R2
	BGT T99
	INCR R2
T99:
	COMR R2
	ANDR R2,R1
	COMR R2
	XORR R2,R1
	ANDR R1,R0
	BEQ T93
	CLRR R0
	MVO R0,var_SP_VALID
T93:
	;[273]     NEXT sp_m
	SRCFILE "texas.bas",273
	MVI var_SP_M,R0
	INCR R0
	MVO R0,var_SP_M
	MVI var_SP_K,R1
	DECR R1
	CMPR R1,R0
	BLE T92
	;[274]     IF sp_valid = 0 THEN POKE SC_TABLE, 0
	SRCFILE "texas.bas",274
	MVI var_SP_VALID,R0
	TSTR R0
	BNE T100
	MVO R0,37248
T100:
	;[275] END
	SRCFILE "texas.bas",275
	RETURN
	ENDP
	;[276] 
	SRCFILE "texas.bas",276
	;[277] ' ---------------------------------------------------------------------------
	SRCFILE "texas.bas",277
	;[278] ' write_room_appkey: persist SC_ENDPT + "?table=" + SC_TABLE back to the
	SRCFILE "texas.bas",278
	;[279] ' lobby server appkey slot, so a reboot without going back through the
	SRCFILE "texas.bas",279
	;[280] ' lobby rejoins the same room (mirrors the C clients' "Update server app
	SRCFILE "texas.bas",280
	;[281] ' key in case of reboot"). Builds the payload directly in FN_TX and writes
	SRCFILE "texas.bas",281
	;[282] ' it from there -- appkey_write's byte-by-byte copy from #fn_src into
	SRCFILE "texas.bas",282
	;[283] ' FN_TX is a safe no-op when #fn_src is FN_TX itself.
	SRCFILE "texas.bas",283
	;[284] ' ---------------------------------------------------------------------------
	SRCFILE "texas.bas",284
	;[285] write_room_appkey: PROCEDURE
	SRCFILE "texas.bas",285
	; WRITE_ROOM_APPKEY
label_WRITE_ROOM_APPKEY:	PROC
	BEGIN
	;[286]     #fn_txlen = 0
	SRCFILE "texas.bas",286
	CLRR R0
	MVO R0,var_&FN_TXLEN
	;[287]     #fn_src = SC_ENDPT : ls_max = 65 : GOSUB fn_strlen : GOSUB fn_putstr
	SRCFILE "texas.bas",287
	MVII #37136,R0
	MVO R0,var_&FN_SRC
	MVII #65,R0
	MVO R0,var_LS_MAX
	CALL label_FN_STRLEN
	CALL label_FN_PUTSTR
	;[288]     #fn_src = VARPTR lit_qtable(0) : fn_len = 7 : GOSUB fn_putstr
	SRCFILE "texas.bas",288
	MVII #label_LIT_QTABLE,R0
	MVO R0,var_&FN_SRC
	MVII #7,R0
	MVO R0,var_FN_LEN
	CALL label_FN_PUTSTR
	;[289]     #fn_src = SC_TABLE : ls_max = 9 : GOSUB fn_strlen : GOSUB fn_putstr
	SRCFILE "texas.bas",289
	MVII #37248,R0
	MVO R0,var_&FN_SRC
	MVII #9,R0
	MVO R0,var_LS_MAX
	CALL label_FN_STRLEN
	CALL label_FN_PUTSTR
	;[290] 
	SRCFILE "texas.bas",290
	;[291]     ak_creator_lo = 1 : ak_creator_hi = 0 : ak_app = 1
	SRCFILE "texas.bas",291
	MVII #1,R0
	MVO R0,var_AK_CREATOR_LO
	CLRR R0
	MVO R0,var_AK_CREATOR_HI
	MVII #1,R0
	MVO R0,var_AK_APP
	;[292]     ak_key = AK_LOBBY_KEY_SERVER : ak_mode = 1
	SRCFILE "texas.bas",292
	MVII #8,R0
	MVO R0,var_AK_KEY
	MVII #1,R0
	MVO R0,var_AK_MODE
	;[293]     GOSUB appkey_open
	SRCFILE "texas.bas",293
	CALL label_APPKEY_OPEN
	;[294]     IF fn_ok THEN
	SRCFILE "texas.bas",294
	MVI var_FN_OK,R0
	TSTR R0
	BEQ T101
	;[295]         fn_len = #fn_txlen : #fn_src = FN_TX
	SRCFILE "texas.bas",295
	MVI var_&FN_TXLEN,R0
	MVO R0,var_FN_LEN
	MVII #40000,R0
	MVO R0,var_&FN_SRC
	;[296]         GOSUB appkey_write
	SRCFILE "texas.bas",296
	CALL label_APPKEY_WRITE
	;[297]         GOSUB appkey_close
	SRCFILE "texas.bas",297
	CALL label_APPKEY_CLOSE
	;[298]     END IF
	SRCFILE "texas.bas",298
T101:
	;[299] END
	SRCFILE "texas.bas",299
	RETURN
	ENDP
	;[300] 
	SRCFILE "texas.bas",300
	;[301] ' ---------------------------------------------------------------------------
	SRCFILE "texas.bas",301
	;[302] ' clear_room_appkey: blank the lobby server appkey slot on a deliberate
	SRCFILE "texas.bas",302
	;[303] ' leave, so a later reboot lands on table select instead of silently
	SRCFILE "texas.bas",303
	;[304] ' rejoining a table the player just quit.
	SRCFILE "texas.bas",304
	;[305] ' ---------------------------------------------------------------------------
	SRCFILE "texas.bas",305
	;[306] clear_room_appkey: PROCEDURE
	SRCFILE "texas.bas",306
	; CLEAR_ROOM_APPKEY
label_CLEAR_ROOM_APPKEY:	PROC
	BEGIN
	;[307]     ak_creator_lo = 1 : ak_creator_hi = 0 : ak_app = 1
	SRCFILE "texas.bas",307
	MVII #1,R0
	MVO R0,var_AK_CREATOR_LO
	CLRR R0
	MVO R0,var_AK_CREATOR_HI
	MVII #1,R0
	MVO R0,var_AK_APP
	;[308]     ak_key = AK_LOBBY_KEY_SERVER : ak_mode = 1
	SRCFILE "texas.bas",308
	MVII #8,R0
	MVO R0,var_AK_KEY
	MVII #1,R0
	MVO R0,var_AK_MODE
	;[309]     GOSUB appkey_open
	SRCFILE "texas.bas",309
	CALL label_APPKEY_OPEN
	;[310]     IF fn_ok THEN
	SRCFILE "texas.bas",310
	MVI var_FN_OK,R0
	TSTR R0
	BEQ T102
	;[311]         fn_len = 0 : #fn_src = FN_TX
	SRCFILE "texas.bas",311
	CLRR R0
	MVO R0,var_FN_LEN
	MVII #40000,R0
	MVO R0,var_&FN_SRC
	;[312]         GOSUB appkey_write
	SRCFILE "texas.bas",312
	CALL label_APPKEY_WRITE
	;[313]         GOSUB appkey_close
	SRCFILE "texas.bas",313
	CALL label_APPKEY_CLOSE
	;[314]     END IF
	SRCFILE "texas.bas",314
T102:
	;[315]     POKE SC_TABLE, 0
	SRCFILE "texas.bas",315
	CLRR R0
	MVO R0,37248
	;[316] END
	SRCFILE "texas.bas",316
	RETURN
	ENDP
	;[317] 
	SRCFILE "texas.bas",317
	;[318] ' ===========================================================================
	SRCFILE "texas.bas",318
	;[319] ' Boot
	SRCFILE "texas.bas",319
	;[320] ' ===========================================================================
	SRCFILE "texas.bas",320
	;[321] boot_start:
	SRCFILE "texas.bas",321
	; BOOT_START
label_BOOT_START:	;[322]     MODE 1
	SRCFILE "texas.bas",322
	MVII #3,R0
	MVO R0,_mode_select
	;[323]     CLS
	SRCFILE "texas.bas",323
	CALL CLRSCR
	;[324]     GOSUB fill_bg
	SRCFILE "texas.bas",324
	CALL label_FILL_BG
	;[325]     GOSUB gfx_init
	SRCFILE "texas.bas",325
	CALL label_GFX_INIT
	;[326] 
	SRCFILE "texas.bas",326
	;[327]     PRINT AT 0 COLOR COL_STATUS, "TEXAS HOLDEM"
	SRCFILE "texas.bas",327
	MVII #512,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #416,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #136,R0
	MVO@ R0,R4
	XORI #232,R0
	MVO@ R0,R4
	XORI #200,R0
	MVO@ R0,R4
	XORI #144,R0
	MVO@ R0,R4
	XORI #408,R0
	MVO@ R0,R4
	XORI #320,R0
	MVO@ R0,R4
	XORI #56,R0
	MVO@ R0,R4
	XORI #24,R0
	MVO@ R0,R4
	XORI #64,R0
	MVO@ R0,R4
	XORI #8,R0
	MVO@ R0,R4
	XORI #64,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[328]     PRINT AT 20, "IN GAME, PRESS KEYPAD"
	SRCFILE "texas.bas",328
	MVII #532,R0
	MVO R0,_screen
	MOVR R0,R4
	MVII #328,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #56,R0
	MVO@ R0,R4
	XORI #368,R0
	MVO@ R0,R4
	XORI #312,R0
	MVO@ R0,R4
	XORI #48,R0
	MVO@ R0,R4
	XORI #96,R0
	MVO@ R0,R4
	XORI #64,R0
	MVO@ R0,R4
	XORI #328,R0
	MVO@ R0,R4
	XORI #96,R0
	MVO@ R0,R4
	XORI #384,R0
	MVO@ R0,R4
	XORI #16,R0
	MVO@ R0,R4
	XORI #184,R0
	MVO@ R0,R4
	XORI #176,R0
	MVO@ R0,R4
	MVO@ R0,R4
	XORI #408,R0
	MVO@ R0,R4
	XORI #344,R0
	MVO@ R0,R4
	XORI #112,R0
	MVO@ R0,R4
	XORI #224,R0
	MVO@ R0,R4
	XORI #72,R0
	MVO@ R0,R4
	XORI #136,R0
	MVO@ R0,R4
	XORI #40,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[329]     PRINT AT 40, "CLEAR FOR THE MENU"
	SRCFILE "texas.bas",329
	MVII #552,R0
	MVO R0,_screen
	MOVR R0,R4
	MVII #280,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #120,R0
	MVO@ R0,R4
	XORI #72,R0
	MVO@ R0,R4
	XORI #32,R0
	MVO@ R0,R4
	XORI #152,R0
	MVO@ R0,R4
	XORI #400,R0
	MVO@ R0,R4
	XORI #304,R0
	MVO@ R0,R4
	XORI #72,R0
	MVO@ R0,R4
	XORI #232,R0
	MVO@ R0,R4
	XORI #400,R0
	MVO@ R0,R4
	XORI #416,R0
	MVO@ R0,R4
	XORI #224,R0
	MVO@ R0,R4
	XORI #104,R0
	MVO@ R0,R4
	XORI #296,R0
	MVO@ R0,R4
	XORI #360,R0
	MVO@ R0,R4
	XORI #64,R0
	MVO@ R0,R4
	XORI #88,R0
	MVO@ R0,R4
	XORI #216,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[330]     PRINT AT 60, "CONNECTING TO FUJINET"
	SRCFILE "texas.bas",330
	MVII #572,R0
	MVO R0,_screen
	MOVR R0,R4
	MVII #280,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #96,R0
	MVO@ R0,R4
	XORI #8,R0
	MVO@ R0,R4
	MVO@ R0,R4
	XORI #88,R0
	MVO@ R0,R4
	XORI #48,R0
	MVO@ R0,R4
	XORI #184,R0
	MVO@ R0,R4
	XORI #232,R0
	MVO@ R0,R4
	XORI #56,R0
	MVO@ R0,R4
	XORI #72,R0
	MVO@ R0,R4
	XORI #312,R0
	MVO@ R0,R4
	XORI #416,R0
	MVO@ R0,R4
	XORI #216,R0
	MVO@ R0,R4
	XORI #376,R0
	MVO@ R0,R4
	XORI #304,R0
	MVO@ R0,R4
	XORI #152,R0
	MVO@ R0,R4
	XORI #248,R0
	MVO@ R0,R4
	XORI #24,R0
	MVO@ R0,R4
	XORI #56,R0
	MVO@ R0,R4
	XORI #88,R0
	MVO@ R0,R4
	XORI #136,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[331]     GOSUB fn_wait_mailbox
	SRCFILE "texas.bas",331
	CALL label_FN_WAIT_MAILBOX
	;[332]     IF fn_ok = 0 THEN
	SRCFILE "texas.bas",332
	MVI var_FN_OK,R0
	TSTR R0
	BNE T103
	;[333]         PRINT AT 60, "NO CARTRIDGE MAILBOX"
	SRCFILE "texas.bas",333
	MVII #572,R0
	MVO R0,_screen
	MOVR R0,R4
	MVII #368,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #8,R0
	MVO@ R0,R4
	XORI #376,R0
	MVO@ R0,R4
	XORI #280,R0
	MVO@ R0,R4
	XORI #16,R0
	MVO@ R0,R4
	XORI #152,R0
	MVO@ R0,R4
	XORI #48,R0
	MVO@ R0,R4
	XORI #48,R0
	MVO@ R0,R4
	XORI #216,R0
	MVO@ R0,R4
	XORI #104,R0
	MVO@ R0,R4
	XORI #24,R0
	MVO@ R0,R4
	XORI #16,R0
	MVO@ R0,R4
	XORI #296,R0
	MVO@ R0,R4
	XORI #360,R0
	MVO@ R0,R4
	XORI #96,R0
	MVO@ R0,R4
	XORI #64,R0
	MVO@ R0,R4
	XORI #40,R0
	MVO@ R0,R4
	XORI #112,R0
	MVO@ R0,R4
	XORI #104,R0
	MVO@ R0,R4
	XORI #184,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[334]         GOTO halt
	SRCFILE "texas.bas",334
	B label_HALT
	;[335]     END IF
	SRCFILE "texas.bas",335
T103:
	;[336] 
	SRCFILE "texas.bas",336
	;[337] ' ---------------------------------------------------------------------------
	SRCFILE "texas.bas",337
	;[338] ' Name: try the lobby appkey first; fall back to the disc letter picker if
	SRCFILE "texas.bas",338
	;[339] ' the transaction fails or the stored name is empty.
	SRCFILE "texas.bas",339
	;[340] ' ---------------------------------------------------------------------------
	SRCFILE "texas.bas",340
	;[341]     ' Every other network call in this game gets an implicit retry via the
	SRCFILE "texas.bas",341
	;[342]     ' outer poll loop; this one-shot boot-time appkey read didn't, so a
	SRCFILE "texas.bas",342
	;[343]     ' single cold-connection timeout (the RP2040/ESP32 link needing a
	SRCFILE "texas.bas",343
	;[344]     ' moment right after the mailbox first comes up -- the same thing
	SRCFILE "texas.bas",344
	;[345]     ' that made the very first transaction after boot occasionally time
	SRCFILE "texas.bas",345
	;[346]     ' out earlier in testing) meant falling back to manual name entry for
	SRCFILE "texas.bas",346
	;[347]     ' the whole session even though a name was genuinely stored. Retry
	SRCFILE "texas.bas",347
	;[348]     ' once before giving up.
	SRCFILE "texas.bas",348
	;[349]     gs_i = 0
	SRCFILE "texas.bas",349
	CLRR R0
	MVO R0,var_GS_I
	;[350]     FOR ak_try = 0 TO 1
	SRCFILE "texas.bas",350
	MVO R0,var_AK_TRY
T104:
	;[351]         ak_creator_lo = 1 : ak_creator_hi = 0 : ak_app = 1 : ak_key = 0 : ak_mode = 0
	SRCFILE "texas.bas",351
	MVII #1,R0
	MVO R0,var_AK_CREATOR_LO
	CLRR R0
	MVO R0,var_AK_CREATOR_HI
	MVII #1,R0
	MVO R0,var_AK_APP
	CLRR R0
	MVO R0,var_AK_KEY
	MVO R0,var_AK_MODE
	;[352]         GOSUB appkey_open
	SRCFILE "texas.bas",352
	CALL label_APPKEY_OPEN
	;[353]         IF fn_ok THEN EXIT FOR
	SRCFILE "texas.bas",353
	MVI var_FN_OK,R0
	TSTR R0
	BNE T106
	;[354]     NEXT ak_try
	SRCFILE "texas.bas",354
	MVI var_AK_TRY,R0
	INCR R0
	MVO R0,var_AK_TRY
	CMPI #1,R0
	BLE T104
T106:
	;[355]     IF fn_ok THEN
	SRCFILE "texas.bas",355
	MVI var_FN_OK,R0
	TSTR R0
	BEQ T107
	;[356]         #fn_src = SC_NAME : ls_max = 9 : GOSUB appkey_read
	SRCFILE "texas.bas",356
	MVII #37120,R0
	MVO R0,var_&FN_SRC
	MVII #9,R0
	MVO R0,var_LS_MAX
	CALL label_APPKEY_READ
	;[357]         GOSUB appkey_close
	SRCFILE "texas.bas",357
	CALL label_APPKEY_CLOSE
	;[358]         IF fn_len > 0 THEN
	SRCFILE "texas.bas",358
	MVI var_FN_LEN,R0
	CMPI #0,R0
	BLE T108
	;[359]             ' Validate every character -- the appkey slot (creator=1,
	SRCFILE "texas.bas",359
	;[360]             ' app=1, key=0) is the *shared* lobby username used by every
	SRCFILE "texas.bas",360
	;[361]             ' FujiNet client on this server, so it can hold stale or
	SRCFILE "texas.bas",361
	;[362]             ' outright incompatible data left by other testing (this
	SRCFILE "texas.bas",362
	;[363]             ' repo's own earlier test runs included). Our name-entry
	SRCFILE "texas.bas",363
	;[364]             ' screen can only ever produce A-Z/0-9, so anything outside
	SRCFILE "texas.bas",364
	;[365]             ' that -- a space, punctuation, an '&' or '?' -- is untrusted:
	SRCFILE "texas.bas",365
	;[366]             ' it goes straight into the /state URL's query string
	SRCFILE "texas.bas",366
	;[367]             ' unescaped, and a stray reserved character there is exactly
	SRCFILE "texas.bas",367
	;[368]             ' the kind of thing that gets the request rejected by the
	SRCFILE "texas.bas",368
	;[369]             ' server (seen as an HTTP 400 page landing in FN_RX, which
	SRCFILE "texas.bas",369
	;[370]             ' render_game then tries to draw as if it were game data).
	SRCFILE "texas.bas",370
	;[371]             gs_i = 1
	SRCFILE "texas.bas",371
	MVII #1,R0
	MVO R0,var_GS_I
	;[372]             FOR gs_j = 0 TO fn_len - 1
	SRCFILE "texas.bas",372
	CLRR R0
	MVO R0,var_GS_J
T109:
	;[373]                 gs_char = PEEK(SC_NAME + gs_j) AND 255
	SRCFILE "texas.bas",373
	MVI var_GS_J,R1
	ADDI #37120,R1
	MVI@ R1,R0
	MVO R0,var_GS_CHAR
	;[374]                 IF gs_char >= 97 AND gs_char <= 122 THEN gs_char = gs_char - 32 ' fold to uppercase for the check
	SRCFILE "texas.bas",374
	MVI var_GS_CHAR,R0
	CMPI #97,R0
	MVII #65535,R0
	BGE T111
	INCR R0
T111:
	MVI var_GS_CHAR,R1
	CMPI #122,R1
	MVII #65535,R1
	BLE T112
	INCR R1
T112:
	ANDR R1,R0
	BEQ T110
	MVI var_GS_CHAR,R0
	SUBI #32,R0
	MVO R0,var_GS_CHAR
T110:
	;[375]                 IF (gs_char < 65 OR gs_char > 90) AND (gs_char < 48 OR gs_char > 57) THEN gs_i = 0
	SRCFILE "texas.bas",375
	MVI var_GS_CHAR,R0
	CMPI #65,R0
	MVII #65535,R0
	BLT T114
	INCR R0
T114:
	MVI var_GS_CHAR,R1
	CMPI #90,R1
	MVII #65535,R1
	BGT T115
	INCR R1
T115:
	COMR R1
	ANDR R1,R0
	COMR R1
	XORR R1,R0
	MVI var_GS_CHAR,R1
	CMPI #48,R1
	MVII #65535,R1
	BLT T116
	INCR R1
T116:
	MVI var_GS_CHAR,R2
	CMPI #57,R2
	MVII #65535,R2
	BGT T117
	INCR R2
T117:
	COMR R2
	ANDR R2,R1
	COMR R2
	XORR R2,R1
	ANDR R1,R0
	BEQ T113
	CLRR R0
	MVO R0,var_GS_I
T113:
	;[376]             NEXT gs_j
	SRCFILE "texas.bas",376
	MVI var_GS_J,R0
	INCR R0
	MVO R0,var_GS_J
	MVI var_FN_LEN,R1
	DECR R1
	CMPR R1,R0
	BLE T109
	;[377]         END IF
	SRCFILE "texas.bas",377
T108:
	;[378]     END IF
	SRCFILE "texas.bas",378
T107:
	;[379]     IF gs_i = 0 THEN GOSUB name_entry_screen
	SRCFILE "texas.bas",379
	MVI var_GS_I,R0
	TSTR R0
	BNE T118
	CALL label_NAME_ENTRY_SCREEN
T118:
	;[380] 
	SRCFILE "texas.bas",380
	;[381] ' ---------------------------------------------------------------------------
	SRCFILE "texas.bas",381
	;[382] ' Room: check the lobby server appkey (creator 1 / app 1 / key
	SRCFILE "texas.bas",382
	;[383] ' AK_LOBBY_KEY_SERVER). If the lobby wrote a room there, split it into
	SRCFILE "texas.bas",383
	;[384] ' SC_ENDPT/SC_TABLE and skip straight past table select. Seed the
	SRCFILE "texas.bas",384
	;[385] ' compiled-in default endpoint first so SC_ENDPT is always valid even if
	SRCFILE "texas.bas",385
	;[386] ' the appkey is empty or the read fails -- compose_url relies on it from
	SRCFILE "texas.bas",386
	;[387] ' here on for every request, not just /tables.
	SRCFILE "texas.bas",387
	;[388] ' ---------------------------------------------------------------------------
	SRCFILE "texas.bas",388
	;[389]     FOR gs_i = 0 TO LEN_HTTPS - 1
	SRCFILE "texas.bas",389
	CLRR R0
	MVO R0,var_GS_I
T119:
	;[390]         POKE (SC_ENDPT + gs_i), PEEK(VARPTR lit_https(0) + gs_i) AND 255
	SRCFILE "texas.bas",390
	MVII #label_LIT_HTTPS,R3
	ADD var_GS_I,R3
	MVI@ R3,R0
	ANDI #255,R0
	MVI var_GS_I,R1
	ADDI #37136,R1
	MVO@ R0,R1
	;[391]     NEXT gs_i
	SRCFILE "texas.bas",391
	MVI var_GS_I,R0
	INCR R0
	MVO R0,var_GS_I
	CMPI #27,R0
	BLE T119
	;[392]     POKE (SC_ENDPT + LEN_HTTPS), 0
	SRCFILE "texas.bas",392
	CLRR R0
	MVO R0,37164
	;[393]     POKE SC_TABLE, 0
	SRCFILE "texas.bas",393
	MVO R0,37248
	;[394] 
	SRCFILE "texas.bas",394
	;[395]     FOR ak_try = 0 TO 1
	SRCFILE "texas.bas",395
	NOP
	MVO R0,var_AK_TRY
T120:
	;[396]         ak_creator_lo = 1 : ak_creator_hi = 0 : ak_app = 1
	SRCFILE "texas.bas",396
	MVII #1,R0
	MVO R0,var_AK_CREATOR_LO
	CLRR R0
	MVO R0,var_AK_CREATOR_HI
	MVII #1,R0
	MVO R0,var_AK_APP
	;[397]         ak_key = AK_LOBBY_KEY_SERVER : ak_mode = 0
	SRCFILE "texas.bas",397
	MVII #8,R0
	MVO R0,var_AK_KEY
	CLRR R0
	MVO R0,var_AK_MODE
	;[398]         GOSUB appkey_open
	SRCFILE "texas.bas",398
	CALL label_APPKEY_OPEN
	;[399]         IF fn_ok THEN EXIT FOR
	SRCFILE "texas.bas",399
	MVI var_FN_OK,R0
	TSTR R0
	BNE T122
	;[400]     NEXT ak_try
	SRCFILE "texas.bas",400
	MVI var_AK_TRY,R0
	INCR R0
	MVO R0,var_AK_TRY
	CMPI #1,R0
	BLE T120
T122:
	;[401]     IF fn_ok THEN
	SRCFILE "texas.bas",401
	MVI var_FN_OK,R0
	TSTR R0
	BEQ T123
	;[402]         #fn_src = SC_ENDPT : ls_max = 65 : GOSUB appkey_read
	SRCFILE "texas.bas",402
	MVII #37136,R0
	MVO R0,var_&FN_SRC
	MVII #65,R0
	MVO R0,var_LS_MAX
	CALL label_APPKEY_READ
	;[403]         GOSUB appkey_close
	SRCFILE "texas.bas",403
	CALL label_APPKEY_CLOSE
	;[404]         IF fn_len > 0 THEN
	SRCFILE "texas.bas",404
	MVI var_FN_LEN,R0
	CMPI #0,R0
	BLE T124
	;[405]             GOSUB split_room_url
	SRCFILE "texas.bas",405
	CALL label_SPLIT_ROOM_URL
	;[406]         ELSE
	SRCFILE "texas.bas",406
	B T125
T124:
	;[407]             ' appkey_read always NUL-terminates at fn_len, even when
	SRCFILE "texas.bas",407
	;[408]             ' empty, which would otherwise wipe out the default just
	SRCFILE "texas.bas",408
	;[409]             ' seeded above -- restore it.
	SRCFILE "texas.bas",409
	;[410]             FOR gs_i = 0 TO LEN_HTTPS - 1
	SRCFILE "texas.bas",410
	CLRR R0
	MVO R0,var_GS_I
T126:
	;[411]                 POKE (SC_ENDPT + gs_i), PEEK(VARPTR lit_https(0) + gs_i) AND 255
	SRCFILE "texas.bas",411
	MVII #label_LIT_HTTPS,R3
	ADD var_GS_I,R3
	MVI@ R3,R0
	ANDI #255,R0
	MVI var_GS_I,R1
	ADDI #37136,R1
	MVO@ R0,R1
	;[412]             NEXT gs_i
	SRCFILE "texas.bas",412
	MVI var_GS_I,R0
	INCR R0
	MVO R0,var_GS_I
	CMPI #27,R0
	BLE T126
	;[413]             POKE (SC_ENDPT + LEN_HTTPS), 0
	SRCFILE "texas.bas",413
	CLRR R0
	MVO R0,37164
	;[414]         END IF
	SRCFILE "texas.bas",414
T125:
	;[415]     END IF
	SRCFILE "texas.bas",415
T123:
	;[416] 
	SRCFILE "texas.bas",416
	;[417]     IF (PEEK(SC_TABLE) AND 255) <> 0 THEN GOTO table_joined
	SRCFILE "texas.bas",417
	MVI 37248,R0
	ANDI #255,R0
	BNE label_TABLE_JOINED
	;[418] 
	SRCFILE "texas.bas",418
	;[419] ' ===========================================================================
	SRCFILE "texas.bas",419
	;[420] ' Table select (re-entered after leaving a table)
	SRCFILE "texas.bas",420
	;[421] ' ===========================================================================
	SRCFILE "texas.bas",421
	;[422] table_select:
	SRCFILE "texas.bas",422
	; TABLE_SELECT
label_TABLE_SELECT:	;[423]     CLS
	SRCFILE "texas.bas",423
	CALL CLRSCR
	;[424]     GOSUB fill_bg
	SRCFILE "texas.bas",424
	CALL label_FILL_BG
	;[425]     PRINT AT 0 COLOR COL_STATUS, "CHOOSE A TABLE"
	SRCFILE "texas.bas",425
	MVII #512,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #280,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #88,R0
	MVO@ R0,R4
	XORI #56,R0
	MVO@ R0,R4
	MVO@ R0,R4
	XORI #224,R0
	MVO@ R0,R4
	XORI #176,R0
	MVO@ R0,R4
	XORI #296,R0
	MVO@ R0,R4
	XORI #264,R0
	MVO@ R0,R4
	XORI #264,R0
	MVO@ R0,R4
	XORI #416,R0
	MVO@ R0,R4
	XORI #168,R0
	MVO@ R0,R4
	XORI #24,R0
	MVO@ R0,R4
	XORI #112,R0
	MVO@ R0,R4
	XORI #72,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[426]     PRINT AT 40, "REFRESHING..."
	SRCFILE "texas.bas",426
	MVII #552,R0
	MVO R0,_screen
	MOVR R0,R4
	MVII #400,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #184,R0
	MVO@ R0,R4
	XORI #24,R0
	MVO@ R0,R4
	XORI #160,R0
	MVO@ R0,R4
	XORI #184,R0
	MVO@ R0,R4
	XORI #176,R0
	MVO@ R0,R4
	XORI #216,R0
	MVO@ R0,R4
	XORI #8,R0
	MVO@ R0,R4
	XORI #56,R0
	MVO@ R0,R4
	XORI #72,R0
	MVO@ R0,R4
	XORI #328,R0
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	NOP
	MVO R4,_screen
	;[427] 
	SRCFILE "texas.bas",427
	;[428]     gs_path = 0 : GOSUB compose_url
	SRCFILE "texas.bas",428
	CLRR R0
	MVO R0,var_GS_PATH
	CALL label_COMPOSE_URL
	;[429]     #net_readlen = TABLES_MAXLEN
	SRCFILE "texas.bas",429
	MVII #361,R0
	MVO R0,var_&NET_READLEN
	;[430]     GOSUB api_call
	SRCFILE "texas.bas",430
	CALL label_API_CALL
	;[431] 
	SRCFILE "texas.bas",431
	;[432]     ' As with /state: the mailbox transaction can report success (the
	SRCFILE "texas.bas",432
	;[433]     ' RP2040 relayed *a* reply) even when the HTTP request itself was
	SRCFILE "texas.bas",433
	;[434]     ' rejected -- an error page's bytes would otherwise get misread as a
	SRCFILE "texas.bas",434
	;[435]     ' Tables struct. Validate the response length against what the
	SRCFILE "texas.bas",435
	;[436]     ' reported count actually implies before trusting it.
	SRCFILE "texas.bas",436
	;[437]     IF fn_ok = 1 THEN
	SRCFILE "texas.bas",437
	MVI var_FN_OK,R0
	CMPI #1,R0
	BNE T128
	;[438]         #tmp_expect = 1 + (PEEK(FN_RX) AND 255) * TABLE_STRIDE
	SRCFILE "texas.bas",438
	MVI 40256,R0
	ANDI #255,R0
	MULT R0,R4,36
	INCR R0
	MVO R0,var_&TMP_EXPECT
	;[439]         IF #net_gotlen < #tmp_expect THEN fn_ok = 0
	SRCFILE "texas.bas",439
	MVI var_&NET_GOTLEN,R0
	CMP var_&TMP_EXPECT,R0
	BGE T129
	CLRR R0
	MVO R0,var_FN_OK
T129:
	;[440]     END IF
	SRCFILE "texas.bas",440
T128:
	;[441] 
	SRCFILE "texas.bas",441
	;[442]     IF fn_ok = 0 THEN
	SRCFILE "texas.bas",442
	MVI var_FN_OK,R0
	TSTR R0
	BNE T130
	;[443]         PRINT AT 40, "SERVER UNREACHABLE  "
	SRCFILE "texas.bas",443
	MVII #552,R0
	MVO R0,_screen
	MOVR R0,R4
	MVII #408,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #176,R0
	MVO@ R0,R4
	XORI #184,R0
	MVO@ R0,R4
	XORI #32,R0
	MVO@ R0,R4
	XORI #152,R0
	MVO@ R0,R4
	XORI #184,R0
	MVO@ R0,R4
	XORI #400,R0
	MVO@ R0,R4
	XORI #424,R0
	MVO@ R0,R4
	XORI #216,R0
	MVO@ R0,R4
	XORI #224,R0
	MVO@ R0,R4
	XORI #184,R0
	MVO@ R0,R4
	XORI #32,R0
	MVO@ R0,R4
	XORI #16,R0
	MVO@ R0,R4
	XORI #88,R0
	MVO@ R0,R4
	XORI #72,R0
	MVO@ R0,R4
	XORI #24,R0
	MVO@ R0,R4
	XORI #112,R0
	MVO@ R0,R4
	XORI #72,R0
	MVO@ R0,R4
	XORI #296,R0
	MVO@ R0,R4
	MVO@ R0,R4
	NOP
	MVO R4,_screen
	;[444]         ' TEMP DEBUG: show the exact outgoing URL so a repeat failure is
	SRCFILE "texas.bas",444
	;[445]         ' diagnosable from a screenshot instead of needing another round trip.
	SRCFILE "texas.bas",445
	;[446]         #df_src = FN_TX : df_pos = 60 : df_len = 20 : #df_color = COL_STATUS
	SRCFILE "texas.bas",446
	MVII #40000,R0
	MVO R0,var_&DF_SRC
	MVII #60,R0
	MVO R0,var_DF_POS
	MVII #20,R0
	MVO R0,var_DF_LEN
	MVII #7,R0
	MVO R0,var_&DF_COLOR
	;[447]         GOSUB draw_field
	SRCFILE "texas.bas",447
	CALL label_DRAW_FIELD
	;[448]         #df_src = FN_TX + 20 : df_pos = 80 : df_len = 20 : #df_color = COL_STATUS
	SRCFILE "texas.bas",448
	MVII #40020,R0
	MVO R0,var_&DF_SRC
	MVII #80,R0
	MVO R0,var_DF_POS
	MVII #20,R0
	MVO R0,var_DF_LEN
	MVII #7,R0
	MVO R0,var_&DF_COLOR
	;[449]         GOSUB draw_field
	SRCFILE "texas.bas",449
	CALL label_DRAW_FIELD
	;[450]         #df_src = FN_TX + 40 : df_pos = 100 : df_len = 20 : #df_color = COL_STATUS
	SRCFILE "texas.bas",450
	MVII #40040,R0
	MVO R0,var_&DF_SRC
	MVII #100,R0
	MVO R0,var_DF_POS
	MVII #20,R0
	MVO R0,var_DF_LEN
	MVII #7,R0
	MVO R0,var_&DF_COLOR
	;[451]         GOSUB draw_field
	SRCFILE "texas.bas",451
	CALL label_DRAW_FIELD
	;[452]         poll_wait = 90
	SRCFILE "texas.bas",452
	MVII #90,R0
	MVO R0,var_POLL_WAIT
	;[453]         WHILE poll_wait > 0
	SRCFILE "texas.bas",453
T131:
	MVI var_POLL_WAIT,R0
	CMPI #0,R0
	BLE T132
	;[454]             poll_wait = poll_wait - 1
	SRCFILE "texas.bas",454
	DECR R0
	MVO R0,var_POLL_WAIT
	;[455]             WAIT
	SRCFILE "texas.bas",455
	CALL _wait
	;[456]         WEND
	SRCFILE "texas.bas",456
	B T131
T132:
	;[457]         GOTO table_select
	SRCFILE "texas.bas",457
	B label_TABLE_SELECT
	;[458]     END IF
	SRCFILE "texas.bas",458
T130:
	;[459] 
	SRCFILE "texas.bas",459
	;[460]     tbl_count = PEEK(FN_RX) AND 255
	SRCFILE "texas.bas",460
	MVI 40256,R0
	MVO R0,var_TBL_COUNT
	;[461]     IF tbl_count > 6 THEN tbl_count = 6
	SRCFILE "texas.bas",461
	MVI var_TBL_COUNT,R0
	CMPI #6,R0
	BLE T133
	MVII #6,R0
	MVO R0,var_TBL_COUNT
T133:
	;[462]     IF tbl_count = 0 THEN
	SRCFILE "texas.bas",462
	MVI var_TBL_COUNT,R0
	TSTR R0
	BNE T134
	;[463]         PRINT AT 40, "NO TABLES AVAILABLE "
	SRCFILE "texas.bas",463
	MVII #552,R0
	MVO R0,_screen
	MOVR R0,R4
	MVII #368,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #8,R0
	MVO@ R0,R4
	XORI #376,R0
	MVO@ R0,R4
	XORI #416,R0
	MVO@ R0,R4
	XORI #168,R0
	MVO@ R0,R4
	XORI #24,R0
	MVO@ R0,R4
	XORI #112,R0
	MVO@ R0,R4
	XORI #72,R0
	MVO@ R0,R4
	XORI #176,R0
	MVO@ R0,R4
	XORI #408,R0
	MVO@ R0,R4
	XORI #264,R0
	MVO@ R0,R4
	XORI #184,R0
	MVO@ R0,R4
	XORI #184,R0
	MVO@ R0,R4
	XORI #64,R0
	MVO@ R0,R4
	XORI #40,R0
	MVO@ R0,R4
	XORI #104,R0
	MVO@ R0,R4
	XORI #24,R0
	MVO@ R0,R4
	XORI #112,R0
	MVO@ R0,R4
	XORI #72,R0
	MVO@ R0,R4
	XORI #296,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[464]         poll_wait = 90
	SRCFILE "texas.bas",464
	MVII #90,R0
	MVO R0,var_POLL_WAIT
	;[465]         WHILE poll_wait > 0
	SRCFILE "texas.bas",465
T135:
	MVI var_POLL_WAIT,R0
	CMPI #0,R0
	BLE T136
	;[466]             poll_wait = poll_wait - 1
	SRCFILE "texas.bas",466
	DECR R0
	MVO R0,var_POLL_WAIT
	;[467]             WAIT
	SRCFILE "texas.bas",467
	CALL _wait
	;[468]         WEND
	SRCFILE "texas.bas",468
	B T135
T136:
	;[469]         GOTO table_select
	SRCFILE "texas.bas",469
	B label_TABLE_SELECT
	;[470]     END IF
	SRCFILE "texas.bas",470
T134:
	;[471] 
	SRCFILE "texas.bas",471
	;[472]     CLS
	SRCFILE "texas.bas",472
	CALL CLRSCR
	;[473]     GOSUB fill_bg
	SRCFILE "texas.bas",473
	CALL label_FILL_BG
	;[474]     PRINT AT 0 COLOR COL_STATUS, "CHOOSE A TABLE"
	SRCFILE "texas.bas",474
	MVII #512,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #280,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #88,R0
	MVO@ R0,R4
	XORI #56,R0
	MVO@ R0,R4
	MVO@ R0,R4
	XORI #224,R0
	MVO@ R0,R4
	XORI #176,R0
	MVO@ R0,R4
	XORI #296,R0
	MVO@ R0,R4
	XORI #264,R0
	MVO@ R0,R4
	XORI #264,R0
	MVO@ R0,R4
	XORI #416,R0
	MVO@ R0,R4
	XORI #168,R0
	MVO@ R0,R4
	XORI #24,R0
	MVO@ R0,R4
	XORI #112,R0
	MVO@ R0,R4
	XORI #72,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[475]     FOR gs_i = 0 TO tbl_count - 1
	SRCFILE "texas.bas",475
	CLRR R0
	MVO R0,var_GS_I
T137:
	;[476]         #tmp_addr = table_addr(gs_i)
	SRCFILE "texas.bas",476
	MVI var_GS_I,R0
	MULT R0,R4,36
	ADDI #40257,R0
	MVO R0,var_&TMP_ADDR
	;[477]         #df_src = #tmp_addr + TBL_NAME : df_pos = 20 + gs_i * 20 + 1 : df_len = 14 : #df_color = COL_NAME
	SRCFILE "texas.bas",477
	ADDI #9,R0
	MVO R0,var_&DF_SRC
	MVI var_GS_I,R0
	MULT R0,R4,20
	ADDI #21,R0
	MVO R0,var_DF_POS
	MVII #14,R0
	MVO R0,var_DF_LEN
	MVII #8199,R0
	MVO R0,var_&DF_COLOR
	;[478]         GOSUB draw_field
	SRCFILE "texas.bas",478
	CALL label_DRAW_FIELD
	;[479]         #df_src = #tmp_addr + TBL_PLAYERS : df_pos = 20 + gs_i * 20 + 15 : df_len = 5 : #df_color = COL_NAME
	SRCFILE "texas.bas",479
	MVI var_&TMP_ADDR,R0
	ADDI #30,R0
	MVO R0,var_&DF_SRC
	MVI var_GS_I,R0
	MULT R0,R4,20
	ADDI #35,R0
	MVO R0,var_DF_POS
	MVII #5,R0
	MVO R0,var_DF_LEN
	MVII #8199,R0
	MVO R0,var_&DF_COLOR
	;[480]         GOSUB draw_field
	SRCFILE "texas.bas",480
	CALL label_DRAW_FIELD
	;[481]     NEXT gs_i
	SRCFILE "texas.bas",481
	MVI var_GS_I,R0
	INCR R0
	MVO R0,var_GS_I
	MVI var_TBL_COUNT,R1
	DECR R1
	CMPR R1,R0
	BLE T137
	;[482] 
	SRCFILE "texas.bas",482
	;[483]     tbl_sel = 0
	SRCFILE "texas.bas",483
	CLRR R0
	MVO R0,var_TBL_SEL
	;[484]     inp_lock = 0
	SRCFILE "texas.bas",484
	MVO R0,var_INP_LOCK
	;[485] tbl_input:
	SRCFILE "texas.bas",485
	; TBL_INPUT
label_TBL_INPUT:	;[486]     WAIT
	SRCFILE "texas.bas",486
	CALL _wait
	;[487]     GOSUB read_input
	SRCFILE "texas.bas",487
	CALL label_READ_INPUT
	;[488]     FOR gs_i = 0 TO tbl_count - 1
	SRCFILE "texas.bas",488
	CLRR R0
	MVO R0,var_GS_I
T138:
	;[489]         #gs_c = COL_NAME
	SRCFILE "texas.bas",489
	MVII #8199,R0
	MVO R0,var_&GS_C
	;[490]         IF gs_i = tbl_sel THEN #gs_c = COL_HILITE
	SRCFILE "texas.bas",490
	MVI var_GS_I,R0
	CMP var_TBL_SEL,R0
	BNE T139
	MVII #8198,R0
	MVO R0,var_&GS_C
T139:
	;[491]         #BACKTAB(20 + gs_i * 20) = (62 - 32) * 8 + #gs_c ' '>' cursor glyph
	SRCFILE "texas.bas",491
	MVII #Q2+20,R0
	MVI var_GS_I,R1
	MULT R1,R4,20
	ADDR R1,R0
	MVI var_&GS_C,R1
	ADDI #240,R1
	MOVR R0,R4
	MVO@ R1,R4
	;[492]     NEXT gs_i
	SRCFILE "texas.bas",492
	MVI var_GS_I,R0
	INCR R0
	MVO R0,var_GS_I
	MVI var_TBL_COUNT,R1
	DECR R1
	CMPR R1,R0
	BLE T138
	;[493] 
	SRCFILE "texas.bas",493
	;[494]     IF inp_lock > 0 THEN inp_lock = inp_lock - 1 : GOTO tbl_input
	SRCFILE "texas.bas",494
	MVI var_INP_LOCK,R0
	CMPI #0,R0
	BLE T140
	DECR R0
	MVO R0,var_INP_LOCK
	B label_TBL_INPUT
T140:
	;[495] 
	SRCFILE "texas.bas",495
	;[496]     IF inp_dir AND DISC_DOWN THEN
	SRCFILE "texas.bas",496
	MVI var_INP_DIR,R0
	ANDI #1,R0
	BEQ T141
	;[497]         tbl_sel = tbl_sel + 1
	SRCFILE "texas.bas",497
	MVI var_TBL_SEL,R0
	INCR R0
	MVO R0,var_TBL_SEL
	;[498]         IF tbl_sel >= tbl_count THEN tbl_sel = 0
	SRCFILE "texas.bas",498
	MVI var_TBL_SEL,R0
	CMP var_TBL_COUNT,R0
	BLT T142
	CLRR R0
	MVO R0,var_TBL_SEL
T142:
	;[499]         inp_lock = 8
	SRCFILE "texas.bas",499
	MVII #8,R0
	MVO R0,var_INP_LOCK
	;[500]         GOSUB sound_cursor
	SRCFILE "texas.bas",500
	CALL label_SOUND_CURSOR
	;[501]         GOTO tbl_input
	SRCFILE "texas.bas",501
	B label_TBL_INPUT
	;[502]     END IF
	SRCFILE "texas.bas",502
T141:
	;[503]     IF inp_dir AND DISC_UP THEN
	SRCFILE "texas.bas",503
	MVI var_INP_DIR,R0
	ANDI #4,R0
	BEQ T143
	;[504]         IF tbl_sel = 0 THEN tbl_sel = tbl_count
	SRCFILE "texas.bas",504
	MVI var_TBL_SEL,R0
	TSTR R0
	BNE T144
	MVI var_TBL_COUNT,R0
	MVO R0,var_TBL_SEL
T144:
	;[505]         tbl_sel = tbl_sel - 1
	SRCFILE "texas.bas",505
	MVI var_TBL_SEL,R0
	DECR R0
	MVO R0,var_TBL_SEL
	;[506]         inp_lock = 8
	SRCFILE "texas.bas",506
	MVII #8,R0
	MVO R0,var_INP_LOCK
	;[507]         GOSUB sound_cursor
	SRCFILE "texas.bas",507
	CALL label_SOUND_CURSOR
	;[508]         GOTO tbl_input
	SRCFILE "texas.bas",508
	B label_TBL_INPUT
	;[509]     END IF
	SRCFILE "texas.bas",509
T143:
	;[510]     IF inp_btn_hit = 0 THEN GOTO tbl_input
	SRCFILE "texas.bas",510
	MVI var_INP_BTN_HIT,R0
	TSTR R0
	BEQ label_TBL_INPUT
	;[511]     GOSUB sound_select
	SRCFILE "texas.bas",511
	CALL label_SOUND_SELECT
	;[512] 
	SRCFILE "texas.bas",512
	;[513]     #tmp_addr = table_addr(tbl_sel)
	SRCFILE "texas.bas",513
	MVI var_TBL_SEL,R0
	MULT R0,R4,36
	ADDI #40257,R0
	MVO R0,var_&TMP_ADDR
	;[514]     FOR gs_i = 0 TO 8
	SRCFILE "texas.bas",514
	CLRR R0
	MVO R0,var_GS_I
T146:
	;[515]         POKE (SC_TABLE + gs_i), PEEK(#tmp_addr + TBL_ID + gs_i) AND 255
	SRCFILE "texas.bas",515
	MVI var_&TMP_ADDR,R1
	ADD var_GS_I,R1
	MVI@ R1,R0
	ANDI #255,R0
	MVI var_GS_I,R1
	ADDI #37248,R1
	MVO@ R0,R1
	;[516]     NEXT gs_i
	SRCFILE "texas.bas",516
	MVI var_GS_I,R0
	INCR R0
	MVO R0,var_GS_I
	CMPI #8,R0
	BLE T146
	;[517] 
	SRCFILE "texas.bas",517
	;[518]     ' Update the lobby server appkey so a reboot without going back
	SRCFILE "texas.bas",518
	;[519]     ' through the lobby rejoins this table.
	SRCFILE "texas.bas",519
	;[520]     GOSUB write_room_appkey
	SRCFILE "texas.bas",520
	CALL label_WRITE_ROOM_APPKEY
	;[521] 
	SRCFILE "texas.bas",521
	;[522] table_joined:
	SRCFILE "texas.bas",522
	; TABLE_JOINED
label_TABLE_JOINED:	;[523] ' ===========================================================================
	SRCFILE "texas.bas",523
	;[524] ' Main game loop
	SRCFILE "texas.bas",524
	;[525] ' ===========================================================================
	SRCFILE "texas.bas",525
	;[526]     GOSUB sound_join
	SRCFILE "texas.bas",526
	CALL label_SOUND_JOIN
	;[527]     has_move = 0
	SRCFILE "texas.bas",527
	CLRR R0
	MVO R0,var_HAS_MOVE
	;[528]     poll_wait = 0
	SRCFILE "texas.bas",528
	MVO R0,var_POLL_WAIT
	;[529]     force_redraw = 0
	SRCFILE "texas.bas",529
	NOP
	MVO R0,var_FORCE_REDRAW
	;[530]     prev_round = 255      ' sentinel: forces a full CLS on the first render_game
	SRCFILE "texas.bas",530
	MVII #255,R0
	MVO R0,var_PREV_ROUND
	;[531]     prev_playercount = 255
	SRCFILE "texas.bas",531
	MVO R0,var_PREV_PLAYERCOUNT
	;[532]     #prev_pot = 65535
	SRCFILE "texas.bas",532
	MVII #65535,R0
	MVO R0,var_&PREV_POT
	;[533]     #prev_purse = 65535
	SRCFILE "texas.bas",533
	MVO R0,var_&PREV_PURSE
	;[534]     #prev_result_hash = 65535 ' sentinel: max possible real hash is 20*255=5100
	SRCFILE "texas.bas",534
	NOP
	MVO R0,var_&PREV_RESULT_HASH
	;[535]     prev_active = 255 ' sentinel: forces the turn cue if we sit down mid-turn
	SRCFILE "texas.bas",535
	MVII #255,R0
	MVO R0,var_PREV_ACTIVE
	;[536]     first_poll = 1 ' arm the baseline on the first poll instead of showing it --
	SRCFILE "texas.bas",536
	MVII #1,R0
	MVO R0,var_FIRST_POLL
	;[537]                     ' lastResult can already hold a message from a hand that
	SRCFILE "texas.bas",537
	;[538]                     ' finished before we joined/sat down, which isn't "new"
	SRCFILE "texas.bas",538
	;[539]     prev_community = 0
	SRCFILE "texas.bas",539
	CLRR R0
	MVO R0,var_PREV_COMMUNITY
	;[540]     FOR gs_i = 0 TO 7
	SRCFILE "texas.bas",540
	MVO R0,var_GS_I
T147:
	;[541]         prev_bet(gs_i) = 255
	SRCFILE "texas.bas",541
	MVII #255,R0
	MVII #array_PREV_BET,R3
	ADD var_GS_I,R3
	MVO@ R0,R3
	;[542]         prev_cards(gs_i) = 0
	SRCFILE "texas.bas",542
	CLRR R0
	ADDI #(array_PREV_CARDS-array_PREV_BET) AND $FFFF,R3
	MVO@ R0,R3
	;[543]     NEXT gs_i
	SRCFILE "texas.bas",543
	MVI var_GS_I,R0
	INCR R0
	MVO R0,var_GS_I
	CMPI #7,R0
	BLE T147
	;[544] 
	SRCFILE "texas.bas",544
	;[545] game_loop:
	SRCFILE "texas.bas",545
	; GAME_LOOP
label_GAME_LOOP:	;[546]     WAIT
	SRCFILE "texas.bas",546
	CALL _wait
	;[547]     GOSUB read_input
	SRCFILE "texas.bas",547
	CALL label_READ_INPUT
	;[548] 
	SRCFILE "texas.bas",548
	;[549]     IF poll_wait > 0 THEN
	SRCFILE "texas.bas",549
	MVI var_POLL_WAIT,R0
	CMPI #0,R0
	BLE T148
	;[550]         poll_wait = poll_wait - 1
	SRCFILE "texas.bas",550
	DECR R0
	MVO R0,var_POLL_WAIT
	;[551]         GOTO input_check
	SRCFILE "texas.bas",551
	B label_INPUT_CHECK
	;[552]     END IF
	SRCFILE "texas.bas",552
T148:
	;[553] 
	SRCFILE "texas.bas",553
	;[554]     IF has_move THEN
	SRCFILE "texas.bas",554
	MVI var_HAS_MOVE,R0
	TSTR R0
	BEQ T149
	;[555]         gs_path = 2
	SRCFILE "texas.bas",555
	MVII #2,R0
	MVO R0,var_GS_PATH
	;[556]     ELSE
	SRCFILE "texas.bas",556
	B T150
T149:
	;[557]         gs_path = 1
	SRCFILE "texas.bas",557
	MVII #1,R0
	MVO R0,var_GS_PATH
	;[558]     END IF
	SRCFILE "texas.bas",558
T150:
	;[559]     GOSUB compose_url
	SRCFILE "texas.bas",559
	CALL label_COMPOSE_URL
	;[560]     #net_readlen = GAME_MAXLEN
	SRCFILE "texas.bas",560
	MVII #429,R0
	MVO R0,var_&NET_READLEN
	;[561]     GOSUB api_call
	SRCFILE "texas.bas",561
	CALL label_API_CALL
	;[562]     has_move = 0
	SRCFILE "texas.bas",562
	CLRR R0
	MVO R0,var_HAS_MOVE
	;[563] 
	SRCFILE "texas.bas",563
	;[564]     ' A short read means FN_RX beyond #net_gotlen still holds stale bytes
	SRCFILE "texas.bas",564
	;[565]     ' from a previous, larger response -- render_game trusts fixed offsets
	SRCFILE "texas.bas",565
	;[566]     ' deep into the buffer, so rendering it would show corrupted-looking
	SRCFILE "texas.bas",566
	;[567]     ' data (a garbage pot/bet value, or a stray card glyph) instead of
	SRCFILE "texas.bas",567
	;[568]     ' just skipping this poll. GAME_MINLEN alone isn't tight enough: it's
	SRCFILE "texas.bas",568
	;[569]     ' only the 0-player floor, so a 7-8 player game's response could land
	SRCFILE "texas.bas",569
	;[570]     ' anywhere from 165 bytes up to its true ~400 bytes and still pass
	SRCFILE "texas.bas",570
	;[571]     ' that check while genuinely truncated partway through the player
	SRCFILE "texas.bas",571
	;[572]     ' array. playerCount (offset 164) is read from before where any
	SRCFILE "texas.bas",572
	;[573]     ' truncation could have happened, so it's safe to use here to compute
	SRCFILE "texas.bas",573
	;[574]     ' the *exact* expected length for this specific response.
	SRCFILE "texas.bas",574
	;[575]     ' A malformed request (e.g. a stray character somewhere it shouldn't
	SRCFILE "texas.bas",575
	;[576]     ' be) can get rejected by the server with an HTTP error page instead
	SRCFILE "texas.bas",576
	;[577]     ' of a Game struct -- our mailbox transaction still reports "OK" (the
	SRCFILE "texas.bas",577
	;[578]     ' RP2040 got *a* reply, just not the one we wanted), so round/
	SRCFILE "texas.bas",578
	;[579]     ' playerCount are the cheapest smoke test: neither should ever be
	SRCFILE "texas.bas",579
	;[580]     ' implausible for a real response, and checking them here means a
	SRCFILE "texas.bas",580
	;[581]     ' bogus response gets treated as a failed poll instead of being
	SRCFILE "texas.bas",581
	;[582]     ' handed to render_game as if it were valid.
	SRCFILE "texas.bas",582
	;[583]     IF fn_ok = 1 AND #net_gotlen >= GAME_MINLEN THEN
	SRCFILE "texas.bas",583
	MVI var_FN_OK,R0
	CMPI #1,R0
	MVII #65535,R0
	BEQ T152
	INCR R0
T152:
	MVI var_&NET_GOTLEN,R1
	CMPI #165,R1
	MVII #65535,R1
	BGE T153
	INCR R1
T153:
	ANDR R1,R0
	BEQ T151
	;[584]         IF (PEEK(FN_RX + GAME_ROUND) AND 255) > 5 OR (PEEK(FN_RX + GAME_PLAYERCOUNT) AND 255) > 8 THEN fn_ok = 0
	SRCFILE "texas.bas",584
	MVI 40337,R0
	ANDI #255,R0
	CMPI #5,R0
	MVII #65535,R0
	BGT T155
	INCR R0
T155:
	MVI 40420,R1
	ANDI #255,R1
	CMPI #8,R1
	MVII #65535,R1
	BGT T156
	INCR R1
T156:
	COMR R1
	ANDR R1,R0
	COMR R1
	XORR R1,R0
	BEQ T154
	CLRR R0
	MVO R0,var_FN_OK
T154:
	;[585]     END IF
	SRCFILE "texas.bas",585
T151:
	;[586] 
	SRCFILE "texas.bas",586
	;[587]     IF fn_ok = 1 AND #net_gotlen >= GAME_MINLEN THEN
	SRCFILE "texas.bas",587
	MVI var_FN_OK,R0
	CMPI #1,R0
	MVII #65535,R0
	BEQ T158
	INCR R0
T158:
	MVI var_&NET_GOTLEN,R1
	CMPI #165,R1
	MVII #65535,R1
	BGE T159
	INCR R1
T159:
	ANDR R1,R0
	BEQ T157
	;[588]         #tmp_expect = GAME_PLAYERS + (PEEK(FN_RX + GAME_PLAYERCOUNT) AND 255) * PLAYER_STRIDE
	SRCFILE "texas.bas",588
	MVI 40420,R0
	ANDI #255,R0
	MULT R0,R4,33
	ADDI #165,R0
	MVO R0,var_&TMP_EXPECT
	;[589]         IF #net_gotlen < #tmp_expect THEN fn_ok = 0
	SRCFILE "texas.bas",589
	MVI var_&NET_GOTLEN,R0
	CMP var_&TMP_EXPECT,R0
	BGE T160
	CLRR R0
	MVO R0,var_FN_OK
T160:
	;[590]     END IF
	SRCFILE "texas.bas",590
T157:
	;[591] 
	SRCFILE "texas.bas",591
	;[592]     IF fn_ok = 0 OR #net_gotlen < GAME_MINLEN THEN
	SRCFILE "texas.bas",592
	MVI var_FN_OK,R0
	TSTR R0
	MVII #65535,R0
	BEQ T162
	INCR R0
T162:
	MVI var_&NET_GOTLEN,R1
	CMPI #165,R1
	MVII #65535,R1
	BLT T163
	INCR R1
T163:
	COMR R1
	ANDR R1,R0
	COMR R1
	XORR R1,R0
	BEQ T161
	;[593]         poll_wait = 30
	SRCFILE "texas.bas",593
	MVII #30,R0
	MVO R0,var_POLL_WAIT
	;[594]         GOTO input_check
	SRCFILE "texas.bas",594
	B label_INPUT_CHECK
	;[595]     END IF
	SRCFILE "texas.bas",595
T161:
	;[596] 
	SRCFILE "texas.bas",596
	;[597]     ' Render *before* checking for a new result message: this is the one
	SRCFILE "texas.bas",597
	;[598]     ' poll whose response actually carries the showdown's revealed hands
	SRCFILE "texas.bas",598
	;[599]     ' (masked "????" flips to the real hole cards only for this response --
	SRCFILE "texas.bas",599
	;[600]     ' by the next poll the server has usually already started a new hand
	SRCFILE "texas.bas",600
	;[601]     ' and reset them). Rendering first means the reveal lands on screen
	SRCFILE "texas.bas",601
	;[602]     ' before the message overlay below covers the bottom two rows; doing
	SRCFILE "texas.bas",602
	;[603]     ' it the other way around (as before) meant the reveal was drawn *at
	SRCFILE "texas.bas",603
	;[604]     ' the earliest* 4 seconds later, by which point it was already gone,
	SRCFILE "texas.bas",604
	;[605]     ' so it never actually appeared.
	SRCFILE "texas.bas",605
	;[606]     GOSUB render_game
	SRCFILE "texas.bas",606
	CALL label_RENDER_GAME
	;[607] 
	SRCFILE "texas.bas",607
	;[608]     ' The server sends a one-shot message (e.g. "Fry BOT won with Pair,
	SRCFILE "texas.bas",608
	;[609]     ' Sixes") in lastResult at the end of a round/hand, but it's normally
	SRCFILE "texas.bas",609
	;[610]     ' only shown in the single-line status row -- easy to miss entirely
	SRCFILE "texas.bas",610
	;[611]     ' since bots move fast and the round can already have advanced past
	SRCFILE "texas.bas",611
	;[612]     ' it by the next poll. Detect a new (changed, non-empty) message via
	SRCFILE "texas.bas",612
	;[613]     ' a cheap byte-sum "hash" and, when one shows up, black out the
	SRCFILE "texas.bas",613
	;[614]     ' bottom two rows to display it prominently and hold it there for a
	SRCFILE "texas.bas",614
	;[615]     ' few seconds before resuming play.
	SRCFILE "texas.bas",615
	;[616]     #tmp_hash = 0
	SRCFILE "texas.bas",616
	CLRR R0
	MVO R0,var_&TMP_HASH
	;[617]     FOR gs_i = 0 TO 19
	SRCFILE "texas.bas",617
	MVO R0,var_GS_I
T164:
	;[618]         #tmp_hash = #tmp_hash + (PEEK(FN_RX + GAME_LASTRESULT + gs_i) AND 255)
	SRCFILE "texas.bas",618
	MVI var_GS_I,R1
	ADDI #40256,R1
	MVI@ R1,R0
	ANDI #255,R0
	ADD var_&TMP_HASH,R0
	MVO R0,var_&TMP_HASH
	;[619]     NEXT gs_i
	SRCFILE "texas.bas",619
	MVI var_GS_I,R0
	INCR R0
	MVO R0,var_GS_I
	CMPI #19,R0
	BLE T164
	;[620]     IF first_poll THEN
	SRCFILE "texas.bas",620
	MVI var_FIRST_POLL,R0
	TSTR R0
	BEQ T165
	;[621]         first_poll = 0
	SRCFILE "texas.bas",621
	CLRR R0
	MVO R0,var_FIRST_POLL
	;[622]         #prev_result_hash = #tmp_hash ' arm the baseline silently; whatever's
	SRCFILE "texas.bas",622
	MVI var_&TMP_HASH,R0
	MVO R0,var_&PREV_RESULT_HASH
	;[623]                                         ' already there predates us sitting down
	SRCFILE "texas.bas",623
	;[624]     ELSEIF (PEEK(FN_RX + GAME_LASTRESULT) AND 255) <> 0 AND #tmp_hash <> #prev_result_hash THEN
	SRCFILE "texas.bas",624
	B T166
T165:
	MVI 40256,R0
	ANDI #255,R0
	MVII #65535,R0
	BNE T168
	INCR R0
T168:
	MVI var_&TMP_HASH,R1
	CMP var_&PREV_RESULT_HASH,R1
	MVII #65535,R1
	BNE T169
	INCR R1
T169:
	ANDR R1,R0
	BEQ T167
	;[625]         #prev_result_hash = #tmp_hash
	SRCFILE "texas.bas",625
	MVI var_&TMP_HASH,R0
	MVO R0,var_&PREV_RESULT_HASH
	;[626]         FOR gs_i = STATUS_ROW - ROWCELLS TO STATUS_ROW + ROWCELLS - 1
	SRCFILE "texas.bas",626
	MVII #200,R0
	MVO R0,var_GS_I
T170:
	;[627]             #BACKTAB(gs_i) = COL_STATUS
	SRCFILE "texas.bas",627
	MVII #7,R0
	MVII #Q2,R3
	ADD var_GS_I,R3
	MVO@ R0,R3
	;[628]         NEXT gs_i
	SRCFILE "texas.bas",628
	MVI var_GS_I,R0
	INCR R0
	MVO R0,var_GS_I
	CMPI #239,R0
	BLE T170
	;[629]         #df_src = FN_RX + GAME_LASTRESULT : df_pos = STATUS_ROW - ROWCELLS : df_len = 2 * ROWCELLS : #df_color = COL_STATUS
	SRCFILE "texas.bas",629
	MVII #40256,R0
	MVO R0,var_&DF_SRC
	MVII #200,R0
	MVO R0,var_DF_POS
	MVII #40,R0
	MVO R0,var_DF_LEN
	MVII #7,R0
	MVO R0,var_&DF_COLOR
	;[630]         GOSUB draw_field
	SRCFILE "texas.bas",630
	CALL label_DRAW_FIELD
	;[631]         GOSUB sound_gamedone
	SRCFILE "texas.bas",631
	CALL label_SOUND_GAMEDONE
	;[632]         force_redraw = 1 ' restore the felt background under row 10 once play resumes
	SRCFILE "texas.bas",632
	MVII #1,R0
	MVO R0,var_FORCE_REDRAW
	;[633]         poll_wait = 240
	SRCFILE "texas.bas",633
	MVII #240,R0
	MVO R0,var_POLL_WAIT
	;[634]         GOTO input_check
	SRCFILE "texas.bas",634
	B label_INPUT_CHECK
	;[635]     END IF
	SRCFILE "texas.bas",635
T166:
T167:
	;[636]     poll_wait = 20
	SRCFILE "texas.bas",636
	MVII #20,R0
	MVO R0,var_POLL_WAIT
	;[637] 
	SRCFILE "texas.bas",637
	;[638]     ' Turn edge: activePlayer differs from the previous poll's. move_ui is
	SRCFILE "texas.bas",638
	;[639]     ' re-entered on every poll where it's still your turn -- bail to the
	SRCFILE "texas.bas",639
	;[640]     ' in-game menu and resume and you land back in it -- so activePlayer
	SRCFILE "texas.bas",640
	;[641]     ' alone can't tell "your turn just began" from "still your turn", and
	SRCFILE "texas.bas",641
	;[642]     ' the cue would replay each time. Deliberately updated here rather than
	SRCFILE "texas.bas",642
	;[643]     ' at the end of the loop: the GOTO input_check early exits above (short
	SRCFILE "texas.bas",643
	;[644]     ' read, and the 4-second result-overlay hold) leave prev_active alone,
	SRCFILE "texas.bas",644
	;[645]     ' so a poll that never got as far as the move UI doesn't eat the edge.
	SRCFILE "texas.bas",645
	;[646]     ' Each betting street you act on is a real activePlayer transition, so
	SRCFILE "texas.bas",646
	;[647]     ' the cue fires once per street rather than once per hand.
	SRCFILE "texas.bas",647
	;[648]     turn_changed = 0
	SRCFILE "texas.bas",648
	CLRR R0
	MVO R0,var_TURN_CHANGED
	;[649]     IF active_player <> prev_active THEN turn_changed = 1
	SRCFILE "texas.bas",649
	MVI 40340,R0
	ANDI #255,R0
	CMPI #255,R0
	MVII #65535,R0
	BEQ T172
	INCR R0
T172:
	MVII #65280,R5
	CLRR R4
	CLRC
	RRC R0,1
	BEQ T174
T173:
	BNC T175
	ADDR R5,R4
T175:
	ADDR R5,R5
	SARC R0,1
	BNE T173
T174:
	BNC T176
	ADDR R5,R4
T176:
	MOVR R4,R0
	MVI 40340,R1
	ANDI #255,R1
	ADDR R1,R0
	CMP var_PREV_ACTIVE,R0
	BEQ T171
	MVII #1,R0
	MVO R0,var_TURN_CHANGED
T171:
	;[650]     prev_active = active_player
	SRCFILE "texas.bas",650
	MVI 40340,R0
	ANDI #255,R0
	CMPI #255,R0
	MVII #65535,R0
	BEQ T177
	INCR R0
T177:
	MVII #65280,R5
	CLRR R4
	CLRC
	RRC R0,1
	BEQ T179
T178:
	BNC T180
	ADDR R5,R4
T180:
	ADDR R5,R5
	SARC R0,1
	BNE T178
T179:
	BNC T181
	ADDR R5,R4
T181:
	MOVR R4,R0
	MVI 40340,R1
	ANDI #255,R1
	ADDR R1,R0
	MVO R0,var_PREV_ACTIVE
	;[651] 
	SRCFILE "texas.bas",651
	;[652]     IF active_player = 0 AND (PEEK(FN_RX + GAME_VIEWING) AND 255) = 0 THEN
	SRCFILE "texas.bas",652
	MVI 40340,R0
	ANDI #255,R0
	CMPI #255,R0
	MVII #65535,R0
	BEQ T183
	INCR R0
T183:
	MVII #65280,R5
	CLRR R4
	CLRC
	RRC R0,1
	BEQ T185
T184:
	BNC T186
	ADDR R5,R4
T186:
	ADDR R5,R5
	SARC R0,1
	BNE T184
T185:
	BNC T187
	ADDR R5,R4
T187:
	MOVR R4,R0
	MVI 40340,R1
	ANDI #255,R1
	ADDR R1,R0
	MVII #65535,R0
	BEQ T188
	INCR R0
T188:
	MVI 40342,R1
	ANDI #255,R1
	MVII #65535,R1
	BEQ T189
	INCR R1
T189:
	ANDR R1,R0
	BEQ T182
	;[653]         GOSUB move_ui
	SRCFILE "texas.bas",653
	CALL label_MOVE_UI
	;[654]         IF has_move THEN poll_wait = 0
	SRCFILE "texas.bas",654
	MVI var_HAS_MOVE,R0
	TSTR R0
	BEQ T190
	CLRR R0
	MVO R0,var_POLL_WAIT
T190:
	;[655]     END IF
	SRCFILE "texas.bas",655
T182:
	;[656] 
	SRCFILE "texas.bas",656
	;[657] input_check:
	SRCFILE "texas.bas",657
	; INPUT_CHECK
label_INPUT_CHECK:	;[658]     IF inp_key_hit = 10 THEN GOSUB ingame_menu
	SRCFILE "texas.bas",658
	MVI var_INP_KEY_HIT,R0
	CMPI #10,R0
	BNE T191
	CALL label_INGAME_MENU
T191:
	;[659]     IF inp_key_hit = 11 THEN GOSUB show_purses
	SRCFILE "texas.bas",659
	MVI var_INP_KEY_HIT,R0
	CMPI #11,R0
	BNE T192
	CALL label_SHOW_PURSES
T192:
	;[660]     IF want_leave THEN
	SRCFILE "texas.bas",660
	MVI var_WANT_LEAVE,R0
	TSTR R0
	BEQ T193
	;[661]         want_leave = 0
	SRCFILE "texas.bas",661
	CLRR R0
	MVO R0,var_WANT_LEAVE
	;[662]         GOTO table_select
	SRCFILE "texas.bas",662
	B label_TABLE_SELECT
	;[663]     END IF
	SRCFILE "texas.bas",663
T193:
	;[664] 
	SRCFILE "texas.bas",664
	;[665]     GOTO game_loop
	SRCFILE "texas.bas",665
	B label_GAME_LOOP
	;[666] 
	SRCFILE "texas.bas",666
	;[667] ' ===========================================================================
	SRCFILE "texas.bas",667
	;[668] ' render_game: redraw the table from the Game struct in FN_RX.
	SRCFILE "texas.bas",668
	;[669] '
	SRCFILE "texas.bas",669
	;[670] ' IntyBASIC/the STIC have no true page-flip (unlike the C clients' Apple2/
	SRCFILE "texas.bas",670
	;[671] ' C64 double buffer or CoCo/MSX's SINGLE_BUFFER differential-only mode) --
	SRCFILE "texas.bas",671
	;[672] ' BACKTAB is read live every frame, so a CLS visibly blanks the screen for
	SRCFILE "texas.bas",672
	;[673] ' a frame before the redraw lands. Since state only changes ~once per poll
	SRCFILE "texas.bas",673
	;[674] ' (not per frame), the fix that matters is simply not clearing the whole
	SRCFILE "texas.bas",674
	;[675] ' screen on every poll: a full CLS only happens on the first render after
	SRCFILE "texas.bas",675
	;[676] ' entering the game, or when the player count or hand round regresses
	SRCFILE "texas.bas",676
	;[677] ' (i.e. a new hand started) -- both mean the previous frame's layout is no
	SRCFILE "texas.bas",677
	;[678] ' longer valid. Every other poll only touches the specific cells whose
	SRCFILE "texas.bas",678
	;[679] ' values can actually change (pot digits, bet digits, name/card cells,
	SRCFILE "texas.bas",679
	;[680] ' community board, street label, status row), matching the CoCo/MSX
	SRCFILE "texas.bas",680
	;[681] ' approach since we're in the same no-real-double-buffer boat they were.
	SRCFILE "texas.bas",681
	;[682] '
	SRCFILE "texas.bas",682
	;[683] ' Center layout (all inside the c6-13 corridor no seat's art reaches):
	SRCFILE "texas.bas",683
	;[684] '   row 3   cells  66-73   street label
	SRCFILE "texas.bas",684
	;[685] '   row 4-5 cells  87-91   community cards (tops r4, suit bottoms r5)
	SRCFILE "texas.bas",685
	;[686] '   row 6   cells 127-131  "$" + 4-digit pot
	SRCFILE "texas.bas",686
	;[687] '   row 7   cells 147-151  "P" + 4-digit purse
	SRCFILE "texas.bas",687
	;[688] ' ---------------------------------------------------------------------------
	SRCFILE "texas.bas",688
	;[689] render_game: PROCEDURE
	SRCFILE "texas.bas",689
	; RENDER_GAME
label_RENDER_GAME:	PROC
	BEGIN
	;[690]     round = PEEK(FN_RX + GAME_ROUND) AND 255
	SRCFILE "texas.bas",690
	MVI 40337,R0
	MVO R0,var_ROUND
	;[691]     tmp_pc = PEEK(FN_RX + GAME_PLAYERCOUNT) AND 255
	SRCFILE "texas.bas",691
	MVI 40420,R0
	MVO R0,var_TMP_PC
	;[692] 
	SRCFILE "texas.bas",692
	;[693]     IF (tmp_pc <> prev_playercount) OR (round < prev_round) OR force_redraw THEN
	SRCFILE "texas.bas",693
	MVI var_TMP_PC,R0
	CMP var_PREV_PLAYERCOUNT,R0
	MVII #65535,R0
	BNE T195
	INCR R0
T195:
	MVI var_ROUND,R1
	CMP var_PREV_ROUND,R1
	MVII #65535,R1
	BLT T196
	INCR R1
T196:
	COMR R1
	ANDR R1,R0
	COMR R1
	XORR R1,R0
	MVI var_FORCE_REDRAW,R4
	COMR R4
	ANDR R4,R0
	XOR var_FORCE_REDRAW,R0
	BEQ T194
	;[694]         CLS
	SRCFILE "texas.bas",694
	CALL CLRSCR
	;[695]         GOSUB fill_bg
	SRCFILE "texas.bas",695
	CALL label_FILL_BG
	;[696]         ' Center block, rows 6-7: pot ("$" + value) and your own purse ("P"
	SRCFILE "texas.bas",696
	;[697]         ' + value) stacked directly beneath it, both pushed down two rows
	SRCFILE "texas.bas",697
	;[698]         ' from where 5 Card Stud kept them so the community board and its
	SRCFILE "texas.bas",698
	;[699]         ' street label own rows 3-5 above.
	SRCFILE "texas.bas",699
	;[700]         PRINT AT 127 COLOR COL_NAME, "$"
	SRCFILE "texas.bas",700
	MVII #639,R0
	MVO R0,_screen
	MVII #8199,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #32,R0
	XOR _color,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[701]         PRINT AT 147 COLOR COL_NAME, "P"
	SRCFILE "texas.bas",701
	MVII #659,R0
	MVO R0,_screen
	MVII #8199,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #384,R0
	XOR _color,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[702]         #prev_pot = 65535   ' force the pot to redraw too on a full layout reset
	SRCFILE "texas.bas",702
	MVII #65535,R0
	MVO R0,var_&PREV_POT
	;[703]         #prev_purse = 65535 ' likewise for purse
	SRCFILE "texas.bas",703
	MVO R0,var_&PREV_PURSE
	;[704]         street_redraw = 1   ' the CLS wiped the label; force_redraw is consumed
	SRCFILE "texas.bas",704
	MVII #1,R0
	MVO R0,var_STREET_REDRAW
	;[705]                             ' right below, so capture the need-to-redraw here
	SRCFILE "texas.bas",705
	;[706]         force_redraw = 0
	SRCFILE "texas.bas",706
	CLRR R0
	MVO R0,var_FORCE_REDRAW
	;[707]         ' A new hand means every seat's hand -- and the community board --
	SRCFILE "texas.bas",707
	;[708]         ' is starting over. Without this, a seat that had cards last hand
	SRCFILE "texas.bas",708
	;[709]         ' would treat this hand's first cards as "already dealt" and skip
	SRCFILE "texas.bas",709
	;[710]         ' animating them, and the next flop would land silently.
	SRCFILE "texas.bas",710
	;[711]         IF round < prev_round THEN
	SRCFILE "texas.bas",711
	MVI var_ROUND,R0
	CMP var_PREV_ROUND,R0
	BGE T197
	;[712]             FOR gs_i = 0 TO 7
	SRCFILE "texas.bas",712
	CLRR R0
	MVO R0,var_GS_I
T198:
	;[713]                 prev_cards(gs_i) = 0
	SRCFILE "texas.bas",713
	CLRR R0
	MVII #array_PREV_CARDS,R3
	ADD var_GS_I,R3
	MVO@ R0,R3
	;[714]             NEXT gs_i
	SRCFILE "texas.bas",714
	MVI var_GS_I,R0
	INCR R0
	MVO R0,var_GS_I
	CMPI #7,R0
	BLE T198
	;[715]             prev_community = 0
	SRCFILE "texas.bas",715
	CLRR R0
	MVO R0,var_PREV_COMMUNITY
	;[716]         END IF
	SRCFILE "texas.bas",716
T197:
	;[717]     END IF
	SRCFILE "texas.bas",717
T194:
	;[718] 
	SRCFILE "texas.bas",718
	;[719]     ' prev_playercount=255 is the boot sentinel (first render ever) -- skip
	SRCFILE "texas.bas",719
	;[720]     ' the join/leave cue then, there's nothing to compare against yet.
	SRCFILE "texas.bas",720
	;[721]     IF prev_playercount <> 255 THEN
	SRCFILE "texas.bas",721
	MVI var_PREV_PLAYERCOUNT,R0
	CMPI #255,R0
	BEQ T199
	;[722]         IF tmp_pc > prev_playercount THEN GOSUB sound_player_join
	SRCFILE "texas.bas",722
	MVI var_TMP_PC,R0
	CMP var_PREV_PLAYERCOUNT,R0
	BLE T200
	CALL label_SOUND_PLAYER_JOIN
T200:
	;[723]         IF tmp_pc < prev_playercount THEN GOSUB sound_player_left
	SRCFILE "texas.bas",723
	MVI var_TMP_PC,R0
	CMP var_PREV_PLAYERCOUNT,R0
	BGE T201
	CALL label_SOUND_PLAYER_LEFT
T201:
	;[724]     END IF
	SRCFILE "texas.bas",724
T199:
	;[725]     IF round < prev_round THEN GOSUB sound_deal
	SRCFILE "texas.bas",725
	MVI var_ROUND,R0
	CMP var_PREV_ROUND,R0
	BGE T202
	CALL label_SOUND_DEAL
T202:
	;[726]     IF round <> prev_round THEN street_redraw = 1
	SRCFILE "texas.bas",726
	MVI var_ROUND,R0
	CMP var_PREV_ROUND,R0
	BEQ T203
	MVII #1,R0
	MVO R0,var_STREET_REDRAW
T203:
	;[727] 
	SRCFILE "texas.bas",727
	;[728]     prev_playercount = tmp_pc
	SRCFILE "texas.bas",728
	MVI var_TMP_PC,R0
	MVO R0,var_PREV_PLAYERCOUNT
	;[729]     prev_round = round
	SRCFILE "texas.bas",729
	MVI var_ROUND,R0
	MVO R0,var_PREV_ROUND
	;[730] 
	SRCFILE "texas.bas",730
	;[731]     ' Street label, row 3 centered above the community board. street_names
	SRCFILE "texas.bas",731
	;[732]     ' is 8 space-padded bytes per round value (round already validated <= 5
	SRCFILE "texas.bas",732
	;[733]     ' before render_game runs), so drawing it both writes the new label and
	SRCFILE "texas.bas",733
	;[734]     ' blanks the remainder of the field -- no stale text possible.
	SRCFILE "texas.bas",734
	;[735]     IF street_redraw THEN
	SRCFILE "texas.bas",735
	MVI var_STREET_REDRAW,R0
	TSTR R0
	BEQ T204
	;[736]         #df_src = VARPTR street_names(0) + round * 8
	SRCFILE "texas.bas",736
	MVII #label_STREET_NAMES,R0
	MVI var_ROUND,R1
	SLL R1,2
	ADDR R1,R1
	ADDR R1,R0
	MVO R0,var_&DF_SRC
	;[737]         df_pos = 66 : df_len = 8 : #df_color = COL_NAME
	SRCFILE "texas.bas",737
	MVII #66,R0
	MVO R0,var_DF_POS
	MVII #8,R0
	MVO R0,var_DF_LEN
	MVII #8199,R0
	MVO R0,var_&DF_COLOR
	;[738]         GOSUB draw_field
	SRCFILE "texas.bas",738
	CALL label_DRAW_FIELD
	;[739]         street_redraw = 0
	SRCFILE "texas.bas",739
	CLRR R0
	MVO R0,var_STREET_REDRAW
	;[740]     END IF
	SRCFILE "texas.bas",740
T204:
	;[741] 
	SRCFILE "texas.bas",741
	;[742]     ' Real hardware/accurate emulation only guarantees a BACKTAB write is
	SRCFILE "texas.bas",742
	;[743]     ' tear-free if it lands within the vblank window; a full-table redraw
	SRCFILE "texas.bas",743
	;[744]     ' (dozens of cells plus several PRINT calls, each involving a slow
	SRCFILE "texas.bas",744
	;[745]     ' division loop for the digits) can run long enough to spill into
	SRCFILE "texas.bas",745
	;[746]     ' active display, and a live screenshot can catch that half-written
	SRCFILE "texas.bas",746
	;[747]     ' state -- seen as a stray non-digit glyph where only a digit could
	SRCFILE "texas.bas",747
	;[748]     ' ever legitimately be. Skipping the PRINT entirely when the value
	SRCFILE "texas.bas",748
	;[749]     ' hasn't changed since the last poll is what keeps the common-case
	SRCFILE "texas.bas",749
	;[750]     ' redraw (most fields static from one poll to the next) small enough
	SRCFILE "texas.bas",750
	;[751]     ' to actually fit in one vblank, rather than trying to chase tearing
	SRCFILE "texas.bas",751
	;[752]     ' after the fact.
	SRCFILE "texas.bas",752
	;[753]     #tmp_num = u16be(FN_RX + GAME_POT)
	SRCFILE "texas.bas",753
	MVI 40339,R0
	ANDI #255,R0
	SWAP R0
	ANDI #65280,R0
	MVI 40338,R1
	ANDI #255,R1
	ADDR R1,R0
	MVO R0,var_&TMP_NUM
	;[754]     IF #tmp_num <> #prev_pot THEN
	SRCFILE "texas.bas",754
	CMP var_&PREV_POT,R0
	BEQ T205
	;[755]         IF #tmp_num > #prev_pot AND #prev_pot <> 65535 THEN GOSUB sound_chip
	SRCFILE "texas.bas",755
	CMP var_&PREV_POT,R0
	MVII #65535,R0
	BGT T207
	INCR R0
T207:
	MVI var_&PREV_POT,R1
	CMPI #65535,R1
	MVII #65535,R1
	BNE T208
	INCR R1
T208:
	ANDR R1,R0
	BEQ T206
	CALL label_SOUND_CHIP
T206:
	;[756]         PRINT AT 128 COLOR COL_NAME, <.4>#tmp_num
	SRCFILE "texas.bas",756
	MVII #640,R0
	MVO R0,_screen
	MVII #8199,R0
	MVO R0,_color
	MVI var_&TMP_NUM,R0
	MVII #4,R2
	MVI _color,R3
	MVI _screen,R4
	CALL PRNUM16.b
	MVO R4,_screen
	;[757]         #prev_pot = #tmp_num
	SRCFILE "texas.bas",757
	MVI var_&TMP_NUM,R0
	MVO R0,var_&PREV_POT
	;[758]     END IF
	SRCFILE "texas.bas",758
T205:
	;[759] 
	SRCFILE "texas.bas",759
	;[760]     ' Your own purse (wire index 0 is always you, per the server's rotation
	SRCFILE "texas.bas",760
	;[761]     ' -- see state.bas), directly under the pot.
	SRCFILE "texas.bas",761
	;[762]     #tmp_num = u16be(player_addr(0) + PL_PURSE)
	SRCFILE "texas.bas",762
	MVI 40442,R0
	ANDI #255,R0
	SWAP R0
	ANDI #65280,R0
	MVI 40441,R1
	ANDI #255,R1
	ADDR R1,R0
	MVO R0,var_&TMP_NUM
	;[763]     IF #tmp_num <> #prev_purse THEN
	SRCFILE "texas.bas",763
	CMP var_&PREV_PURSE,R0
	BEQ T209
	;[764]         PRINT AT 148 COLOR COL_NAME, <.4>#tmp_num
	SRCFILE "texas.bas",764
	MVII #660,R0
	MVO R0,_screen
	MVII #8199,R0
	MVO R0,_color
	MVI var_&TMP_NUM,R0
	MVII #4,R2
	MVI _color,R3
	MVI _screen,R4
	CALL PRNUM16.b
	MVO R4,_screen
	;[765]         #prev_purse = #tmp_num
	SRCFILE "texas.bas",765
	MVI var_&TMP_NUM,R0
	MVO R0,var_&PREV_PURSE
	;[766]     END IF
	SRCFILE "texas.bas",766
T209:
	;[767] 
	SRCFILE "texas.bas",767
	;[768]     ' Community board: up to 5 cards, drawn every poll exactly like the
	SRCFILE "texas.bas",768
	;[769]     ' seat hands below (so the flop/turn/river land in place without a
	SRCFILE "texas.bas",769
	;[770]     ' CLS); only the deal click is gated on prev_community. The scan bound
	SRCFILE "texas.bas",770
	;[771]     ' is 5 slots (offsets 87-96 -- byte 97 is the field's NUL, never a 6th
	SRCFILE "texas.bas",771
	;[772]     ' card), and cards fill contiguously from index 0, so the count dealt
	SRCFILE "texas.bas",772
	;[773]     ' is 1 + the highest nonzero index.
	SRCFILE "texas.bas",773
	;[774]     deal_count = 0
	SRCFILE "texas.bas",774
	CLRR R0
	MVO R0,var_DEAL_COUNT
	;[775]     FOR mv_sel = 0 TO 4
	SRCFILE "texas.bas",775
	MVO R0,var_MV_SEL
T210:
	;[776]         card = PEEK(FN_RX + GAME_COMMUNITY + mv_sel * 2) AND 255
	SRCFILE "texas.bas",776
	MVI var_MV_SEL,R1
	SLL R1,1
	ADDI #40343,R1
	MVI@ R1,R0
	MVO R0,var_CARD
	;[777]         IF card <> 0 THEN deal_count = mv_sel + 1
	SRCFILE "texas.bas",777
	MVI var_CARD,R0
	TSTR R0
	BEQ T211
	MVI var_MV_SEL,R0
	INCR R0
	MVO R0,var_DEAL_COUNT
T211:
	;[778]     NEXT mv_sel
	SRCFILE "texas.bas",778
	MVI var_MV_SEL,R0
	INCR R0
	MVO R0,var_MV_SEL
	CMPI #4,R0
	BLE T210
	;[779]     ' The board can shrink without an intervening CLS: the server sends a
	SRCFILE "texas.bas",779
	;[780]     ' masked "??" board in some transitional states (seen live: one card
	SRCFILE "texas.bas",780
	;[781]     ' back drawn at pre-flop right after joining a table mid-hand), and
	SRCFILE "texas.bas",781
	;[782]     ' once the wire reverts to empty the draw loop below simply stops at
	SRCFILE "texas.bas",782
	;[783]     ' deal_count -- nothing else ever touches the leftover cells. Blank
	SRCFILE "texas.bas",783
	;[784]     ' any cell we drew last poll that has no card this poll back to felt
	SRCFILE "texas.bas",784
	;[785]     ' (same bare color-word idiom as fill_bg).
	SRCFILE "texas.bas",785
	;[786]     IF deal_count < prev_community THEN
	SRCFILE "texas.bas",786
	MVI var_DEAL_COUNT,R0
	CMP var_PREV_COMMUNITY,R0
	BGE T212
	;[787]         FOR mv_sel = deal_count TO prev_community - 1
	SRCFILE "texas.bas",787
	MVO R0,var_MV_SEL
T213:
	;[788]             #BACKTAB(87 + mv_sel) = COL_NAME
	SRCFILE "texas.bas",788
	MVII #8199,R0
	MVII #Q2+87,R3
	ADD var_MV_SEL,R3
	MVO@ R0,R3
	;[789]             #BACKTAB(107 + mv_sel) = COL_NAME
	SRCFILE "texas.bas",789
	ADDI #20,R3
	MVO@ R0,R3
	;[790]         NEXT mv_sel
	SRCFILE "texas.bas",790
	MVI var_MV_SEL,R0
	INCR R0
	MVO R0,var_MV_SEL
	MVI var_PREV_COMMUNITY,R1
	DECR R1
	CMPR R1,R0
	BLE T213
	;[791]     END IF
	SRCFILE "texas.bas",791
T212:
	;[792]     FOR mv_sel = 0 TO deal_count - 1
	SRCFILE "texas.bas",792
	CLRR R0
	MVO R0,var_MV_SEL
T214:
	;[793]         card = PEEK(FN_RX + GAME_COMMUNITY + mv_sel * 2) AND 255
	SRCFILE "texas.bas",793
	MVI var_MV_SEL,R1
	SLL R1,1
	ADDI #40343,R1
	MVI@ R1,R0
	MVO R0,var_CARD
	;[794]         suit = PEEK(FN_RX + GAME_COMMUNITY + mv_sel * 2 + 1) AND 255
	SRCFILE "texas.bas",794
	MVI var_MV_SEL,R1
	SLL R1,1
	ADDI #40344,R1
	MVI@ R1,R0
	MVO R0,var_SUIT
	;[795]         IF mv_sel >= prev_community THEN GOSUB sound_deal
	SRCFILE "texas.bas",795
	MVI var_MV_SEL,R0
	CMP var_PREV_COMMUNITY,R0
	BLT T215
	CALL label_SOUND_DEAL
T215:
	;[796]         conv_in = card : GOSUB card_from_ascii : card = conv_out
	SRCFILE "texas.bas",796
	MVI var_CARD,R0
	MVO R0,var_CONV_IN
	CALL label_CARD_FROM_ASCII
	MVI var_CONV_OUT,R0
	MVO R0,var_CARD
	;[797]         conv_in = suit : GOSUB suit_from_ascii : suit = conv_out
	SRCFILE "texas.bas",797
	MVI var_SUIT,R0
	MVO R0,var_CONV_IN
	CALL label_SUIT_FROM_ASCII
	MVI var_CONV_OUT,R0
	MVO R0,var_SUIT
	;[798]         p = 87 + mv_sel
	SRCFILE "texas.bas",798
	MVI var_MV_SEL,R0
	ADDI #87,R0
	MVO R0,var_P
	;[799]         GOSUB print_card
	SRCFILE "texas.bas",799
	CALL label_PRINT_CARD
	;[800]     NEXT mv_sel
	SRCFILE "texas.bas",800
	MVI var_MV_SEL,R0
	INCR R0
	MVO R0,var_MV_SEL
	MVI var_DEAL_COUNT,R1
	DECR R1
	CMPR R1,R0
	BLE T214
	;[801]     prev_community = deal_count
	SRCFILE "texas.bas",801
	MVI var_DEAL_COUNT,R0
	MVO R0,var_PREV_COMMUNITY
	;[802]     ' Same one-vblank-budget reasoning as the per-seat WAIT below: yield a
	SRCFILE "texas.bas",802
	;[803]     ' frame after the board so a flop's 5 fresh cells plus the seat loop's
	SRCFILE "texas.bas",803
	;[804]     ' first seat can't pile into the same vblank.
	SRCFILE "texas.bas",804
	;[805]     WAIT
	SRCFILE "texas.bas",805
	CALL _wait
	;[806] 
	SRCFILE "texas.bas",806
	;[807]     gs_j = tmp_pc - 2
	SRCFILE "texas.bas",807
	MVI var_TMP_PC,R0
	SUBI #2,R0
	MVO R0,var_GS_J
	;[808]     IF gs_j < 0 THEN gs_j = 0
	SRCFILE "texas.bas",808
	MVI var_GS_J,R0
	CMPI #0,R0
	BGE T216
	CLRR R0
	MVO R0,var_GS_J
T216:
	;[809]     IF gs_j > 6 THEN gs_j = 6
	SRCFILE "texas.bas",809
	MVI var_GS_J,R0
	CMPI #6,R0
	BLE T217
	MVII #6,R0
	MVO R0,var_GS_J
T217:
	;[810] 
	SRCFILE "texas.bas",810
	;[811]     FOR gs_i = 0 TO tmp_pc - 1
	SRCFILE "texas.bas",811
	CLRR R0
	MVO R0,var_GS_I
T218:
	;[812]         sel_seat = PEEK(VARPTR seatmap(0) + gs_j * 8 + gs_i) AND 255
	SRCFILE "texas.bas",812
	MVII #label_SEATMAP,R1
	MVI var_GS_J,R2
	SLL R2,2
	ADDR R2,R2
	ADDR R2,R1
	ADD var_GS_I,R1
	MVI@ R1,R0
	MVO R0,var_SEL_SEAT
	;[813]         IF sel_seat <> 255 THEN
	SRCFILE "texas.bas",813
	MVI var_SEL_SEAT,R0
	CMPI #255,R0
	BEQ T219
	;[814]             sel_i = PEEK(VARPTR seat_name_off(0) + sel_seat) AND 255
	SRCFILE "texas.bas",814
	MVII #label_SEAT_NAME_OFF,R3
	ADDR R0,R3
	MVI@ R3,R0
	MVO R0,var_SEL_I
	;[815] 
	SRCFILE "texas.bas",815
	;[816]             #gs_c = COL_NAME
	SRCFILE "texas.bas",816
	MVII #8199,R0
	MVO R0,var_&GS_C
	;[817]             IF gs_i = active_player THEN #gs_c = COL_HILITE
	SRCFILE "texas.bas",817
	MVI 40340,R0
	ANDI #255,R0
	CMPI #255,R0
	MVII #65535,R0
	BEQ T221
	INCR R0
T221:
	MVII #65280,R5
	CLRR R4
	CLRC
	RRC R0,1
	BEQ T223
T222:
	BNC T224
	ADDR R5,R4
T224:
	ADDR R5,R5
	SARC R0,1
	BNE T222
T223:
	BNC T225
	ADDR R5,R4
T225:
	MOVR R4,R0
	MVI 40340,R1
	ANDI #255,R1
	ADDR R1,R0
	MVI var_GS_I,R1
	CMPR R1,R0
	BNE T220
	MVII #8198,R0
	MVO R0,var_&GS_C
T220:
	;[818] 
	SRCFILE "texas.bas",818
	;[819]             #tmp_addr = player_addr(gs_i)
	SRCFILE "texas.bas",819
	MVI var_GS_I,R0
	MULT R0,R4,33
	ADDI #40421,R0
	MVO R0,var_&TMP_ADDR
	;[820]             #df_src = #tmp_addr + PL_NAME : df_pos = sel_i : df_len = 4 : #df_color = #gs_c
	SRCFILE "texas.bas",820
	MVO R0,var_&DF_SRC
	MVI var_SEL_I,R0
	MVO R0,var_DF_POS
	MVII #4,R0
	MVO R0,var_DF_LEN
	MVI var_&GS_C,R0
	MVO R0,var_&DF_COLOR
	;[821]             GOSUB draw_field
	SRCFILE "texas.bas",821
	CALL label_DRAW_FIELD
	;[822] 
	SRCFILE "texas.bas",822
	;[823]             #tmp_num = u16be(#tmp_addr + PL_BET)
	SRCFILE "texas.bas",823
	MVI var_&TMP_ADDR,R1
	ADDI #11,R1
	MVI@ R1,R0
	ANDI #255,R0
	SWAP R0
	ANDI #65280,R0
	MVI var_&TMP_ADDR,R1
	ADDI #10,R1
	MVI@ R1,R1
	ANDI #255,R1
	ADDR R1,R0
	MVO R0,var_&TMP_NUM
	;[824]             ' Clamp to 99: the bet field is 2 cells wide (a 3-digit PRINT
	SRCFILE "texas.bas",824
	;[825]             ' would spill a digit past it -- for the right-edge seats,
	SRCFILE "texas.bas",825
	;[826]             ' whose bet sits in the row's last 2 columns, that digit wraps
	SRCFILE "texas.bas",826
	;[827]             ' to the next row on top of another seat's card cell), and it
	SRCFILE "texas.bas",827
	;[828]             ' keeps the value inside prev_bet's 8-bit range for the
	SRCFILE "texas.bas",828
	;[829]             ' change-detection compare. Hold'em raises pass 100 routinely,
	SRCFILE "texas.bas",829
	;[830]             ' unlike 5 Card Stud where this was only latent.
	SRCFILE "texas.bas",830
	;[831]             IF #tmp_num > 99 THEN #tmp_num = 99
	SRCFILE "texas.bas",831
	CMPI #99,R0
	BLE T226
	MVII #99,R0
	MVO R0,var_&TMP_NUM
T226:
	;[832]             IF #tmp_num <> prev_bet(sel_seat) THEN
	SRCFILE "texas.bas",832
	MVI var_&TMP_NUM,R0
	MVII #array_PREV_BET,R3
	ADD var_SEL_SEAT,R3
	CMP@ R3,R0
	BEQ T227
	;[833]                 PRINT AT sel_i + 4 COLOR #gs_c, <2>#tmp_num
	SRCFILE "texas.bas",833
	MVI var_SEL_I,R0
	ADDI #516,R0
	MVO R0,_screen
	MVI var_&GS_C,R0
	MVO R0,_color
	MVI var_&TMP_NUM,R0
	MVII #2,R2
	MVI _color,R3
	MVI _screen,R4
	CALL PRNUM16.z
	MVO R4,_screen
	;[834]                 prev_bet(sel_seat) = #tmp_num
	SRCFILE "texas.bas",834
	MVI var_&TMP_NUM,R0
	MVII #array_PREV_BET,R3
	ADD var_SEL_SEAT,R3
	MVO@ R0,R3
	;[835]             END IF
	SRCFILE "texas.bas",835
T227:
	;[836] 
	SRCFILE "texas.bas",836
	;[837]             ' Hole cards (2 in Hold'em) fill the hand contiguously from
	SRCFILE "texas.bas",837
	;[838]             ' index 0 (never a gap), so the count currently dealt is just
	SRCFILE "texas.bas",838
	;[839]             ' 1 + the highest nonzero index. Comparing that against what
	SRCFILE "texas.bas",839
	;[840]             ' this seat showed last poll (prev_cards) is what tells a
	SRCFILE "texas.bas",840
	;[841]             ' genuinely new card apart from one we've already drawn on
	SRCFILE "texas.bas",841
	;[842]             ' every previous poll.
	SRCFILE "texas.bas",842
	;[843]             deal_count = 0
	SRCFILE "texas.bas",843
	CLRR R0
	MVO R0,var_DEAL_COUNT
	;[844]             FOR mv_sel = 0 TO 1
	SRCFILE "texas.bas",844
	MVO R0,var_MV_SEL
T228:
	;[845]                 card = PEEK(#tmp_addr + PL_HAND + mv_sel * 2) AND 255
	SRCFILE "texas.bas",845
	MVI var_&TMP_ADDR,R1
	ADDI #22,R1
	MVI var_MV_SEL,R2
	SLL R2,1
	ADDR R2,R1
	MVI@ R1,R0
	MVO R0,var_CARD
	;[846]                 IF card <> 0 THEN deal_count = mv_sel + 1
	SRCFILE "texas.bas",846
	MVI var_CARD,R0
	TSTR R0
	BEQ T229
	MVI var_MV_SEL,R0
	INCR R0
	MVO R0,var_DEAL_COUNT
T229:
	;[847]             NEXT mv_sel
	SRCFILE "texas.bas",847
	MVI var_MV_SEL,R0
	INCR R0
	MVO R0,var_MV_SEL
	CMPI #1,R0
	BLE T228
	;[848] 
	SRCFILE "texas.bas",848
	;[849]             ' Same shrink-without-CLS gap as the community board above: a
	SRCFILE "texas.bas",849
	;[850]             ' fold shrinks "????" (2 backs) to "??" (1 back), and the
	SRCFILE "texas.bas",850
	;[851]             ' draw loop below would leave the second back on screen
	SRCFILE "texas.bas",851
	;[852]             ' forever. Blank the cells this seat showed last poll but not
	SRCFILE "texas.bas",852
	;[853]             ' this one.
	SRCFILE "texas.bas",853
	;[854]             IF deal_count < prev_cards(sel_seat) THEN
	SRCFILE "texas.bas",854
	MVI var_DEAL_COUNT,R0
	MVII #array_PREV_CARDS,R3
	ADD var_SEL_SEAT,R3
	CMP@ R3,R0
	BGE T230
	;[855]                 FOR mv_sel = deal_count TO prev_cards(sel_seat) - 1
	SRCFILE "texas.bas",855
	MVO R0,var_MV_SEL
T231:
	;[856]                     #BACKTAB(sel_i + 20 + mv_sel) = COL_NAME
	SRCFILE "texas.bas",856
	MVII #Q2,R0
	MVI var_SEL_I,R1
	ADDI #20,R1
	ADD var_MV_SEL,R1
	ADDR R1,R0
	MVII #8199,R1
	MOVR R0,R4
	MVO@ R1,R4
	;[857]                     #BACKTAB(sel_i + 40 + mv_sel) = COL_NAME
	SRCFILE "texas.bas",857
	MVII #Q2,R0
	MVI var_SEL_I,R1
	ADDI #40,R1
	ADD var_MV_SEL,R1
	ADDR R1,R0
	MVII #8199,R1
	MOVR R0,R4
	MVO@ R1,R4
	;[858]                 NEXT mv_sel
	SRCFILE "texas.bas",858
	MVI var_MV_SEL,R0
	INCR R0
	MVO R0,var_MV_SEL
	MVII #array_PREV_CARDS,R3
	ADD var_SEL_SEAT,R3
	MVI@ R3,R1
	DECR R1
	CMPR R1,R0
	BLE T231
	;[859]             END IF
	SRCFILE "texas.bas",859
T230:
	;[860] 
	SRCFILE "texas.bas",860
	;[861]             FOR mv_sel = 0 TO deal_count - 1
	SRCFILE "texas.bas",861
	CLRR R0
	MVO R0,var_MV_SEL
T232:
	;[862]                 card = PEEK(#tmp_addr + PL_HAND + mv_sel * 2) AND 255
	SRCFILE "texas.bas",862
	MVI var_&TMP_ADDR,R1
	ADDI #22,R1
	MVI var_MV_SEL,R2
	SLL R2,1
	ADDR R2,R1
	MVI@ R1,R0
	MVO R0,var_CARD
	;[863]                 suit = PEEK(#tmp_addr + PL_HAND + mv_sel * 2 + 1) AND 255
	SRCFILE "texas.bas",863
	MVI var_&TMP_ADDR,R1
	ADDI #22,R1
	MVI var_MV_SEL,R2
	SLL R2,1
	ADDR R2,R1
	INCR R1
	MVI@ R1,R0
	MVO R0,var_SUIT
	;[864]                 ' A card index this seat hasn't shown before is a fresh
	SRCFILE "texas.bas",864
	;[865]                 ' deal -- the click (and its own built-in pause) stands in
	SRCFILE "texas.bas",865
	;[866]                 ' for the "card landing on the table" beat, instead of
	SRCFILE "texas.bas",866
	;[867]                 ' every new card just popping in silently and instantly
	SRCFILE "texas.bas",867
	;[868]                 ' like the C clients' animated deal never happens here.
	SRCFILE "texas.bas",868
	;[869]                 IF mv_sel >= prev_cards(sel_seat) THEN GOSUB sound_deal
	SRCFILE "texas.bas",869
	MVI var_MV_SEL,R0
	MVII #array_PREV_CARDS,R3
	ADD var_SEL_SEAT,R3
	CMP@ R3,R0
	BLT T233
	CALL label_SOUND_DEAL
T233:
	;[870]                 ' card=0/suit=0 after conversion (an unrecognized wire
	SRCFILE "texas.bas",870
	;[871]                 ' char, e.g. "??" for a folded/masked hand) is itself a
	SRCFILE "texas.bas",871
	;[872]                 ' valid "hidden" input to print_card -- draws the card-
	SRCFILE "texas.bas",872
	;[873]                 ' back glyph, which is what keeps a folded/masked card
	SRCFILE "texas.bas",873
	;[874]                 ' from leaving stale rank art on screen instead of just
	SRCFILE "texas.bas",874
	;[875]                 ' going quiet. The showdown flip needs no code at all:
	SRCFILE "texas.bas",875
	;[876]                 ' the server swaps "????" for the real chars in this
	SRCFILE "texas.bas",876
	;[877]                 ' response and this same loop redraws whatever arrives.
	SRCFILE "texas.bas",877
	;[878]                 conv_in = card : GOSUB card_from_ascii : card = conv_out
	SRCFILE "texas.bas",878
	MVI var_CARD,R0
	MVO R0,var_CONV_IN
	CALL label_CARD_FROM_ASCII
	MVI var_CONV_OUT,R0
	MVO R0,var_CARD
	;[879]                 conv_in = suit : GOSUB suit_from_ascii : suit = conv_out
	SRCFILE "texas.bas",879
	MVI var_SUIT,R0
	MVO R0,var_CONV_IN
	CALL label_SUIT_FROM_ASCII
	MVI var_CONV_OUT,R0
	MVO R0,var_SUIT
	;[880]                 p = sel_i + 20 + mv_sel
	SRCFILE "texas.bas",880
	MVI var_SEL_I,R0
	ADDI #20,R0
	ADD var_MV_SEL,R0
	MVO R0,var_P
	;[881]                 GOSUB print_card
	SRCFILE "texas.bas",881
	CALL label_PRINT_CARD
	;[882]             NEXT mv_sel
	SRCFILE "texas.bas",882
	MVI var_MV_SEL,R0
	INCR R0
	MVO R0,var_MV_SEL
	MVI var_DEAL_COUNT,R1
	DECR R1
	CMPR R1,R0
	BLE T232
	;[883]             prev_cards(sel_seat) = deal_count
	SRCFILE "texas.bas",883
	MVI var_DEAL_COUNT,R0
	MVII #array_PREV_CARDS,R3
	ADD var_SEL_SEAT,R3
	MVO@ R0,R3
	;[884] 
	SRCFILE "texas.bas",884
	;[885]             ' One seat's worth of pokes (name + bet digits + 2 cards) is
	SRCFILE "texas.bas",885
	;[886]             ' small enough to reliably land within a single vblank; the
	SRCFILE "texas.bas",886
	;[887]             ' full ~8-seat redraw as one unbroken burst isn't, and that's
	SRCFILE "texas.bas",887
	;[888]             ' what let a screenshot catch a genuinely half-written frame
	SRCFILE "texas.bas",888
	;[889]             ' (garbage that looked like data corruption but wasn't -- nothing
	SRCFILE "texas.bas",889
	;[890]             ' in FN_RX was wrong, the *display* was mid-update). Yielding a
	SRCFILE "texas.bas",890
	;[891]             ' frame between seats bounds the tear to at most one seat's
	SRCFILE "texas.bas",891
	;[892]             ' fields at a time instead of the whole table, at the cost of
	SRCFILE "texas.bas",892
	;[893]             ' a full new-hand redraw taking up to ~8 extra frames (moot;
	SRCFILE "texas.bas",893
	;[894]             ' that only happens once per hand, not every poll).
	SRCFILE "texas.bas",894
	;[895]             WAIT
	SRCFILE "texas.bas",895
	CALL _wait
	;[896]         END IF
	SRCFILE "texas.bas",896
T219:
	;[897]     NEXT gs_i
	SRCFILE "texas.bas",897
	MVI var_GS_I,R0
	INCR R0
	MVO R0,var_GS_I
	MVI var_TMP_PC,R1
	DECR R1
	CMPR R1,R0
	BLE T218
	;[898] 
	SRCFILE "texas.bas",898
	;[899]     GOSUB draw_status
	SRCFILE "texas.bas",899
	CALL label_DRAW_STATUS
	;[900] END
	SRCFILE "texas.bas",900
	RETURN
	ENDP
	;[901] 
	SRCFILE "texas.bas",901
	;[902] ' ---------------------------------------------------------------------------
	SRCFILE "texas.bas",902
	;[903] ' show_purses: while KEYPAD ENTER is held, overwrite every seated player's
	SRCFILE "texas.bas",903
	;[904] ' name cells with their purse value instead. Reuses tmp_pc/seatmap/
	SRCFILE "texas.bas",904
	;[905] ' seat_name_off exactly as render_game's own seat loop does -- tmp_pc is a
	SRCFILE "texas.bas",905
	;[906] ' global left holding the last poll's player count, so this works between
	SRCFILE "texas.bas",906
	;[907] ' polls without needing a fresh network round-trip. Releasing the key just
	SRCFILE "texas.bas",907
	;[908] ' asks for a full redraw on the next poll (the same trick the win-message
	SRCFILE "texas.bas",908
	;[909] ' overlay uses) rather than restoring each name field by hand here.
	SRCFILE "texas.bas",909
	;[910] ' ---------------------------------------------------------------------------
	SRCFILE "texas.bas",910
	;[911] show_purses: PROCEDURE
	SRCFILE "texas.bas",911
	; SHOW_PURSES
label_SHOW_PURSES:	PROC
	BEGIN
	;[912]     gs_j = tmp_pc - 2
	SRCFILE "texas.bas",912
	MVI var_TMP_PC,R0
	SUBI #2,R0
	MVO R0,var_GS_J
	;[913]     IF gs_j < 0 THEN gs_j = 0
	SRCFILE "texas.bas",913
	MVI var_GS_J,R0
	CMPI #0,R0
	BGE T234
	CLRR R0
	MVO R0,var_GS_J
T234:
	;[914]     IF gs_j > 6 THEN gs_j = 6
	SRCFILE "texas.bas",914
	MVI var_GS_J,R0
	CMPI #6,R0
	BLE T235
	MVII #6,R0
	MVO R0,var_GS_J
T235:
	;[915] 
	SRCFILE "texas.bas",915
	;[916]     FOR gs_i = 0 TO tmp_pc - 1
	SRCFILE "texas.bas",916
	CLRR R0
	MVO R0,var_GS_I
T236:
	;[917]         sel_seat = PEEK(VARPTR seatmap(0) + gs_j * 8 + gs_i) AND 255
	SRCFILE "texas.bas",917
	MVII #label_SEATMAP,R1
	MVI var_GS_J,R2
	SLL R2,2
	ADDR R2,R2
	ADDR R2,R1
	ADD var_GS_I,R1
	MVI@ R1,R0
	MVO R0,var_SEL_SEAT
	;[918]         IF sel_seat <> 255 THEN
	SRCFILE "texas.bas",918
	MVI var_SEL_SEAT,R0
	CMPI #255,R0
	BEQ T237
	;[919]             sel_i = PEEK(VARPTR seat_name_off(0) + sel_seat) AND 255
	SRCFILE "texas.bas",919
	MVII #label_SEAT_NAME_OFF,R3
	ADDR R0,R3
	MVI@ R3,R0
	MVO R0,var_SEL_I
	;[920]             #tmp_addr = player_addr(gs_i)
	SRCFILE "texas.bas",920
	MVI var_GS_I,R0
	MULT R0,R4,33
	ADDI #40421,R0
	MVO R0,var_&TMP_ADDR
	;[921]             #tmp_num = u16be(#tmp_addr + PL_PURSE)
	SRCFILE "texas.bas",921
	MOVR R0,R1
	ADDI #21,R1
	MVI@ R1,R0
	ANDI #255,R0
	SWAP R0
	ANDI #65280,R0
	MVI var_&TMP_ADDR,R1
	ADDI #20,R1
	MVI@ R1,R1
	ANDI #255,R1
	ADDR R1,R0
	MVO R0,var_&TMP_NUM
	;[922]             IF #tmp_num > 9999 THEN #tmp_num = 9999
	SRCFILE "texas.bas",922
	CMPI #9999,R0
	BLE T238
	MVII #9999,R0
	MVO R0,var_&TMP_NUM
T238:
	;[923]             PRINT AT sel_i COLOR COL_HILITE, <.4>#tmp_num
	SRCFILE "texas.bas",923
	MVI var_SEL_I,R0
	ADDI #512,R0
	MVO R0,_screen
	MVII #8198,R0
	MVO R0,_color
	MVI var_&TMP_NUM,R0
	MVII #4,R2
	MVI _color,R3
	MVI _screen,R4
	CALL PRNUM16.b
	MVO R4,_screen
	;[924]         END IF
	SRCFILE "texas.bas",924
T237:
	;[925]     NEXT gs_i
	SRCFILE "texas.bas",925
	MVI var_GS_I,R0
	INCR R0
	MVO R0,var_GS_I
	MVI var_TMP_PC,R1
	DECR R1
	CMPR R1,R0
	BLE T236
	;[926] 
	SRCFILE "texas.bas",926
	;[927] sp_wait:
	SRCFILE "texas.bas",927
	; SP_WAIT
label_SP_WAIT:	;[928]     WAIT
	SRCFILE "texas.bas",928
	CALL _wait
	;[929]     GOSUB read_input
	SRCFILE "texas.bas",929
	CALL label_READ_INPUT
	;[930]     IF inp_key = 11 THEN GOTO sp_wait ' level, not an edge -- this is hold-to-view
	SRCFILE "texas.bas",930
	MVI var_INP_KEY,R0
	CMPI #11,R0
	BEQ label_SP_WAIT
	;[931] 
	SRCFILE "texas.bas",931
	;[932]     force_redraw = 1 ' restore names (and everything else) on the next poll
	SRCFILE "texas.bas",932
	MVII #1,R0
	MVO R0,var_FORCE_REDRAW
	;[933] END
	SRCFILE "texas.bas",933
	RETURN
	ENDP
	;[934] 
	SRCFILE "texas.bas",934
	;[935] ' ---------------------------------------------------------------------------
	SRCFILE "texas.bas",935
	;[936] ' card_from_ascii / suit_from_ascii: translate the wire's lowercase ASCII
	SRCFILE "texas.bas",936
	;[937] ' rank/suit chars (conv_in) into print_card's expected numeric codes
	SRCFILE "texas.bas",937
	;[938] ' (conv_out; 0 = unrecognized/blank).
	SRCFILE "texas.bas",938
	;[939] ' ---------------------------------------------------------------------------
	SRCFILE "texas.bas",939
	;[940] card_from_ascii: PROCEDURE
	SRCFILE "texas.bas",940
	; CARD_FROM_ASCII
label_CARD_FROM_ASCII:	PROC
	BEGIN
	;[941]     IF conv_in = 50 THEN
	SRCFILE "texas.bas",941
	MVI var_CONV_IN,R0
	CMPI #50,R0
	BNE T240
	;[942]         conv_out = 2
	SRCFILE "texas.bas",942
	MVII #2,R0
	MVO R0,var_CONV_OUT
	;[943]     ELSEIF conv_in = 51 THEN
	SRCFILE "texas.bas",943
	B T241
T240:
	MVI var_CONV_IN,R0
	CMPI #51,R0
	BNE T242
	;[944]         conv_out = 3
	SRCFILE "texas.bas",944
	MVII #3,R0
	MVO R0,var_CONV_OUT
	;[945]     ELSEIF conv_in = 52 THEN
	SRCFILE "texas.bas",945
	B T241
T242:
	MVI var_CONV_IN,R0
	CMPI #52,R0
	BNE T243
	;[946]         conv_out = 4
	SRCFILE "texas.bas",946
	MVII #4,R0
	MVO R0,var_CONV_OUT
	;[947]     ELSEIF conv_in = 53 THEN
	SRCFILE "texas.bas",947
	B T241
T243:
	MVI var_CONV_IN,R0
	CMPI #53,R0
	BNE T244
	;[948]         conv_out = 5
	SRCFILE "texas.bas",948
	MVII #5,R0
	MVO R0,var_CONV_OUT
	;[949]     ELSEIF conv_in = 54 THEN
	SRCFILE "texas.bas",949
	B T241
T244:
	MVI var_CONV_IN,R0
	CMPI #54,R0
	BNE T245
	;[950]         conv_out = 6
	SRCFILE "texas.bas",950
	MVII #6,R0
	MVO R0,var_CONV_OUT
	;[951]     ELSEIF conv_in = 55 THEN
	SRCFILE "texas.bas",951
	B T241
T245:
	MVI var_CONV_IN,R0
	CMPI #55,R0
	BNE T246
	;[952]         conv_out = 7
	SRCFILE "texas.bas",952
	MVII #7,R0
	MVO R0,var_CONV_OUT
	;[953]     ELSEIF conv_in = 56 THEN
	SRCFILE "texas.bas",953
	B T241
T246:
	MVI var_CONV_IN,R0
	CMPI #56,R0
	BNE T247
	;[954]         conv_out = 8
	SRCFILE "texas.bas",954
	MVII #8,R0
	MVO R0,var_CONV_OUT
	;[955]     ELSEIF conv_in = 57 THEN
	SRCFILE "texas.bas",955
	B T241
T247:
	MVI var_CONV_IN,R0
	CMPI #57,R0
	BNE T248
	;[956]         conv_out = 9
	SRCFILE "texas.bas",956
	MVII #9,R0
	MVO R0,var_CONV_OUT
	;[957]     ELSEIF conv_in = 116 THEN
	SRCFILE "texas.bas",957
	B T241
T248:
	MVI var_CONV_IN,R0
	CMPI #116,R0
	BNE T249
	;[958]         conv_out = 10
	SRCFILE "texas.bas",958
	MVII #10,R0
	MVO R0,var_CONV_OUT
	;[959]     ELSEIF conv_in = 106 THEN
	SRCFILE "texas.bas",959
	B T241
T249:
	MVI var_CONV_IN,R0
	CMPI #106,R0
	BNE T250
	;[960]         conv_out = 11
	SRCFILE "texas.bas",960
	MVII #11,R0
	MVO R0,var_CONV_OUT
	;[961]     ELSEIF conv_in = 113 THEN
	SRCFILE "texas.bas",961
	B T241
T250:
	MVI var_CONV_IN,R0
	CMPI #113,R0
	BNE T251
	;[962]         conv_out = 12
	SRCFILE "texas.bas",962
	MVII #12,R0
	MVO R0,var_CONV_OUT
	;[963]     ELSEIF conv_in = 107 THEN
	SRCFILE "texas.bas",963
	B T241
T251:
	MVI var_CONV_IN,R0
	CMPI #107,R0
	BNE T252
	;[964]         conv_out = 13
	SRCFILE "texas.bas",964
	MVII #13,R0
	MVO R0,var_CONV_OUT
	;[965]     ELSEIF conv_in = 97 THEN
	SRCFILE "texas.bas",965
	B T241
T252:
	MVI var_CONV_IN,R0
	CMPI #97,R0
	BNE T253
	;[966]         conv_out = 14
	SRCFILE "texas.bas",966
	MVII #14,R0
	MVO R0,var_CONV_OUT
	;[967]     ELSE
	SRCFILE "texas.bas",967
	B T241
T253:
	;[968]         conv_out = 0
	SRCFILE "texas.bas",968
	CLRR R0
	MVO R0,var_CONV_OUT
	;[969]     END IF
	SRCFILE "texas.bas",969
T241:
	;[970] END
	SRCFILE "texas.bas",970
	RETURN
	ENDP
	;[971] 
	SRCFILE "texas.bas",971
	;[972] suit_from_ascii: PROCEDURE
	SRCFILE "texas.bas",972
	; SUIT_FROM_ASCII
label_SUIT_FROM_ASCII:	PROC
	BEGIN
	;[973]     IF conv_in = 100 THEN
	SRCFILE "texas.bas",973
	MVI var_CONV_IN,R0
	CMPI #100,R0
	BNE T254
	;[974]         conv_out = DIAMONDS
	SRCFILE "texas.bas",974
	MVII #1,R0
	MVO R0,var_CONV_OUT
	;[975]     ELSEIF conv_in = 104 THEN
	SRCFILE "texas.bas",975
	B T255
T254:
	MVI var_CONV_IN,R0
	CMPI #104,R0
	BNE T256
	;[976]         conv_out = HEARTS
	SRCFILE "texas.bas",976
	MVII #2,R0
	MVO R0,var_CONV_OUT
	;[977]     ELSEIF conv_in = 99 THEN
	SRCFILE "texas.bas",977
	B T255
T256:
	MVI var_CONV_IN,R0
	CMPI #99,R0
	BNE T257
	;[978]         conv_out = CLUBS
	SRCFILE "texas.bas",978
	MVII #3,R0
	MVO R0,var_CONV_OUT
	;[979]     ELSEIF conv_in = 115 THEN
	SRCFILE "texas.bas",979
	B T255
T257:
	MVI var_CONV_IN,R0
	CMPI #115,R0
	BNE T258
	;[980]         conv_out = SPADES
	SRCFILE "texas.bas",980
	MVII #4,R0
	MVO R0,var_CONV_OUT
	;[981]     ELSE
	SRCFILE "texas.bas",981
	B T255
T258:
	;[982]         conv_out = 0
	SRCFILE "texas.bas",982
	CLRR R0
	MVO R0,var_CONV_OUT
	;[983]     END IF
	SRCFILE "texas.bas",983
T255:
	;[984] END
	SRCFILE "texas.bas",984
	RETURN
	ENDP
	;[985] 
	SRCFILE "texas.bas",985
	;[986] ' ---------------------------------------------------------------------------
	SRCFILE "texas.bas",986
	;[987] ' draw_status: status row (row 11). Your turn is handled separately by
	SRCFILE "texas.bas",987
	;[988] ' move_ui (which overwrites this row); otherwise show "WAIT <name>" while
	SRCFILE "texas.bas",988
	;[989] ' someone else acts, or the truncated lastResult otherwise.
	SRCFILE "texas.bas",989
	;[990] ' ---------------------------------------------------------------------------
	SRCFILE "texas.bas",990
	;[991] draw_status: PROCEDURE
	SRCFILE "texas.bas",991
	; DRAW_STATUS
label_DRAW_STATUS:	PROC
	BEGIN
	;[992]     IF active_player > 0 THEN
	SRCFILE "texas.bas",992
	MVI 40340,R0
	ANDI #255,R0
	CMPI #255,R0
	MVII #65535,R0
	BEQ T260
	INCR R0
T260:
	MVII #65280,R5
	CLRR R4
	CLRC
	RRC R0,1
	BEQ T262
T261:
	BNC T263
	ADDR R5,R4
T263:
	ADDR R5,R5
	SARC R0,1
	BNE T261
T262:
	BNC T264
	ADDR R5,R4
T264:
	MOVR R4,R0
	MVI 40340,R1
	ANDI #255,R1
	ADDR R1,R0
	CMPI #0,R0
	BLE T259
	;[993]         PRINT AT STATUS_ROW COLOR COL_STATUS, "WAIT "
	SRCFILE "texas.bas",993
	MVII #732,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #440,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #176,R0
	MVO@ R0,R4
	XORI #64,R0
	MVO@ R0,R4
	XORI #232,R0
	MVO@ R0,R4
	XORI #416,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[994]         #tmp_addr = player_addr(active_player)
	SRCFILE "texas.bas",994
	MVI 40340,R0
	ANDI #255,R0
	CMPI #255,R0
	MVII #65535,R0
	BEQ T265
	INCR R0
T265:
	MVII #65280,R5
	CLRR R4
	CLRC
	RRC R0,1
	BEQ T267
T266:
	BNC T268
	ADDR R5,R4
T268:
	ADDR R5,R5
	SARC R0,1
	BNE T266
T267:
	BNC T269
	ADDR R5,R4
T269:
	MOVR R4,R0
	MVI 40340,R1
	ANDI #255,R1
	MULT R1,R4,33
	ADDR R1,R0
	ADDI #40421,R0
	MVO R0,var_&TMP_ADDR
	;[995]         #df_src = #tmp_addr + PL_NAME : df_pos = STATUS_ROW + 5 : df_len = 4 : #df_color = COL_STATUS
	SRCFILE "texas.bas",995
	MVO R0,var_&DF_SRC
	MVII #225,R0
	MVO R0,var_DF_POS
	MVII #4,R0
	MVO R0,var_DF_LEN
	MVII #7,R0
	MVO R0,var_&DF_COLOR
	;[996]         GOSUB draw_field
	SRCFILE "texas.bas",996
	CALL label_DRAW_FIELD
	;[997]         ' "WAIT <name>" only fills 9 of the row's 20 cells -- without a
	SRCFILE "texas.bas",997
	;[998]         ' full CLS between polls, blank out the rest so a previous,
	SRCFILE "texas.bas",998
	;[999]         ' longer status line (the lastResult branch below, or a move
	SRCFILE "texas.bas",999
	;[1000]         ' menu) can't leave stale characters past column 8.
	SRCFILE "texas.bas",1000
	;[1001]         FOR gs_i = STATUS_ROW + 9 TO STATUS_ROW + ROWCELLS - 1
	SRCFILE "texas.bas",1001
	MVII #229,R0
	MVO R0,var_GS_I
T270:
	;[1002]             #BACKTAB(gs_i) = COL_STATUS
	SRCFILE "texas.bas",1002
	MVII #7,R0
	MVII #Q2,R3
	ADD var_GS_I,R3
	MVO@ R0,R3
	;[1003]         NEXT gs_i
	SRCFILE "texas.bas",1003
	MVI var_GS_I,R0
	INCR R0
	MVO R0,var_GS_I
	CMPI #239,R0
	BLE T270
	;[1004]     ELSE
	SRCFILE "texas.bas",1004
	B T271
T259:
	;[1005]         #df_src = FN_RX + GAME_LASTRESULT : df_pos = STATUS_ROW : df_len = ROWCELLS : #df_color = COL_STATUS
	SRCFILE "texas.bas",1005
	MVII #40256,R0
	MVO R0,var_&DF_SRC
	MVII #220,R0
	MVO R0,var_DF_POS
	MVII #20,R0
	MVO R0,var_DF_LEN
	MVII #7,R0
	MVO R0,var_&DF_COLOR
	;[1006]         GOSUB draw_field
	SRCFILE "texas.bas",1006
	CALL label_DRAW_FIELD
	;[1007]     END IF
	SRCFILE "texas.bas",1007
T271:
	;[1008] END
	SRCFILE "texas.bas",1008
	RETURN
	ENDP
	;[1009] 
	SRCFILE "texas.bas",1009
	;[1010] ' ===========================================================================
	SRCFILE "texas.bas",1010
	;[1011] ' move_ui: your turn. List valid moves on the status row, disc left/right
	SRCFILE "texas.bas",1011
	;[1012] ' to choose, action button to submit. Sets has_move + mvcode_a/mvcode_b.
	SRCFILE "texas.bas",1012
	;[1013] ' ===========================================================================
	SRCFILE "texas.bas",1013
	;[1014] move_ui: PROCEDURE
	SRCFILE "texas.bas",1014
	; MOVE_UI
label_MOVE_UI:	PROC
	BEGIN
	;[1015]     mv_count = PEEK(FN_RX + GAME_VALIDMOVECOUNT) AND 255
	SRCFILE "texas.bas",1015
	MVI 40354,R0
	MVO R0,var_MV_COUNT
	;[1016]     IF mv_count > 5 THEN mv_count = 5
	SRCFILE "texas.bas",1016
	MVI var_MV_COUNT,R0
	CMPI #5,R0
	BLE T272
	MVII #5,R0
	MVO R0,var_MV_COUNT
T272:
	;[1017]     IF mv_count = 0 THEN RETURN
	SRCFILE "texas.bas",1017
	MVI var_MV_COUNT,R0
	TSTR R0
	BNE T273
	RETURN
T273:
	;[1018] 
	SRCFILE "texas.bas",1018
	;[1019]     mv_sel = 0
	SRCFILE "texas.bas",1019
	CLRR R0
	MVO R0,var_MV_SEL
	;[1020]     IF mv_count > 1 THEN mv_sel = 1 ' default to the second move (not Fold), matching the C client
	SRCFILE "texas.bas",1020
	MVI var_MV_COUNT,R0
	CMPI #1,R0
	BLE T274
	MVII #1,R0
	MVO R0,var_MV_SEL
T274:
	;[1021]     ' Only on the poll where the turn actually changed hands -- see the
	SRCFILE "texas.bas",1021
	;[1022]     ' turn_changed comment in the game loop. Kept below the mv_count guard
	SRCFILE "texas.bas",1022
	;[1023]     ' so a state that says it's your turn but carries no moves to make
	SRCFILE "texas.bas",1023
	;[1024]     ' stays silent (the edge is spent either way, matching Fujitzee: the
	SRCFILE "texas.bas",1024
	;[1025]     ' server always attaches validMoves with the turn, so a zero count is
	SRCFILE "texas.bas",1025
	;[1026]     ' a malformed response rather than a turn worth announcing).
	SRCFILE "texas.bas",1026
	;[1027]     IF turn_changed THEN GOSUB sound_myturn
	SRCFILE "texas.bas",1027
	MVI var_TURN_CHANGED,R0
	TSTR R0
	BEQ T275
	CALL label_SOUND_MYTURN
T275:
	;[1028] 
	SRCFILE "texas.bas",1028
	;[1029]     ' Without a per-poll CLS, the status row can be carrying over a
	SRCFILE "texas.bas",1029
	;[1030]     ' previous, wider draw_status message (lastResult fills all 20
	SRCFILE "texas.bas",1030
	;[1031]     ' cells) -- move_ui only pokes the exact columns its move names
	SRCFILE "texas.bas",1031
	;[1032]     ' occupy, so blank the whole row once up front rather than leaving
	SRCFILE "texas.bas",1032
	;[1033]     ' stale text past the last move.
	SRCFILE "texas.bas",1033
	;[1034]     FOR gs_i = STATUS_ROW TO STATUS_ROW + ROWCELLS - 1
	SRCFILE "texas.bas",1034
	MVII #220,R0
	MVO R0,var_GS_I
T276:
	;[1035]         #BACKTAB(gs_i) = COL_STATUS
	SRCFILE "texas.bas",1035
	MVII #7,R0
	MVII #Q2,R3
	ADD var_GS_I,R3
	MVO@ R0,R3
	;[1036]     NEXT gs_i
	SRCFILE "texas.bas",1036
	MVI var_GS_I,R0
	INCR R0
	MVO R0,var_GS_I
	CMPI #239,R0
	BLE T276
	;[1037]     ' Stopwatch icon (cardbot's 7th/last glyph, screen code 276 -- the
	SRCFILE "texas.bas",1037
	;[1038]     ' only one of that set that's a clock face) in the last 3 columns of
	SRCFILE "texas.bas",1038
	;[1039]     ' the move row, poked directly rather than through print_card since
	SRCFILE "texas.bas",1039
	;[1040]     ' this isn't a playing card.
	SRCFILE "texas.bas",1040
	;[1041]     #BACKTAB(STATUS_ROW + 17) = 276 * 8 + COL_STATUS
	SRCFILE "texas.bas",1041
	MVII #2215,R0
	MVO R0,Q2+237
	;[1042] 
	SRCFILE "texas.bas",1042
	;[1043]     ' moveTime (server-computed, already net of a network round-trip
	SRCFILE "texas.bas",1043
	;[1044]     ' grace period -- see gameLogic.go) is our countdown's starting
	SRCFILE "texas.bas",1044
	;[1045]     ' point; we count it down locally frame-by-frame rather than
	SRCFILE "texas.bas",1045
	;[1046]     ' re-polling the server every second.
	SRCFILE "texas.bas",1046
	;[1047]     mv_timeleft = PEEK(FN_RX + GAME_MOVETIME) AND 255
	SRCFILE "texas.bas",1047
	MVI 40341,R0
	MVO R0,var_MV_TIMELEFT
	;[1048]     mv_framecount = 0
	SRCFILE "texas.bas",1048
	CLRR R0
	MVO R0,var_MV_FRAMECOUNT
	;[1049]     PRINT AT STATUS_ROW + 18 COLOR COL_STATUS, <2>mv_timeleft
	SRCFILE "texas.bas",1049
	MVII #750,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI var_MV_TIMELEFT,R0
	MVII #2,R2
	MVI _color,R3
	MVI _screen,R4
	CALL PRNUM16.z
	MVO R4,_screen
	;[1050] 
	SRCFILE "texas.bas",1050
	;[1051]     ' Columns 0-16 are the move menu's budget (the stopwatch + timer own
	SRCFILE "texas.bas",1051
	;[1052]     ' 17-19). 5 Card Stud's fixed 5-col spacing with a clamp at 12 let a
	SRCFILE "texas.bas",1052
	;[1053]     ' 4th move overwrite half the 3rd ("RAIS"/"ALL-" rendering as
	SRCFILE "texas.bas",1053
	;[1054]     ' "RAALL-") -- rare there, but Hold'em offers FOLD/CHECK/RAISE/ALL-IN
	SRCFILE "texas.bas",1054
	;[1055]     ' routinely, so scale the spacing to the move count instead and show
	SRCFILE "texas.bas",1055
	;[1056]     ' as many name chars as fit in it: 1-3 moves get 5 cols / 4 chars
	SRCFILE "texas.bas",1056
	;[1057]     ' (unchanged), 4 get 4/3, 5 get 3/2. Never overlaps, never reaches
	SRCFILE "texas.bas",1057
	;[1058]     ' the timer.
	SRCFILE "texas.bas",1058
	;[1059]     mv_gap = 16 / mv_count
	SRCFILE "texas.bas",1059
	MVII #16,R0
	MVI var_MV_COUNT,R4
	MOVR R0,R5
	TSTR R4
	BEQ T277
	MVII #65535,R0
T278:
	INCR R0
	SUBR R4,R5
	BC T278
T277:
	MVO R0,var_MV_GAP
	;[1060]     IF mv_gap > 5 THEN mv_gap = 5
	SRCFILE "texas.bas",1060
	MVI var_MV_GAP,R0
	CMPI #5,R0
	BLE T279
	MVII #5,R0
	MVO R0,var_MV_GAP
T279:
	;[1061]     mv_len = mv_gap - 1
	SRCFILE "texas.bas",1061
	MVI var_MV_GAP,R0
	DECR R0
	MVO R0,var_MV_LEN
	;[1062]     IF mv_len > 4 THEN mv_len = 4
	SRCFILE "texas.bas",1062
	MVI var_MV_LEN,R0
	CMPI #4,R0
	BLE T280
	MVII #4,R0
	MVO R0,var_MV_LEN
T280:
	;[1063] 
	SRCFILE "texas.bas",1063
	;[1064]     inp_lock = 0
	SRCFILE "texas.bas",1064
	CLRR R0
	MVO R0,var_INP_LOCK
	;[1065] mu_loop:
	SRCFILE "texas.bas",1065
	; MU_LOOP
label_MU_LOOP:	;[1066]     gs_j = 0
	SRCFILE "texas.bas",1066
	CLRR R0
	MVO R0,var_GS_J
	;[1067]     FOR gs_i = 0 TO mv_count - 1
	SRCFILE "texas.bas",1067
	MVO R0,var_GS_I
T281:
	;[1068]         mv_col(gs_i) = gs_j
	SRCFILE "texas.bas",1068
	MVI var_GS_J,R0
	MVII #array_MV_COL,R3
	ADD var_GS_I,R3
	MVO@ R0,R3
	;[1069]         #gs_c = COL_STATUS
	SRCFILE "texas.bas",1069
	MVII #7,R0
	MVO R0,var_&GS_C
	;[1070]         IF gs_i = mv_sel THEN #gs_c = COL_HILITE
	SRCFILE "texas.bas",1070
	MVI var_GS_I,R0
	CMP var_MV_SEL,R0
	BNE T282
	MVII #8198,R0
	MVO R0,var_&GS_C
T282:
	;[1071]         #tmp_addr = move_addr(gs_i)
	SRCFILE "texas.bas",1071
	MVI var_GS_I,R0
	MULT R0,R4,13
	ADDI #40355,R0
	MVO R0,var_&TMP_ADDR
	;[1072]         #df_src = #tmp_addr + MOVE_NAME : df_pos = STATUS_ROW + gs_j : df_len = mv_len : #df_color = #gs_c
	SRCFILE "texas.bas",1072
	ADDI #3,R0
	MVO R0,var_&DF_SRC
	MVI var_GS_J,R0
	ADDI #220,R0
	MVO R0,var_DF_POS
	MVI var_MV_LEN,R0
	MVO R0,var_DF_LEN
	MVI var_&GS_C,R0
	MVO R0,var_&DF_COLOR
	;[1073]         GOSUB draw_field
	SRCFILE "texas.bas",1073
	CALL label_DRAW_FIELD
	;[1074]         gs_j = gs_j + mv_gap
	SRCFILE "texas.bas",1074
	MVI var_GS_J,R0
	ADD var_MV_GAP,R0
	MVO R0,var_GS_J
	;[1075]     NEXT gs_i
	SRCFILE "texas.bas",1075
	MVI var_GS_I,R0
	INCR R0
	MVO R0,var_GS_I
	MVI var_MV_COUNT,R1
	DECR R1
	CMPR R1,R0
	BLE T281
	;[1076] 
	SRCFILE "texas.bas",1076
	;[1077]     WAIT
	SRCFILE "texas.bas",1077
	CALL _wait
	;[1078]     GOSUB read_input
	SRCFILE "texas.bas",1078
	CALL label_READ_INPUT
	;[1079] 
	SRCFILE "texas.bas",1079
	;[1080]     mv_framecount = mv_framecount + 1
	SRCFILE "texas.bas",1080
	MVI var_MV_FRAMECOUNT,R0
	INCR R0
	MVO R0,var_MV_FRAMECOUNT
	;[1081]     IF mv_framecount >= 60 THEN
	SRCFILE "texas.bas",1081
	MVI var_MV_FRAMECOUNT,R0
	CMPI #60,R0
	BLT T283
	;[1082]         mv_framecount = 0
	SRCFILE "texas.bas",1082
	CLRR R0
	MVO R0,var_MV_FRAMECOUNT
	;[1083]         IF mv_timeleft > 0 THEN mv_timeleft = mv_timeleft - 1
	SRCFILE "texas.bas",1083
	MVI var_MV_TIMELEFT,R0
	CMPI #0,R0
	BLE T284
	DECR R0
	MVO R0,var_MV_TIMELEFT
T284:
	;[1084]         PRINT AT STATUS_ROW + 18 COLOR COL_STATUS, <2>mv_timeleft
	SRCFILE "texas.bas",1084
	MVII #750,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI var_MV_TIMELEFT,R0
	MVII #2,R2
	MVI _color,R3
	MVI _screen,R4
	CALL PRNUM16.z
	MVO R4,_screen
	;[1085]         ' Timed out -- submit whatever's currently highlighted (the
	SRCFILE "texas.bas",1085
	;[1086]         ' default move if the player never touched the disc, matching
	SRCFILE "texas.bas",1086
	;[1087]         ' the C clients' timeout behavior of submitting the highlighted
	SRCFILE "texas.bas",1087
	;[1088]         ' selection rather than always folding).
	SRCFILE "texas.bas",1088
	;[1089]         IF mv_timeleft = 0 THEN GOTO mu_confirm
	SRCFILE "texas.bas",1089
	MVI var_MV_TIMELEFT,R0
	TSTR R0
	BEQ label_MU_CONFIRM
	;[1090]     END IF
	SRCFILE "texas.bas",1090
T283:
	;[1091] 
	SRCFILE "texas.bas",1091
	;[1092]     IF inp_lock > 0 THEN inp_lock = inp_lock - 1 : GOTO mu_loop
	SRCFILE "texas.bas",1092
	MVI var_INP_LOCK,R0
	CMPI #0,R0
	BLE T286
	DECR R0
	MVO R0,var_INP_LOCK
	B label_MU_LOOP
T286:
	;[1093] 
	SRCFILE "texas.bas",1093
	;[1094]     IF inp_dir AND DISC_RIGHT THEN
	SRCFILE "texas.bas",1094
	MVI var_INP_DIR,R0
	ANDI #2,R0
	BEQ T287
	;[1095]         mv_sel = mv_sel + 1
	SRCFILE "texas.bas",1095
	MVI var_MV_SEL,R0
	INCR R0
	MVO R0,var_MV_SEL
	;[1096]         IF mv_sel >= mv_count THEN mv_sel = 0
	SRCFILE "texas.bas",1096
	MVI var_MV_SEL,R0
	CMP var_MV_COUNT,R0
	BLT T288
	CLRR R0
	MVO R0,var_MV_SEL
T288:
	;[1097]         inp_lock = 8
	SRCFILE "texas.bas",1097
	MVII #8,R0
	MVO R0,var_INP_LOCK
	;[1098]         GOSUB sound_cursor
	SRCFILE "texas.bas",1098
	CALL label_SOUND_CURSOR
	;[1099]         GOTO mu_loop
	SRCFILE "texas.bas",1099
	B label_MU_LOOP
	;[1100]     END IF
	SRCFILE "texas.bas",1100
T287:
	;[1101]     IF inp_dir AND DISC_LEFT THEN
	SRCFILE "texas.bas",1101
	MVI var_INP_DIR,R0
	ANDI #8,R0
	BEQ T289
	;[1102]         IF mv_sel = 0 THEN mv_sel = mv_count
	SRCFILE "texas.bas",1102
	MVI var_MV_SEL,R0
	TSTR R0
	BNE T290
	MVI var_MV_COUNT,R0
	MVO R0,var_MV_SEL
T290:
	;[1103]         mv_sel = mv_sel - 1
	SRCFILE "texas.bas",1103
	MVI var_MV_SEL,R0
	DECR R0
	MVO R0,var_MV_SEL
	;[1104]         inp_lock = 8
	SRCFILE "texas.bas",1104
	MVII #8,R0
	MVO R0,var_INP_LOCK
	;[1105]         GOSUB sound_cursor
	SRCFILE "texas.bas",1105
	CALL label_SOUND_CURSOR
	;[1106]         GOTO mu_loop
	SRCFILE "texas.bas",1106
	B label_MU_LOOP
	;[1107]     END IF
	SRCFILE "texas.bas",1107
T289:
	;[1108]     ' Bail to the in-game menu without moving. The edge isn't consumed by
	SRCFILE "texas.bas",1108
	;[1109]     ' returning -- input_check runs next and sees the same inp_key_hit, which
	SRCFILE "texas.bas",1109
	;[1110]     ' is what actually opens the menu.
	SRCFILE "texas.bas",1110
	;[1111]     IF inp_key_hit = 10 THEN RETURN
	SRCFILE "texas.bas",1111
	MVI var_INP_KEY_HIT,R0
	CMPI #10,R0
	BNE T291
	RETURN
T291:
	;[1112]     IF inp_btn_hit = 0 THEN GOTO mu_loop
	SRCFILE "texas.bas",1112
	MVI var_INP_BTN_HIT,R0
	TSTR R0
	BEQ label_MU_LOOP
	;[1113]     GOSUB sound_select
	SRCFILE "texas.bas",1113
	CALL label_SOUND_SELECT
	;[1114] 
	SRCFILE "texas.bas",1114
	;[1115] mu_confirm:
	SRCFILE "texas.bas",1115
	; MU_CONFIRM
label_MU_CONFIRM:	;[1116]     #tmp_addr = move_addr(mv_sel)
	SRCFILE "texas.bas",1116
	MVI var_MV_SEL,R0
	MULT R0,R4,13
	ADDI #40355,R0
	MVO R0,var_&TMP_ADDR
	;[1117]     mvcode_a = PEEK(#tmp_addr + MOVE_CODE) AND 255
	SRCFILE "texas.bas",1117
	MOVR R0,R1
	MVI@ R1,R0
	MVO R0,var_MVCODE_A
	;[1118]     mvcode_b = PEEK(#tmp_addr + MOVE_CODE + 1) AND 255
	SRCFILE "texas.bas",1118
	INCR R1
	MVI@ R1,R0
	MVO R0,var_MVCODE_B
	;[1119]     has_move = 1
	SRCFILE "texas.bas",1119
	MVII #1,R0
	MVO R0,var_HAS_MOVE
	;[1120] END
	SRCFILE "texas.bas",1120
	RETURN
	ENDP
	;[1121] 
	SRCFILE "texas.bas",1121
	;[1122] ' ===========================================================================
	SRCFILE "texas.bas",1122
	;[1123] ' ingame_menu: keypad CLEAR overlay. Disc up/down to choose, action button
	SRCFILE "texas.bas",1123
	;[1124] ' to confirm, matching every other screen's controls (Clear itself also
	SRCFILE "texas.bas",1124
	;[1125] ' cancels, for a quick way back in without touching the disc). Defaults
	SRCFILE "texas.bas",1125
	;[1126] ' to RESUME so an accidental Clear press can't quit a hand by surprise.
	SRCFILE "texas.bas",1126
	;[1127] ' ===========================================================================
	SRCFILE "texas.bas",1127
	;[1128] ingame_menu: PROCEDURE
	SRCFILE "texas.bas",1128
	; INGAME_MENU
label_INGAME_MENU:	PROC
	BEGIN
	;[1129]     im_sel = 0
	SRCFILE "texas.bas",1129
	CLRR R0
	MVO R0,var_IM_SEL
	;[1130]     inp_lock = 0
	SRCFILE "texas.bas",1130
	MVO R0,var_INP_LOCK
	;[1131] im_loop:
	SRCFILE "texas.bas",1131
	; IM_LOOP
label_IM_LOOP:	;[1132]     PRINT AT 80 COLOR COL_STATUS, "                    "
	SRCFILE "texas.bas",1132
	MVII #592,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	NOP
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	NOP
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	NOP
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	NOP
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	NOP
	MVO R4,_screen
	;[1133]     PRINT AT 100 COLOR COL_STATUS, "                    "
	SRCFILE "texas.bas",1133
	MVII #612,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	NOP
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	NOP
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	NOP
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	NOP
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	NOP
	MVO R4,_screen
	;[1134]     PRINT AT 120 COLOR COL_STATUS, "                    "
	SRCFILE "texas.bas",1134
	MVII #632,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	NOP
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	NOP
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	NOP
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	NOP
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	NOP
	MVO R4,_screen
	;[1135]     PRINT AT 86 COLOR COL_STATUS, "TABLE MENU"
	SRCFILE "texas.bas",1135
	MVII #598,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #416,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #168,R0
	MVO@ R0,R4
	XORI #24,R0
	MVO@ R0,R4
	XORI #112,R0
	MVO@ R0,R4
	XORI #72,R0
	MVO@ R0,R4
	XORI #296,R0
	MVO@ R0,R4
	XORI #360,R0
	MVO@ R0,R4
	XORI #64,R0
	MVO@ R0,R4
	XORI #88,R0
	MVO@ R0,R4
	XORI #216,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[1136]     #gs_c = COL_STATUS
	SRCFILE "texas.bas",1136
	MVII #7,R0
	MVO R0,var_&GS_C
	;[1137]     IF im_sel = 0 THEN #gs_c = COL_HILITE
	SRCFILE "texas.bas",1137
	MVI var_IM_SEL,R0
	TSTR R0
	BNE T293
	MVII #8198,R0
	MVO R0,var_&GS_C
T293:
	;[1138]     PRINT AT 106 COLOR #gs_c, "RESUME"
	SRCFILE "texas.bas",1138
	MVII #618,R0
	MVO R0,_screen
	MVI var_&GS_C,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #400,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #184,R0
	MVO@ R0,R4
	XORI #176,R0
	MVO@ R0,R4
	XORI #48,R0
	MVO@ R0,R4
	XORI #192,R0
	MVO@ R0,R4
	XORI #64,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[1139]     #gs_c = COL_STATUS
	SRCFILE "texas.bas",1139
	MVII #7,R0
	MVO R0,var_&GS_C
	;[1140]     IF im_sel = 1 THEN #gs_c = COL_HILITE
	SRCFILE "texas.bas",1140
	MVI var_IM_SEL,R0
	CMPI #1,R0
	BNE T294
	MVII #8198,R0
	MVO R0,var_&GS_C
T294:
	;[1141]     PRINT AT 126 COLOR #gs_c, "QUIT TABLE"
	SRCFILE "texas.bas",1141
	MVII #638,R0
	MVO R0,_screen
	MVI var_&GS_C,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #392,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #32,R0
	MVO@ R0,R4
	XORI #224,R0
	MVO@ R0,R4
	XORI #232,R0
	MVO@ R0,R4
	XORI #416,R0
	MVO@ R0,R4
	XORI #416,R0
	MVO@ R0,R4
	XORI #168,R0
	MVO@ R0,R4
	XORI #24,R0
	MVO@ R0,R4
	XORI #112,R0
	MVO@ R0,R4
	XORI #72,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[1142] 
	SRCFILE "texas.bas",1142
	;[1143]     WAIT
	SRCFILE "texas.bas",1143
	CALL _wait
	;[1144]     GOSUB read_input
	SRCFILE "texas.bas",1144
	CALL label_READ_INPUT
	;[1145]     IF inp_lock > 0 THEN inp_lock = inp_lock - 1 : GOTO im_loop
	SRCFILE "texas.bas",1145
	MVI var_INP_LOCK,R0
	CMPI #0,R0
	BLE T295
	DECR R0
	MVO R0,var_INP_LOCK
	B label_IM_LOOP
T295:
	;[1146] 
	SRCFILE "texas.bas",1146
	;[1147]     IF inp_dir AND (DISC_UP OR DISC_DOWN) THEN
	SRCFILE "texas.bas",1147
	MVI var_INP_DIR,R0
	ANDI #5,R0
	BEQ T296
	;[1148]         im_sel = 1 - im_sel
	SRCFILE "texas.bas",1148
	MVII #1,R0
	SUB var_IM_SEL,R0
	MVO R0,var_IM_SEL
	;[1149]         inp_lock = 10
	SRCFILE "texas.bas",1149
	MVII #10,R0
	MVO R0,var_INP_LOCK
	;[1150]         GOSUB sound_cursor
	SRCFILE "texas.bas",1150
	CALL label_SOUND_CURSOR
	;[1151]         GOTO im_loop
	SRCFILE "texas.bas",1151
	B label_IM_LOOP
	;[1152]     END IF
	SRCFILE "texas.bas",1152
T296:
	;[1153]     ' Clear again cancels straight back to RESUME. Safe to test on the frame
	SRCFILE "texas.bas",1153
	;[1154]     ' the menu opens: inp_key_hit is an edge, so the still-held press that
	SRCFILE "texas.bas",1154
	;[1155]     ' got us here reads as "no key" until it's released and pressed again.
	SRCFILE "texas.bas",1155
	;[1156]     IF inp_key_hit = 10 THEN GOTO im_done
	SRCFILE "texas.bas",1156
	MVI var_INP_KEY_HIT,R0
	CMPI #10,R0
	BEQ label_IM_DONE
	;[1157]     IF inp_btn_hit = 0 THEN GOTO im_loop
	SRCFILE "texas.bas",1157
	MVI var_INP_BTN_HIT,R0
	TSTR R0
	BEQ label_IM_LOOP
	;[1158]     GOSUB sound_select
	SRCFILE "texas.bas",1158
	CALL label_SOUND_SELECT
	;[1159] 
	SRCFILE "texas.bas",1159
	;[1160]     IF im_sel = 1 THEN
	SRCFILE "texas.bas",1160
	MVI var_IM_SEL,R0
	CMPI #1,R0
	BNE T299
	;[1161]         gs_path = 3 : GOSUB compose_url
	SRCFILE "texas.bas",1161
	MVII #3,R0
	MVO R0,var_GS_PATH
	CALL label_COMPOSE_URL
	;[1162]         #net_readlen = 8
	SRCFILE "texas.bas",1162
	MVII #8,R0
	MVO R0,var_&NET_READLEN
	;[1163]         GOSUB api_call
	SRCFILE "texas.bas",1163
	CALL label_API_CALL
	;[1164]         GOSUB clear_room_appkey
	SRCFILE "texas.bas",1164
	CALL label_CLEAR_ROOM_APPKEY
	;[1165]         want_leave = 1
	SRCFILE "texas.bas",1165
	MVII #1,R0
	MVO R0,var_WANT_LEAVE
	;[1166]     END IF
	SRCFILE "texas.bas",1166
T299:
	;[1167] im_done:
	SRCFILE "texas.bas",1167
	; IM_DONE
label_IM_DONE:	;[1168]     force_redraw = 1
	SRCFILE "texas.bas",1168
	MVII #1,R0
	MVO R0,var_FORCE_REDRAW
	;[1169] END
	SRCFILE "texas.bas",1169
	RETURN
	ENDP
	;[1170] 
	SRCFILE "texas.bas",1170
	;[1171] ' ===========================================================================
	SRCFILE "texas.bas",1171
	;[1172] ' name_entry_screen: disc letter picker, max 8 chars. Disc up/down cycles
	SRCFILE "texas.bas",1172
	;[1173] ' the character under the cursor through A-Z, 0-9, space; left/right moves
	SRCFILE "texas.bas",1173
	;[1174] ' the cursor; the action button accepts (at least 1 non-space char).
	SRCFILE "texas.bas",1174
	;[1175] ' ===========================================================================
	SRCFILE "texas.bas",1175
	;[1176] name_entry_screen: PROCEDURE
	SRCFILE "texas.bas",1176
	; NAME_ENTRY_SCREEN
label_NAME_ENTRY_SCREEN:	PROC
	BEGIN
	;[1177]     CLS
	SRCFILE "texas.bas",1177
	CALL CLRSCR
	;[1178]     GOSUB fill_bg
	SRCFILE "texas.bas",1178
	CALL label_FILL_BG
	;[1179]     PRINT AT 0 COLOR COL_STATUS, "ENTER YOUR NAME"
	SRCFILE "texas.bas",1179
	MVII #512,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #296,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #88,R0
	MVO@ R0,R4
	XORI #208,R0
	MVO@ R0,R4
	XORI #136,R0
	MVO@ R0,R4
	XORI #184,R0
	MVO@ R0,R4
	XORI #400,R0
	MVO@ R0,R4
	XORI #456,R0
	MVO@ R0,R4
	XORI #176,R0
	MVO@ R0,R4
	XORI #208,R0
	MVO@ R0,R4
	XORI #56,R0
	MVO@ R0,R4
	XORI #400,R0
	MVO@ R0,R4
	XORI #368,R0
	MVO@ R0,R4
	XORI #120,R0
	MVO@ R0,R4
	XORI #96,R0
	MVO@ R0,R4
	XORI #64,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[1180]     FOR ne_i = 0 TO 7
	SRCFILE "texas.bas",1180
	CLRR R0
	MVO R0,var_NE_I
T300:
	;[1181]         ne_buf(ne_i) = 36 ' space
	SRCFILE "texas.bas",1181
	MVII #36,R0
	MVII #array_NE_BUF,R3
	ADD var_NE_I,R3
	MVO@ R0,R3
	;[1182]     NEXT ne_i
	SRCFILE "texas.bas",1182
	MVI var_NE_I,R0
	INCR R0
	MVO R0,var_NE_I
	CMPI #7,R0
	BLE T300
	;[1183]     ne_cur = 0
	SRCFILE "texas.bas",1183
	CLRR R0
	MVO R0,var_NE_CUR
	;[1184]     inp_lock = 0
	SRCFILE "texas.bas",1184
	MVO R0,var_INP_LOCK
	;[1185] 
	SRCFILE "texas.bas",1185
	;[1186] ne_loop:
	SRCFILE "texas.bas",1186
	; NE_LOOP
label_NE_LOOP:	;[1187]     FOR ne_i = 0 TO 7
	SRCFILE "texas.bas",1187
	CLRR R0
	MVO R0,var_NE_I
T301:
	;[1188]         #gs_c = COL_NAME
	SRCFILE "texas.bas",1188
	MVII #8199,R0
	MVO R0,var_&GS_C
	;[1189]         IF ne_i = ne_cur THEN #gs_c = COL_HILITE
	SRCFILE "texas.bas",1189
	MVI var_NE_I,R0
	CMP var_NE_CUR,R0
	BNE T302
	MVII #8198,R0
	MVO R0,var_&GS_C
T302:
	;[1190]         ne_j = ne_buf(ne_i)
	SRCFILE "texas.bas",1190
	MVII #array_NE_BUF,R3
	ADD var_NE_I,R3
	MVI@ R3,R0
	MVO R0,var_NE_J
	;[1191]         IF ne_j < 26 THEN
	SRCFILE "texas.bas",1191
	MVI var_NE_J,R0
	CMPI #26,R0
	BGE T303
	;[1192]             gs_j = 65 + ne_j
	SRCFILE "texas.bas",1192
	ADDI #65,R0
	MVO R0,var_GS_J
	;[1193]         ELSEIF ne_j < 36 THEN
	SRCFILE "texas.bas",1193
	B T304
T303:
	MVI var_NE_J,R0
	CMPI #36,R0
	BGE T305
	;[1194]             gs_j = 48 + ne_j - 26
	SRCFILE "texas.bas",1194
	ADDI #22,R0
	MVO R0,var_GS_J
	;[1195]         ELSE
	SRCFILE "texas.bas",1195
	B T304
T305:
	;[1196]             gs_j = 95 ' underscore stands in for a visible blank
	SRCFILE "texas.bas",1196
	MVII #95,R0
	MVO R0,var_GS_J
	;[1197]         END IF
	SRCFILE "texas.bas",1197
T304:
	;[1198]         #BACKTAB(60 + 6 + ne_i) = (gs_j - 32) * 8 + #gs_c
	SRCFILE "texas.bas",1198
	MVI var_GS_J,R0
	SUBI #32,R0
	SLL R0,2
	ADDR R0,R0
	ADD var_&GS_C,R0
	MVII #Q2+66,R3
	ADD var_NE_I,R3
	MVO@ R0,R3
	;[1199]     NEXT ne_i
	SRCFILE "texas.bas",1199
	MVI var_NE_I,R0
	INCR R0
	MVO R0,var_NE_I
	CMPI #7,R0
	BLE T301
	;[1200] 
	SRCFILE "texas.bas",1200
	;[1201]     WAIT
	SRCFILE "texas.bas",1201
	CALL _wait
	;[1202]     GOSUB read_input
	SRCFILE "texas.bas",1202
	CALL label_READ_INPUT
	;[1203]     IF inp_lock > 0 THEN inp_lock = inp_lock - 1 : GOTO ne_loop
	SRCFILE "texas.bas",1203
	MVI var_INP_LOCK,R0
	CMPI #0,R0
	BLE T306
	DECR R0
	MVO R0,var_INP_LOCK
	B label_NE_LOOP
T306:
	;[1204] 
	SRCFILE "texas.bas",1204
	;[1205]     IF inp_dir AND DISC_RIGHT THEN
	SRCFILE "texas.bas",1205
	MVI var_INP_DIR,R0
	ANDI #2,R0
	BEQ T307
	;[1206]         ne_cur = ne_cur + 1
	SRCFILE "texas.bas",1206
	MVI var_NE_CUR,R0
	INCR R0
	MVO R0,var_NE_CUR
	;[1207]         IF ne_cur > 7 THEN ne_cur = 0
	SRCFILE "texas.bas",1207
	MVI var_NE_CUR,R0
	CMPI #7,R0
	BLE T308
	CLRR R0
	MVO R0,var_NE_CUR
T308:
	;[1208]         inp_lock = 8
	SRCFILE "texas.bas",1208
	MVII #8,R0
	MVO R0,var_INP_LOCK
	;[1209]         GOSUB sound_cursor
	SRCFILE "texas.bas",1209
	CALL label_SOUND_CURSOR
	;[1210]         GOTO ne_loop
	SRCFILE "texas.bas",1210
	B label_NE_LOOP
	;[1211]     END IF
	SRCFILE "texas.bas",1211
T307:
	;[1212]     IF inp_dir AND DISC_LEFT THEN
	SRCFILE "texas.bas",1212
	MVI var_INP_DIR,R0
	ANDI #8,R0
	BEQ T309
	;[1213]         IF ne_cur = 0 THEN ne_cur = 8
	SRCFILE "texas.bas",1213
	MVI var_NE_CUR,R0
	TSTR R0
	BNE T310
	MVII #8,R0
	MVO R0,var_NE_CUR
T310:
	;[1214]         ne_cur = ne_cur - 1
	SRCFILE "texas.bas",1214
	MVI var_NE_CUR,R0
	DECR R0
	MVO R0,var_NE_CUR
	;[1215]         inp_lock = 8
	SRCFILE "texas.bas",1215
	MVII #8,R0
	MVO R0,var_INP_LOCK
	;[1216]         GOSUB sound_cursor
	SRCFILE "texas.bas",1216
	CALL label_SOUND_CURSOR
	;[1217]         GOTO ne_loop
	SRCFILE "texas.bas",1217
	B label_NE_LOOP
	;[1218]     END IF
	SRCFILE "texas.bas",1218
T309:
	;[1219]     IF inp_dir AND DISC_UP THEN
	SRCFILE "texas.bas",1219
	MVI var_INP_DIR,R0
	ANDI #4,R0
	BEQ T311
	;[1220]         ne_buf(ne_cur) = ne_buf(ne_cur) + 1
	SRCFILE "texas.bas",1220
	MVII #array_NE_BUF,R3
	ADD var_NE_CUR,R3
	MVI@ R3,R0
	INCR R0
	MVO@ R0,R3
	;[1221]         IF ne_buf(ne_cur) > 36 THEN ne_buf(ne_cur) = 0
	SRCFILE "texas.bas",1221
	MVI@ R3,R0
	CMPI #36,R0
	BLE T312
	CLRR R0
	MVO@ R0,R3
T312:
	;[1222]         inp_lock = 6
	SRCFILE "texas.bas",1222
	MVII #6,R0
	MVO R0,var_INP_LOCK
	;[1223]         GOSUB sound_cursor
	SRCFILE "texas.bas",1223
	CALL label_SOUND_CURSOR
	;[1224]         GOTO ne_loop
	SRCFILE "texas.bas",1224
	B label_NE_LOOP
	;[1225]     END IF
	SRCFILE "texas.bas",1225
T311:
	;[1226]     IF inp_dir AND DISC_DOWN THEN
	SRCFILE "texas.bas",1226
	MVI var_INP_DIR,R0
	ANDI #1,R0
	BEQ T313
	;[1227]         IF ne_buf(ne_cur) = 0 THEN ne_buf(ne_cur) = 37
	SRCFILE "texas.bas",1227
	MVII #array_NE_BUF,R3
	ADD var_NE_CUR,R3
	MVI@ R3,R0
	TSTR R0
	BNE T314
	MVII #37,R0
	MVO@ R0,R3
T314:
	;[1228]         ne_buf(ne_cur) = ne_buf(ne_cur) - 1
	SRCFILE "texas.bas",1228
	MVII #array_NE_BUF,R3
	ADD var_NE_CUR,R3
	MVI@ R3,R0
	DECR R0
	MVO@ R0,R3
	;[1229]         inp_lock = 6
	SRCFILE "texas.bas",1229
	MVII #6,R0
	MVO R0,var_INP_LOCK
	;[1230]         GOSUB sound_cursor
	SRCFILE "texas.bas",1230
	CALL label_SOUND_CURSOR
	;[1231]         GOTO ne_loop
	SRCFILE "texas.bas",1231
	B label_NE_LOOP
	;[1232]     END IF
	SRCFILE "texas.bas",1232
T313:
	;[1233]     IF inp_btn_hit = 0 THEN GOTO ne_loop
	SRCFILE "texas.bas",1233
	MVI var_INP_BTN_HIT,R0
	TSTR R0
	BEQ label_NE_LOOP
	;[1234]     GOSUB sound_select
	SRCFILE "texas.bas",1234
	CALL label_SOUND_SELECT
	;[1235] 
	SRCFILE "texas.bas",1235
	;[1236]     ne_len = 8
	SRCFILE "texas.bas",1236
	MVII #8,R0
	MVO R0,var_NE_LEN
	;[1237]     WHILE ne_len > 0 AND ne_buf(ne_len - 1) = 36
	SRCFILE "texas.bas",1237
T316:
	MVI var_NE_LEN,R0
	CMPI #0,R0
	MVII #65535,R0
	BGT T318
	INCR R0
T318:
	MVII #array_NE_BUF-1,R3
	ADD var_NE_LEN,R3
	MVI@ R3,R1
	CMPI #36,R1
	MVII #65535,R1
	BEQ T319
	INCR R1
T319:
	ANDR R1,R0
	BEQ T317
	;[1238]         ne_len = ne_len - 1
	SRCFILE "texas.bas",1238
	MVI var_NE_LEN,R0
	DECR R0
	MVO R0,var_NE_LEN
	;[1239]     WEND
	SRCFILE "texas.bas",1239
	B T316
T317:
	;[1240]     IF ne_len = 0 THEN GOTO ne_loop
	SRCFILE "texas.bas",1240
	MVI var_NE_LEN,R0
	TSTR R0
	BEQ label_NE_LOOP
	;[1241] 
	SRCFILE "texas.bas",1241
	;[1242]     FOR ne_i = 0 TO ne_len - 1
	SRCFILE "texas.bas",1242
	CLRR R0
	MVO R0,var_NE_I
T321:
	;[1243]         ne_j = ne_buf(ne_i)
	SRCFILE "texas.bas",1243
	MVII #array_NE_BUF,R3
	ADD var_NE_I,R3
	MVI@ R3,R0
	MVO R0,var_NE_J
	;[1244]         IF ne_j < 26 THEN
	SRCFILE "texas.bas",1244
	MVI var_NE_J,R0
	CMPI #26,R0
	BGE T322
	;[1245]             gs_j = 65 + ne_j
	SRCFILE "texas.bas",1245
	ADDI #65,R0
	MVO R0,var_GS_J
	;[1246]         ELSE
	SRCFILE "texas.bas",1246
	B T323
T322:
	;[1247]             gs_j = 48 + ne_j - 26
	SRCFILE "texas.bas",1247
	MVI var_NE_J,R0
	ADDI #22,R0
	MVO R0,var_GS_J
	;[1248]         END IF
	SRCFILE "texas.bas",1248
T323:
	;[1249]         POKE (SC_NAME + ne_i), gs_j
	SRCFILE "texas.bas",1249
	MVI var_GS_J,R0
	MVI var_NE_I,R1
	ADDI #37120,R1
	MVO@ R0,R1
	;[1250]     NEXT ne_i
	SRCFILE "texas.bas",1250
	MVI var_NE_I,R0
	INCR R0
	MVO R0,var_NE_I
	MVI var_NE_LEN,R1
	DECR R1
	CMPR R1,R0
	BLE T321
	;[1251]     POKE (SC_NAME + ne_len), 0
	SRCFILE "texas.bas",1251
	CLRR R0
	MVI var_NE_LEN,R1
	ADDI #37120,R1
	MVO@ R0,R1
	;[1252] 
	SRCFILE "texas.bas",1252
	;[1253]     ak_creator_lo = 1 : ak_creator_hi = 0 : ak_app = 1 : ak_key = 0 : ak_mode = 1
	SRCFILE "texas.bas",1253
	MVII #1,R0
	MVO R0,var_AK_CREATOR_LO
	CLRR R0
	MVO R0,var_AK_CREATOR_HI
	MVII #1,R0
	MVO R0,var_AK_APP
	CLRR R0
	MVO R0,var_AK_KEY
	MVII #1,R0
	MVO R0,var_AK_MODE
	;[1254]     GOSUB appkey_open
	SRCFILE "texas.bas",1254
	CALL label_APPKEY_OPEN
	;[1255]     IF fn_ok THEN
	SRCFILE "texas.bas",1255
	MVI var_FN_OK,R0
	TSTR R0
	BEQ T324
	;[1256]         #fn_src = SC_NAME : fn_len = ne_len
	SRCFILE "texas.bas",1256
	MVII #37120,R0
	MVO R0,var_&FN_SRC
	MVI var_NE_LEN,R0
	MVO R0,var_FN_LEN
	;[1257]         GOSUB appkey_write
	SRCFILE "texas.bas",1257
	CALL label_APPKEY_WRITE
	;[1258]         ' A failed write used to be silent -- looked identical to success
	SRCFILE "texas.bas",1258
	;[1259]         ' from here, even though the name would never come back on the
	SRCFILE "texas.bas",1259
	;[1260]         ' next boot (e.g. if the backend has no SD/appkey storage mounted).
	SRCFILE "texas.bas",1260
	;[1261]         IF fn_ok = 0 THEN
	SRCFILE "texas.bas",1261
	MVI var_FN_OK,R0
	TSTR R0
	BNE T325
	;[1262]             PRINT AT 100 COLOR COL_STATUS, "NAME NOT SAVED FOR "
	SRCFILE "texas.bas",1262
	MVII #612,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #368,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #120,R0
	MVO@ R0,R4
	XORI #96,R0
	MVO@ R0,R4
	XORI #64,R0
	MVO@ R0,R4
	XORI #296,R0
	MVO@ R0,R4
	XORI #368,R0
	MVO@ R0,R4
	XORI #8,R0
	MVO@ R0,R4
	XORI #216,R0
	MVO@ R0,R4
	XORI #416,R0
	MVO@ R0,R4
	XORI #408,R0
	MVO@ R0,R4
	XORI #144,R0
	MVO@ R0,R4
	XORI #184,R0
	MVO@ R0,R4
	XORI #152,R0
	MVO@ R0,R4
	XORI #8,R0
	MVO@ R0,R4
	XORI #288,R0
	MVO@ R0,R4
	XORI #304,R0
	MVO@ R0,R4
	XORI #72,R0
	MVO@ R0,R4
	XORI #232,R0
	MVO@ R0,R4
	XORI #400,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[1263]             PRINT AT 120 COLOR COL_STATUS, "NEXT TIME           "
	SRCFILE "texas.bas",1263
	MVII #632,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #368,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #88,R0
	MVO@ R0,R4
	XORI #232,R0
	MVO@ R0,R4
	XORI #96,R0
	MVO@ R0,R4
	XORI #416,R0
	MVO@ R0,R4
	XORI #416,R0
	MVO@ R0,R4
	XORI #232,R0
	MVO@ R0,R4
	XORI #32,R0
	MVO@ R0,R4
	XORI #64,R0
	MVO@ R0,R4
	XORI #296,R0
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	NOP
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	NOP
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	NOP
	MVO R4,_screen
	;[1264]             poll_wait = 90
	SRCFILE "texas.bas",1264
	MVII #90,R0
	MVO R0,var_POLL_WAIT
	;[1265]             WHILE poll_wait > 0
	SRCFILE "texas.bas",1265
T326:
	MVI var_POLL_WAIT,R0
	CMPI #0,R0
	BLE T327
	;[1266]                 poll_wait = poll_wait - 1
	SRCFILE "texas.bas",1266
	DECR R0
	MVO R0,var_POLL_WAIT
	;[1267]                 WAIT
	SRCFILE "texas.bas",1267
	CALL _wait
	;[1268]             WEND
	SRCFILE "texas.bas",1268
	B T326
T327:
	;[1269]         END IF
	SRCFILE "texas.bas",1269
T325:
	;[1270]         GOSUB appkey_close
	SRCFILE "texas.bas",1270
	CALL label_APPKEY_CLOSE
	;[1271]     END IF
	SRCFILE "texas.bas",1271
T324:
	;[1272] END
	SRCFILE "texas.bas",1272
	RETURN
	ENDP
	;[1273] 
	SRCFILE "texas.bas",1273
	;[1274] halt:
	SRCFILE "texas.bas",1274
	; HALT
label_HALT:	;[1275]     WAIT
	SRCFILE "texas.bas",1275
	CALL _wait
	;[1276]     GOTO halt
	SRCFILE "texas.bas",1276
	B label_HALT
	;ENDFILE
	SRCFILE "",0
intybasic_keypad:	equ 1	; Forces to include keypad library
intybasic_numbers:	equ 1	; Forces to include numbers library
	;
	; Epilogue for IntyBASIC programs
	; by Oscar Toledo G.  http://nanochess.org/
	;
	; Revision: Jan/30/2014. Moved GRAM code below MOB updates.
	;                        Added comments.
	; Revision: Feb/26/2014. Optimized access to collision registers
	;                        per DZ-Jay suggestion. Added scrolling
	;                        routines with optimization per intvnut
	;                        suggestion. Added border/mask support.
	; Revision: Apr/02/2014. Added support to set MODE (color stack
	;                        or foreground/background), added support
	;                        for SCREEN statement.
	; Revision: Aug/19/2014. Solved bug in bottom scroll, moved an
	;                        extra unneeded line.
	; Revision: Aug/26/2014. Integrated music player and NTSC/PAL
	;                        detection.
	; Revision: Oct/24/2014. Adjust in some comments.
	; Revision: Nov/13/2014. Integrated Joseph Zbiciak's routines
	;                        for printing numbers.
	; Revision: Nov/17/2014. Redesigned MODE support to use a single
	;                        variable.
	; Revision: Nov/21/2014. Added Intellivoice support routines made
	;                        by Joseph Zbiciak.
	; Revision: Dec/11/2014. Optimized keypad decode routines.
	; Revision: Jan/25/2015. Added marker for insertion of ON FRAME GOSUB
	; Revision: Feb/17/2015. Allows to deactivate music player (PLAY NONE)
	; Revision: Apr/21/2015. Accelerates common case of keypad not pressed.
	;                        Added ECS ROM disable code.
	; Revision: Apr/22/2015. Added Joseph Zbiciak accelerated multiplication
	;                        routines.
	; Revision: Jun/04/2015. Optimized play_music (per GroovyBee suggestion)
	; Revision: Jul/25/2015. Added infinite loop at start to avoid crashing
	;                        with empty programs. Solved bug where _color
	;                        didn't started with white.
	; Revision: Aug/20/2015. Moved ECS mapper disable code so nothing gets
	;                        after it (GroovyBee 42K sample code)
	; Revision: Aug/21/2015. Added Joseph Zbiciak routines for JLP Flash
	;                        handling.
	; Revision: Aug/31/2015. Added CPYBLK2 for SCREEN fifth argument.
	; Revision: Sep/01/2015. Defined labels Q1 and Q2 as alias.
	; Revision: Jan/22/2016. Music player allows not to use noise channel
	;                        for drums. Allows setting music volume.
	; Revision: Jan/23/2016. Added jump inside of music (for MUSIC JUMP)
	; Revision: May/03/2016. Preserves current mode in bit 0 of _mode_select
	; Revision: Oct/21/2016. Added C7 in notes table, it was missing. (thanks
	;                        mmarrero)
	; Revision: Jan/09/2018. Initializes scroll offset registers (useful when
	;                        starting from $4800). Uses slightly less space.
	; Revision: Feb/05/2018. Added IV_HUSH.
	; Revision: Mar/01/2018. Added support for music tracker over ECS.
	; Revision: Sep/25/2018. Solved bug in mixer for ECS drums.
	; Revision: Oct/30/2018. Small optimization in music player.
	; Revision: Jan/09/2019. Solved bug where it would play always like
	;                        PLAY SIMPLE NO DRUMS.
	; Revision: May/18/2019. Solved bug where drums failed in ECS side.
	;

	;
	; Avoids empty programs to crash
	; 
stuck:	B stuck

	;
	; Copy screen helper for SCREEN wide statement
	;

CPYBLK2:	PROC
	MOVR R0,R3		; Offset
	MOVR R5,R2
	PULR R0
	PULR R1
	PULR R5
	PULR R4
	PSHR R2
	SUBR R1,R3

@@1:	PSHR R3
	MOVR R1,R3		; Init line copy
@@2:	MVI@ R4,R2		; Copy line
	MVO@ R2,R5
	DECR R3
	BNE @@2
	PULR R3		 ; Add offset to start in next line
	ADDR R3,R4
	SUBR R1,R5
	ADDI #20,R5
	DECR R0		 ; Count lines
	BNE @@1

	RETURN
	ENDP

	;
	; Copy screen helper for SCREEN statement
	;
CPYBLK:	PROC
	BEGIN
	MOVR R3,R4
	MOVR R2,R5

@@1:	MOVR R1,R3	      ; Init line copy
@@2:	MVI@ R4,R2	      ; Copy line
	MVO@ R2,R5
	DECR R3
	BNE @@2
	MVII #20,R3	     ; Add offset to start in next line
	SUBR R1,R3
	ADDR R3,R4
	ADDR R3,R5
	DECR R0		 ; Count lines
	BNE @@1
	RETURN
	ENDP

	;
	; Wait for interruption
	;
_wait:  PROC

    IF DEFINED intybasic_keypad
	MVI $01FF,R0
	COMR R0
	ANDI #$FF,R0
	CMP _cnt1_p0,R0
	BNE @@2
	CMP _cnt1_p1,R0
	BNE @@2
	TSTR R0		; Accelerates common case of key not pressed
	MVII #_keypad_table+13,R4
	BEQ @@4
	MVII #_keypad_table,R4
    REPEAT 6
	CMP@ R4,R0
	BEQ @@4
	CMP@ R4,R0
	BEQ @@4
    ENDR
	INCR R4
@@4:    SUBI #_keypad_table+1,R4
	MVO R4,_cnt1_key

@@2:    MVI _cnt1_p1,R1
	MVO R1,_cnt1_p0
	MVO R0,_cnt1_p1

	MVI $01FE,R0
	COMR R0
	ANDI #$FF,R0
	CMP _cnt2_p0,R0
	BNE @@5
	CMP _cnt2_p1,R0
	BNE @@5
	TSTR R0		; Accelerates common case of key not pressed
	MVII #_keypad_table+13,R4
	BEQ @@7
	MVII #_keypad_table,R4
    REPEAT 6
	CMP@ R4,R0
	BEQ @@7
	CMP@ R4,R0
	BEQ @@7
    ENDR

	INCR R4
@@7:    SUBI #_keypad_table+1,R4
	MVO R4,_cnt2_key

@@5:    MVI _cnt2_p1,R1
	MVO R1,_cnt2_p0
	MVO R0,_cnt2_p1
    ENDI

	CLRR    R0
	MVO     R0,_int	 ; Clears waiting flag
@@1:	CMP     _int,  R0       ; Waits for change
	BEQ     @@1
	JR      R5	      ; Returns
	ENDP

	;
	; Keypad table
	;
_keypad_table:	  PROC
	DECLE $48,$81,$41,$21,$82,$42,$22,$84,$44,$24,$88,$28
	ENDP

_set_isr:	PROC
	MVI@ R5,R0
	MVO R0,ISRVEC
	SWAP R0
	MVO R0,ISRVEC+1
	JR R5
	ENDP

	;
	; Interruption routine
	;
_int_vector:     PROC

    IF DEFINED intybasic_stack
	CMPI #$308,R6
	BNC @@vs
	MVO R0,$20	; Enables display
	MVI $21,R0	; Activates Color Stack mode
	CLRR R0
	MVO R0,$28
	MVO R0,$29
	MVO R0,$2A
	MVO R0,$2B
	MVII #@@vs1,R4
	MVII #$200,R5
	MVII #20,R1
@@vs2:	MVI@ R4,R0
	MVO@ R0,R5
	DECR R1
	BNE @@vs2
	RETURN

	; Stack Overflow message
@@vs1:	DECLE 0,0,0,$33*8+7,$54*8+7,$41*8+7,$43*8+7,$4B*8+7,$00*8+7
	DECLE $4F*8+7,$56*8+7,$45*8+7,$52*8+7,$46*8+7,$4C*8+7
	DECLE $4F*8+7,$57*8+7,0,0,0

@@vs:
    ENDI

	MVII #1,R1
	MVO R1,_int	; Indicates interrupt happened.

	MVI _mode_select,R0
	SARC R0,2
	BNE @@ds
	MVO R0,$20	; Enables display
@@ds:	BNC @@vi14
	MVO R0,$21	; Foreground/background mode
	BNOV @@vi0
	B @@vi15

@@vi14:	MVI $21,R0	; Color stack mode
	BNOV @@vi0
	CLRR R1
	MVI _color,R0
	MVO R0,$28
	SWAP R0
	MVO R0,$29
	SLR R0,2
	SLR R0,2
	MVO R0,$2A
	SWAP R0
	MVO R0,$2B
@@vi15:
	MVO R1,_mode_select
	MVII #7,R0
	MVO R0,_color	   ; Default color for PRINT "string"
@@vi0:

	BEGIN

	MVI _border_color,R0
	MVO     R0,     $2C     ; Border color
	MVI _border_mask,R0
	MVO     R0,     $32     ; Border mask
	;
	; Save collision registers for further use and clear them
	;
	MVII #$18,R4
	MVII #_col0,R5
	MVI@ R4,R0
	MVO@ R0,R5  ; _col0
	MVI@ R4,R0
	MVO@ R0,R5  ; _col1
	MVI@ R4,R0
	MVO@ R0,R5  ; _col2
	MVI@ R4,R0
	MVO@ R0,R5  ; _col3
	MVI@ R4,R0
	MVO@ R0,R5  ; _col4
	MVI@ R4,R0
	MVO@ R0,R5  ; _col5
	MVI@ R4,R0
	MVO@ R0,R5  ; _col6
	MVI@ R4,R0
	MVO@ R0,R5  ; _col7
	
    IF DEFINED intybasic_scroll

	;
	; Scrolling things
	;
	MVI _scroll_x,R0
	MVO R0,$30
	MVI _scroll_y,R0
	MVO R0,$31
    ENDI

	;
	; Updates sprites (MOBs)
	;
	MOVR R5,R4	; MVII #_mobs,R4
	CLRR R5		; X-coordinates
    REPEAT 8
	MVI@ R4,R0
	MVO@ R0,R5
	MVI@ R4,R0
	MVO@ R0,R5
	MVI@ R4,R0
	MVO@ R0,R5
    ENDR
	CLRR R0		; Erase collision bits (R5 = $18)
	MVO@ R0,R5
	MVO@ R0,R5
	MVO@ R0,R5
	MVO@ R0,R5
	MVO@ R0,R5
	MVO@ R0,R5
	MVO@ R0,R5
	MVO@ R0,R5

    IF DEFINED intybasic_music
     	MVI _ntsc,R0
	RRC R0,1	 ; PAL?
	BNC @@vo97      ; Yes, always emit sound
	MVI _music_frame,R0
	INCR R0
	CMPI #6,R0
	BNE @@vo14
	CLRR R0
@@vo14:	MVO R0,_music_frame
	BEQ @@vo15
@@vo97:	CALL _emit_sound
    IF DEFINED intybasic_music_ecs
	CALL _emit_sound_ecs
    ENDI
@@vo15:
    ENDI

	;
	; Detect GRAM definition
	;
	MVI _gram_bitmap,R4
	TSTR R4
	BEQ @@vi1
	MVI _gram_target,R1
	SLL R1,2
	SLL R1,1
	ADDI #$3800,R1
	MOVR R1,R5
	MVI _gram_total,R0
@@vi3:
	MVI@    R4,     R1
	MVO@    R1,     R5
	SWAP    R1
	MVO@    R1,     R5
	MVI@    R4,     R1
	MVO@    R1,     R5
	SWAP    R1
	MVO@    R1,     R5
	MVI@    R4,     R1
	MVO@    R1,     R5
	SWAP    R1
	MVO@    R1,     R5
	MVI@    R4,     R1
	MVO@    R1,     R5
	SWAP    R1
	MVO@    R1,     R5
	DECR R0
	BNE @@vi3
	MVO R0,_gram_bitmap
@@vi1:
	MVI _gram2_bitmap,R4
	TSTR R4
	BEQ @@vii1
	MVI _gram2_target,R1
	SLL R1,2
	SLL R1,1
	ADDI #$3800,R1
	MOVR R1,R5
	MVI _gram2_total,R0
@@vii3:
	MVI@    R4,     R1
	MVO@    R1,     R5
	SWAP    R1
	MVO@    R1,     R5
	MVI@    R4,     R1
	MVO@    R1,     R5
	SWAP    R1
	MVO@    R1,     R5
	MVI@    R4,     R1
	MVO@    R1,     R5
	SWAP    R1
	MVO@    R1,     R5
	MVI@    R4,     R1
	MVO@    R1,     R5
	SWAP    R1
	MVO@    R1,     R5
	DECR R0
	BNE @@vii3
	MVO R0,_gram2_bitmap
@@vii1:

    IF DEFINED intybasic_scroll
	;
	; Frame scroll support
	;
	MVI _scroll_d,R0
	TSTR R0
	BEQ @@vi4
	CLRR R1
	MVO R1,_scroll_d
	DECR R0     ; Left
	BEQ @@vi5
	DECR R0     ; Right
	BEQ @@vi6
	DECR R0     ; Top
	BEQ @@vi7
	DECR R0     ; Bottom
	BEQ @@vi8
	B @@vi4

@@vi5:  MVII #$0200,R4
	MOVR R4,R5
	INCR R5
	MVII #12,R1
@@vi12: MVI@ R4,R2
	MVI@ R4,R3
	REPEAT 8
	MVO@ R2,R5
	MVI@ R4,R2
	MVO@ R3,R5
	MVI@ R4,R3
	ENDR
	MVO@ R2,R5
	MVI@ R4,R2
	MVO@ R3,R5
	MVO@ R2,R5
	INCR R4
	INCR R5
	DECR R1
	BNE @@vi12
	B @@vi4

@@vi6:  MVII #$0201,R4
	MVII #$0200,R5
	MVII #12,R1
@@vi11:
	REPEAT 19
	MVI@ R4,R0
	MVO@ R0,R5
	ENDR
	INCR R4
	INCR R5
	DECR R1
	BNE @@vi11
	B @@vi4
    
	;
	; Complex routine to be ahead of STIC display
	; Moves first the top 6 lines, saves intermediate line
	; Then moves the bottom 6 lines and restores intermediate line
	;
@@vi7:  MVII #$0264,R4
	MVII #5,R1
	MVII #_scroll_buffer,R5
	REPEAT 20
	MVI@ R4,R0
	MVO@ R0,R5
	ENDR
	SUBI #40,R4
	MOVR R4,R5
	ADDI #20,R5
@@vi10:
	REPEAT 20
	MVI@ R4,R0
	MVO@ R0,R5
	ENDR
	SUBI #40,R4
	SUBI #40,R5
	DECR R1
	BNE @@vi10
	MVII #$02C8,R4
	MVII #$02DC,R5
	MVII #5,R1
@@vi13:
	REPEAT 20
	MVI@ R4,R0
	MVO@ R0,R5
	ENDR
	SUBI #40,R4
	SUBI #40,R5
	DECR R1
	BNE @@vi13
	MVII #_scroll_buffer,R4
	REPEAT 20
	MVI@ R4,R0
	MVO@ R0,R5
	ENDR
	B @@vi4

@@vi8:  MVII #$0214,R4
	MVII #$0200,R5
	MVII #$DC/4,R1
@@vi9:  
	REPEAT 4
	MVI@ R4,R0
	MVO@ R0,R5
	ENDR
	DECR R1
	BNE @@vi9
	B @@vi4

@@vi4:
    ENDI

    IF DEFINED intybasic_voice
	;
	; Intellivoice support
	;
	CALL IV_ISR
    ENDI

	;
	; Random number generator
	;
	CALL _next_random

    IF DEFINED intybasic_music
	; Generate sound for next frame
       	MVI _ntsc,R0
	RRC R0,1	 ; PAL?
	BNC @@vo98      ; Yes, always generate sound
	MVI _music_frame,R0
	TSTR R0
	BEQ @@vo16
@@vo98: CALL _generate_music
@@vo16:
    ENDI

	; Increase frame number
	MVI _frame,R0
	INCR R0
	MVO R0,_frame

	; This mark is for ON FRAME GOSUB support

	RETURN
	ENDP

	;
	; Generates the next random number
	;
_next_random:	PROC

MACRO _ROR
	RRC R0,1
	MOVR R0,R2
	SLR R2,2
	SLR R2,2
	ANDI #$0800,R2
	SLR R2,2
	SLR R2,2
	ANDI #$007F,R0
	XORR R2,R0
ENDM
	MVI _rand,R0
	SETC
	_ROR
	XOR _frame,R0
	_ROR
	XOR _rand,R0
	_ROR
	XORI #9,R0
	MVO R0,_rand
	JR R5
	ENDP

    IF DEFINED intybasic_music

	;
	; Music player, comes from my game Princess Quest for Intellivision
	; so it's a practical tracker used in a real game ;) and with enough
	; features.
	;

	; NTSC frequency for notes (based on 3.579545 mhz)
ntsc_note_table:    PROC
	; Silence - 0
	DECLE 0
	; Octave 2 - 1
	DECLE 1721,1621,1532,1434,1364,1286,1216,1141,1076,1017,956,909
	; Octave 3 - 13
	DECLE 854,805,761,717,678,639,605,571,538,508,480,453
	; Octave 4 - 25
	DECLE 427,404,380,360,339,321,302,285,270,254,240,226
	; Octave 5 - 37
	DECLE 214,202,191,180,170,160,151,143,135,127,120,113
	; Octave 6 - 49
	DECLE 107,101,95,90,85,80,76,71,67,64,60,57
	; Octave 7 - 61
	DECLE 54
	; Space for two notes more
	ENDP

	; PAL frequency for notes (based on 4 mhz)
pal_note_table:    PROC
	; Silence - 0
	DECLE 0
	; Octava 2 - 1
	DECLE 1923,1812,1712,1603,1524,1437,1359,1276,1202,1136,1068,1016
	; Octava 3 - 13
	DECLE 954,899,850,801,758,714,676,638,601,568,536,506
	; Octava 4 - 25
	DECLE 477,451,425,402,379,358,338,319,301,284,268,253
	; Octava 5 - 37
	DECLE 239,226,213,201,190,179,169,159,150,142,134,127
	; Octava 6 - 49
	DECLE 120,113,106,100,95,89,84,80,75,71,67,63
	; Octava 7 - 61
	DECLE 60
	; Space for two notes more
	ENDP
    ENDI

	;
	; Music tracker init
	;
_init_music:	PROC
    IF DEFINED intybasic_music
	MVI _ntsc,R0
	RRC R0,1
	MVII #ntsc_note_table,R0
	BC @@0
	MVII #pal_note_table,R0
@@0:	MVO R0,_music_table
	MVII #$38,R0	; $B8 blocks controllers o.O!
	MVO R0,_music_mix
    IF DEFINED intybasic_music_ecs
	MVO R0,_music2_mix
    ENDI
	CLRR R0
    ELSE
	JR R5		; Tracker disabled (no PLAY statement used)
    ENDI
	ENDP

    IF DEFINED intybasic_music
	;
	; Start music
	; R0 = Pointer to music
	;
_play_music:	PROC
	MVII #1,R1
	MOVR R1,R3
	MOVR R0,R2
	BEQ @@1
	MVI@ R2,R3
	INCR R2
@@1:	MVO R2,_music_p
	MVO R2,_music_start
	SWAP R2
	MVO R2,_music_start+1
	MVO R3,_music_t
	MVO R1,_music_tc
	JR R5

	ENDP

	;
	; Generate music
	;
_generate_music:	PROC
	BEGIN
	MVI _music_mix,R0
	ANDI #$C0,R0
	XORI #$38,R0
	MVO R0,_music_mix
    IF DEFINED intybasic_music_ecs
	MVI _music2_mix,R0
	ANDI #$C0,R0
	XORI #$38,R0
	MVO R0,_music2_mix
    ENDI
	CLRR R1			; Turn off volume for the three sound channels
	MVO R1,_music_vol1
	MVO R1,_music_vol2
	MVI _music_tc,R3
	MVO R1,_music_vol3
    IF DEFINED intybasic_music_ecs
	MVO R1,_music2_vol1
	NOP
	MVO R1,_music2_vol2
	MVO R1,_music2_vol3
    ENDI
	DECR R3
	MVO R3,_music_tc
	BNE @@6
	; R3 is zero from here up to @@6
	MVI _music_p,R4
@@15:	TSTR R4		; Silence?
	BEQ @@43	; Keep quiet
@@41:	MVI@ R4,R0
	MVI@ R4,R1
	MVI _music_t,R2
	CMPI #$FA00,R1	; Volume?
	BNC @@42
    IF DEFINED intybasic_music_volume
	BEQ @@40
    ENDI
	CMPI #$FF00,R1	; Speed?
	BEQ @@39
	CMPI #$FB00,R1	; Return?
	BEQ @@38
	CMPI #$FC00,R1	; Gosub?
	BEQ @@37
	CMPI #$FE00,R1	; The end?
	BEQ @@36       ; Keep quiet
;	CMPI #$FD00,R1	; Repeat?
;	BNE @@42
	MVI _music_start+1,R0
	SWAP R0
	ADD _music_start,R0
	MOVR R0,R4
	B @@15

    IF DEFINED intybasic_music_volume
@@40:	
	MVO R0,_music_vol
	B @@41
    ENDI

@@39:	MVO R0,_music_t
	MOVR R0,R2
	B @@41

@@38:	MVI _music_gosub,R4
	B @@15

@@37:	MVO R4,_music_gosub
@@36:	MOVR R0,R4	; Jump, zero will make it quiet
	B @@15

@@43:	MVII #1,R0
	MVO R0,_music_tc
	B @@0
	
@@42: 	MVO R2,_music_tc    ; Restart note time
     	MVO R4,_music_p
     	
	MOVR R0,R2
	ANDI #$FF,R2
	CMPI #$3F,R2	; Sustain note?
	BEQ @@1
	MOVR R2,R4
	ANDI #$3F,R4
	MVO R4,_music_n1	; Note
	MVO R3,_music_s1	; Waveform
	ANDI #$C0,R2
	MVO R2,_music_i1	; Instrument
	
@@1:	SWAP R0
	ANDI #$FF,R0
	CMPI #$3F,R0	; Sustain note?
	BEQ @@2
	MOVR R0,R4
	ANDI #$3F,R4
	MVO R4,_music_n2	; Note
	MVO R3,_music_s2	; Waveform
	ANDI #$C0,R0
	MVO R0,_music_i2	; Instrument
	
@@2:	MOVR R1,R2
	ANDI #$FF,R2
	CMPI #$3F,R2	; Sustain note?
	BEQ @@3
	MOVR R2,R4
	ANDI #$3F,R4
	MVO R4,_music_n3	; Note
	MVO R3,_music_s3	; Waveform
	ANDI #$C0,R2
	MVO R2,_music_i3	; Instrument
	
@@3:	SWAP R1
	MVO R1,_music_n4
	MVO R3,_music_s4
	
    IF DEFINED intybasic_music_ecs
	MVI _music_p,R4
	MVI@ R4,R0
	MVI@ R4,R1
	MVO R4,_music_p

	MOVR R0,R2
	ANDI #$FF,R2
	CMPI #$3F,R2	; Sustain note?
	BEQ @@33
	MOVR R2,R4
	ANDI #$3F,R4
	MVO R4,_music_n5	; Note
	MVO R3,_music_s5	; Waveform
	ANDI #$C0,R2
	MVO R2,_music_i5	; Instrument
	
@@33:	SWAP R0
	ANDI #$FF,R0
	CMPI #$3F,R0	; Sustain note?
	BEQ @@34
	MOVR R0,R4
	ANDI #$3F,R4
	MVO R4,_music_n6	; Note
	MVO R3,_music_s6	; Waveform
	ANDI #$C0,R0
	MVO R0,_music_i6	; Instrument
	
@@34:	MOVR R1,R2
	ANDI #$FF,R2
	CMPI #$3F,R2	; Sustain note?
	BEQ @@35
	MOVR R2,R4
	ANDI #$3F,R4
	MVO R4,_music_n7	; Note
	MVO R3,_music_s7	; Waveform
	ANDI #$C0,R2
	MVO R2,_music_i7	; Instrument
	
@@35:	MOVR R1,R2
	SWAP R2
	MVO R2,_music_n8
	MVO R3,_music_s8
	
    ENDI

	;
	; Construct main voice
	;
@@6:	MVI _music_n1,R3	; Read note
	TSTR R3		; There is note?
	BEQ @@7		; No, jump
	MVI _music_s1,R1
	MVI _music_i1,R2
	MOVR R1,R0
	CALL _note2freq
	MVO R3,_music_freq10	; Note in voice A
	SWAP R3
	MVO R3,_music_freq11
	MVO R1,_music_vol1
	; Increase time for instrument waveform
	INCR R0
	CMPI #$18,R0
	BNE @@20
	SUBI #$08,R0
@@20:	MVO R0,_music_s1

@@7:	MVI _music_n2,R3	; Read note
	TSTR R3		; There is note?
	BEQ @@8		; No, jump
	MVI _music_s2,R1
	MVI _music_i2,R2
	MOVR R1,R0
	CALL _note2freq
	MVO R3,_music_freq20	; Note in voice B
	SWAP R3
	MVO R3,_music_freq21
	MVO R1,_music_vol2
	; Increase time for instrument waveform
	INCR R0
	CMPI #$18,R0
	BNE @@21
	SUBI #$08,R0
@@21:	MVO R0,_music_s2

@@8:	MVI _music_n3,R3	; Read note
	TSTR R3		; There is note?
	BEQ @@9		; No, jump
	MVI _music_s3,R1
	MVI _music_i3,R2
	MOVR R1,R0
	CALL _note2freq
	MVO R3,_music_freq30	; Note in voice C
	SWAP R3
	MVO R3,_music_freq31
	MVO R1,_music_vol3
	; Increase time for instrument waveform
	INCR R0
	CMPI #$18,R0
	BNE @@22
	SUBI #$08,R0
@@22:	MVO R0,_music_s3

@@9:	MVI _music_n4,R0	; Read drum
	DECR R0		; There is drum?
	BMI @@4		; No, jump
	MVI _music_s4,R1
	       		; 1 - Strong
	BNE @@5
	CMPI #3,R1
	BGE @@12
@@10:	MVII #5,R0
	MVO R0,_music_noise
	CALL _activate_drum
	B @@12

@@5:	DECR R0		;2 - Short
	BNE @@11
	TSTR R1
	BNE @@12
	MVII #8,R0
	MVO R0,_music_noise
	CALL _activate_drum
	B @@12

@@11:	;DECR R0	; 3 - Rolling
	;BNE @@12
	CMPI #2,R1
	BLT @@10
	MVI _music_t,R0
	SLR R0,1
	CMPR R0,R1
	BLT @@12
	ADDI #2,R0
	CMPR R0,R1
	BLT @@10
	; Increase time for drum waveform
@@12:   INCR R1
	MVO R1,_music_s4

@@4:
    IF DEFINED intybasic_music_ecs
	;
	; Construct main voice
	;
	MVI _music_n5,R3	; Read note
	TSTR R3		; There is note?
	BEQ @@23	; No, jump
	MVI _music_s5,R1
	MVI _music_i5,R2
	MOVR R1,R0
	CALL _note2freq
	MVO R3,_music2_freq10	; Note in voice A
	SWAP R3
	MVO R3,_music2_freq11
	MVO R1,_music2_vol1
	; Increase time for instrument waveform
	INCR R0
	CMPI #$18,R0
	BNE @@24
	SUBI #$08,R0
@@24:	MVO R0,_music_s5

@@23:	MVI _music_n6,R3	; Read note
	TSTR R3		; There is note?
	BEQ @@25		; No, jump
	MVI _music_s6,R1
	MVI _music_i6,R2
	MOVR R1,R0
	CALL _note2freq
	MVO R3,_music2_freq20	; Note in voice B
	SWAP R3
	MVO R3,_music2_freq21
	MVO R1,_music2_vol2
	; Increase time for instrument waveform
	INCR R0
	CMPI #$18,R0
	BNE @@26
	SUBI #$08,R0
@@26:	MVO R0,_music_s6

@@25:	MVI _music_n7,R3	; Read note
	TSTR R3		; There is note?
	BEQ @@27		; No, jump
	MVI _music_s7,R1
	MVI _music_i7,R2
	MOVR R1,R0
	CALL _note2freq
	MVO R3,_music2_freq30	; Note in voice C
	SWAP R3
	MVO R3,_music2_freq31
	MVO R1,_music2_vol3
	; Increase time for instrument waveform
	INCR R0
	CMPI #$18,R0
	BNE @@28
	SUBI #$08,R0
@@28:	MVO R0,_music_s7

@@27:	MVI _music_n8,R0	; Read drum
	DECR R0		; There is drum?
	BMI @@0		; No, jump
	MVI _music_s8,R1
	       		; 1 - Strong
	BNE @@29
	CMPI #3,R1
	BGE @@31
@@32:	MVII #5,R0
	MVO R0,_music2_noise
	CALL _activate_drum_ecs
	B @@31

@@29:	DECR R0		;2 - Short
	BNE @@30
	TSTR R1
	BNE @@31
	MVII #8,R0
	MVO R0,_music2_noise
	CALL _activate_drum_ecs
	B @@31

@@30:	;DECR R0	; 3 - Rolling
	;BNE @@31
	CMPI #2,R1
	BLT @@32
	MVI _music_t,R0
	SLR R0,1
	CMPR R0,R1
	BLT @@31
	ADDI #2,R0
	CMPR R0,R1
	BLT @@32
	; Increase time for drum waveform
@@31:	INCR R1
	MVO R1,_music_s8

    ENDI
@@0:	RETURN
	ENDP

	;
	; Translates note number to frequency
	; R3 = Note
	; R1 = Position in waveform for instrument
	; R2 = Instrument
	;
_note2freq:	PROC
	ADD _music_table,R3
	MVI@ R3,R3
	SWAP R2
	BEQ _piano_instrument
	RLC R2,1
	BNC _clarinet_instrument
	BPL _flute_instrument
;	BMI _bass_instrument
	ENDP

	;
	; Generates a bass
	;
_bass_instrument:	PROC
	SLL R3,2	; Lower 2 octaves
	ADDI #_bass_volume,R1
	MVI@ R1,R1	; Bass effect
    IF DEFINED intybasic_music_volume
	B _global_volume
    ELSE
	JR R5
    ENDI
	ENDP

_bass_volume:	PROC
	DECLE 12,13,14,14,13,12,12,12
	DECLE 11,11,12,12,11,11,12,12
	DECLE 11,11,12,12,11,11,12,12
	ENDP

	;
	; Generates a piano
	; R3 = Frequency
	; R1 = Waveform position
	;
	; Output:
	; R3 = Frequency.
	; R1 = Volume.
	;
_piano_instrument:	PROC
	ADDI #_piano_volume,R1
	MVI@ R1,R1
    IF DEFINED intybasic_music_volume
	B _global_volume
    ELSE
	JR R5
    ENDI
	ENDP

_piano_volume:	PROC
	DECLE 14,13,13,12,12,11,11,10
	DECLE 10,9,9,8,8,7,7,6
	DECLE 6,6,7,7,6,6,5,5
	ENDP

	;
	; Generate a clarinet
	; R3 = Frequency
	; R1 = Waveform position
	;
	; Output:
	; R3 = Frequency
	; R1 = Volume
	;
_clarinet_instrument:	PROC
	ADDI #_clarinet_vibrato,R1
	ADD@ R1,R3
	CLRC
	RRC R3,1	; Duplicates frequency
	ADCR R3
	ADDI #_clarinet_volume-_clarinet_vibrato,R1
	MVI@ R1,R1
    IF DEFINED intybasic_music_volume
	B _global_volume
    ELSE
	JR R5
    ENDI
	ENDP

_clarinet_vibrato:	PROC
	DECLE 0,0,0,0
	DECLE -2,-4,-2,0
	DECLE 2,4,2,0
	DECLE -2,-4,-2,0
	DECLE 2,4,2,0
	DECLE -2,-4,-2,0
	ENDP

_clarinet_volume:	PROC
	DECLE 13,14,14,13,13,12,12,12
	DECLE 11,11,11,11,12,12,12,12
	DECLE 11,11,11,11,12,12,12,12
	ENDP

	;
	; Generates a flute
	; R3 = Frequency
	; R1 = Waveform position
	;
	; Output:
	; R3 = Frequency
	; R1 = Volume
	;
_flute_instrument:	PROC
	ADDI #_flute_vibrato,R1
	ADD@ R1,R3
	ADDI #_flute_volume-_flute_vibrato,R1
	MVI@ R1,R1
    IF DEFINED intybasic_music_volume
	B _global_volume
    ELSE
	JR R5
    ENDI
	ENDP

_flute_vibrato:	PROC
	DECLE 0,0,0,0
	DECLE 0,1,2,1
	DECLE 0,1,2,1
	DECLE 0,1,2,1
	DECLE 0,1,2,1
	DECLE 0,1,2,1
	ENDP
		 
_flute_volume:	PROC
	DECLE 10,12,13,13,12,12,12,12
	DECLE 11,11,11,11,10,10,10,10
	DECLE 11,11,11,11,10,10,10,10
	ENDP

    IF DEFINED intybasic_music_volume

_global_volume:	PROC
	MVI _music_vol,R2
	ANDI #$0F,R2
	SLL R2,2
	SLL R2,2
	ADDR R1,R2
	ADDI #@@table,R2
	MVI@ R2,R1
	JR R5

@@table:
	DECLE 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	DECLE 0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1
	DECLE 0,0,0,0,1,1,1,1,1,1,1,2,2,2,2,2
	DECLE 0,0,0,1,1,1,1,1,2,2,2,2,2,3,3,3
	DECLE 0,0,1,1,1,1,2,2,2,2,3,3,3,4,4,4
	DECLE 0,0,1,1,1,2,2,2,3,3,3,4,4,4,5,5
	DECLE 0,0,1,1,2,2,2,3,3,4,4,4,5,5,6,6
	DECLE 0,1,1,1,2,2,3,3,4,4,5,5,6,6,7,7
	DECLE 0,1,1,2,2,3,3,4,4,5,5,6,6,7,8,8
	DECLE 0,1,1,2,2,3,4,4,5,5,6,7,7,8,8,9
	DECLE 0,1,1,2,3,3,4,5,5,6,7,7,8,9,9,10
	DECLE 0,1,2,2,3,4,4,5,6,7,7,8,9,10,10,11
	DECLE 0,1,2,2,3,4,5,6,6,7,8,9,10,10,11,12
	DECLE 0,1,2,3,4,4,5,6,7,8,9,10,10,11,12,13
	DECLE 0,1,2,3,4,5,6,7,8,8,9,10,11,12,13,14
	DECLE 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15

	ENDP

    ENDI

    IF DEFINED intybasic_music_ecs
	;
	; Emits sound for ECS
	;
_emit_sound_ecs:	PROC
	MOVR R5,R1
	MVI _music_mode,R2
	SARC R2,1
	BEQ @@6
	MVII #_music2_freq10,R4
	MVII #$00F0,R5
	B _emit_sound.0

@@6:	JR R1

	ENDP

    ENDI

	;
	; Emits sound
	;
_emit_sound:	PROC
	MOVR R5,R1
	MVI _music_mode,R2
	SARC R2,1
	BEQ @@6
	MVII #_music_freq10,R4
	MVII #$01F0,R5
@@0:
	MVI@ R4,R0
	MVO@ R0,R5	; $01F0 - Channel A Period (Low 8 bits of 12)
	MVI@ R4,R0
	MVO@ R0,R5	; $01F1 - Channel B Period (Low 8 bits of 12)
	DECR R2
	BEQ @@1
	MVI@ R4,R0	
	MVO@ R0,R5	; $01F2 - Channel C Period (Low 8 bits of 12)
	INCR R5		; Avoid $01F3 - Enveloped Period (Low 8 bits of 16)
	MVI@ R4,R0
	MVO@ R0,R5	; $01F4 - Channel A Period (High 4 bits of 12)
	MVI@ R4,R0
	MVO@ R0,R5	; $01F5 - Channel B Period (High 4 bits of 12)
	MVI@ R4,R0
	MVO@ R0,R5	; $01F6 - Channel C Period (High 4 bits of 12)
	INCR R5		; Avoid $01F7 - Envelope Period (High 8 bits of 16)
	BC @@2		; Jump if playing with drums
	ADDI #2,R4
	ADDI #3,R5
	B @@3

@@2:	MVI@ R4,R0
	MVO@ R0,R5	; $01F8 - Enable Noise/Tone (bits 3-5 Noise : 0-2 Tone)
	MVI@ R4,R0	
	MVO@ R0,R5	; $01F9 - Noise Period (5 bits)
	INCR R5		; Avoid $01FA - Envelope Type (4 bits)
@@3:	MVI@ R4,R0
	MVO@ R0,R5	; $01FB - Channel A Volume
	MVI@ R4,R0
	MVO@ R0,R5	; $01FC - Channel B Volume
	MVI@ R4,R0
	MVO@ R0,R5	; $01FD - Channel C Volume
	JR R1

@@1:	INCR R4		
	INCR R5		; Avoid $01F2 and $01F3
	INCR R5		; Cannot use ADDI
	MVI@ R4,R0
	MVO@ R0,R5	; $01F4 - Channel A Period (High 4 bits of 12)
	MVI@ R4,R0
	MVO@ R0,R5	; $01F5 - Channel B Period (High 4 bits of 12)
	INCR R4
	INCR R5		; Avoid $01F6 and $01F7
	INCR R5		; Cannot use ADDI
	BC @@4		; Jump if playing with drums
	ADDI #2,R4
	ADDI #3,R5
	B @@5

@@4:	MVI@ R4,R0
	MVO@ R0,R5	; $01F8 - Enable Noise/Tone (bits 3-5 Noise : 0-2 Tone)
	MVI@ R4,R0
	MVO@ R0,R5	; $01F9 - Noise Period (5 bits)
	INCR R5		; Avoid $01FA - Envelope Type (4 bits)
@@5:	MVI@ R4,R0
	MVO@ R0,R5	; $01FB - Channel A Volume
	MVI@ R4,R0
	MVO@ R0,R5	; $01FC - Channel B Volume
@@6:	JR R1
	ENDP

	;
	; Activates drum
	;
_activate_drum:	PROC
    IF DEFINED intybasic_music_volume
	BEGIN
    ENDI
	MVI _music_mode,R2
	SARC R2,1	; PLAY NO DRUMS?
	BNC @@0		; Yes, jump
	MVI _music_vol1,R0
	TSTR R0
	BNE @@1
	MVII #11,R1
    IF DEFINED intybasic_music_volume
	CALL _global_volume
    ENDI
	MVO R1,_music_vol1
	MVI _music_mix,R0
	ANDI #$F6,R0
	XORI #$01,R0
	MVO R0,_music_mix
    IF DEFINED intybasic_music_volume
	RETURN
    ELSE
	JR R5
    ENDI

@@1:    MVI _music_vol2,R0
	TSTR R0
	BNE @@2
	MVII #11,R1
    IF DEFINED intybasic_music_volume
	CALL _global_volume
    ENDI
	MVO R1,_music_vol2
	MVI _music_mix,R0
	ANDI #$ED,R0
	XORI #$02,R0
	MVO R0,_music_mix
    IF DEFINED intybasic_music_volume
	RETURN
    ELSE
	JR R5
    ENDI

@@2:    DECR R2		; PLAY SIMPLE?
	BEQ @@3		; Yes, jump
	MVI _music_vol3,R0
	TSTR R0
	BNE @@3
	MVII #11,R1
    IF DEFINED intybasic_music_volume
	CALL _global_volume
    ENDI
	MVO R1,_music_vol3
	MVI _music_mix,R0
	ANDI #$DB,R0
	XORI #$04,R0
	MVO R0,_music_mix
    IF DEFINED intybasic_music_volume
	RETURN
    ELSE
	JR R5
    ENDI

@@3:    MVI _music_mix,R0
	ANDI #$EF,R0
	MVO R0,_music_mix
@@0:	
    IF DEFINED intybasic_music_volume
	RETURN
    ELSE
	JR R5
    ENDI

	ENDP

    IF DEFINED intybasic_music_ecs
	;
	; Activates drum
	;
_activate_drum_ecs:	PROC
    IF DEFINED intybasic_music_volume
	BEGIN
    ENDI
	MVI _music_mode,R2
	SARC R2,1	; PLAY NO DRUMS?
	BNC @@0		; Yes, jump
	MVI _music2_vol1,R0
	TSTR R0
	BNE @@1
	MVII #11,R1
    IF DEFINED intybasic_music_volume
	CALL _global_volume
    ENDI
	MVO R1,_music2_vol1
	MVI _music2_mix,R0
	ANDI #$F6,R0
	XORI #$01,R0
	MVO R0,_music2_mix
    IF DEFINED intybasic_music_volume
	RETURN
    ELSE
	JR R5
    ENDI

@@1:    MVI _music2_vol2,R0
	TSTR R0
	BNE @@2
	MVII #11,R1
    IF DEFINED intybasic_music_volume
	CALL _global_volume
    ENDI
	MVO R1,_music2_vol2
	MVI _music2_mix,R0
	ANDI #$ED,R0
	XORI #$02,R0
	MVO R0,_music2_mix
    IF DEFINED intybasic_music_volume
	RETURN
    ELSE
	JR R5
    ENDI

@@2:    DECR R2		; PLAY SIMPLE?
	BEQ @@3		; Yes, jump
	MVI _music2_vol3,R0
	TSTR R0
	BNE @@3
	MVII #11,R1
    IF DEFINED intybasic_music_volume
	CALL _global_volume
    ENDI
	MVO R1,_music2_vol3
	MVI _music2_mix,R0
	ANDI #$DB,R0
	XORI #$04,R0
	MVO R0,_music2_mix
    IF DEFINED intybasic_music_volume
	RETURN
    ELSE
	JR R5
    ENDI

@@3:    MVI _music2_mix,R0
	ANDI #$EF,R0
	MVO R0,_music2_mix
@@0:	
    IF DEFINED intybasic_music_volume
	RETURN
    ELSE
	JR R5
    ENDI

	ENDP

    ENDI

    ENDI
    
    IF DEFINED intybasic_numbers

	;
	; Following code from as1600 libraries, prnum16.asm
	; Public domain by Joseph Zbiciak
	;

;* ======================================================================== *;
;*  These routines are placed into the public domain by their author.  All  *;
;*  copyright rights are hereby relinquished on the routines and data in    *;
;*  this file.  -- Joseph Zbiciak, 2008				     *;
;* ======================================================================== *;

;; ======================================================================== ;;
;;  _PW10								   ;;
;;      Lookup table holding the first 5 powers of 10 (1 thru 10000) as     ;;
;;      16-bit numbers.						     ;;
;; ======================================================================== ;;
_PW10   PROC    ; 0 thru 10000
	DECLE   10000, 1000, 100, 10, 1, 0
	ENDP

;; ======================================================================== ;;
;;  PRNUM16.l     -- Print an unsigned 16-bit number left-justified.	;;
;;  PRNUM16.b     -- Print an unsigned 16-bit number with leading blanks.   ;;
;;  PRNUM16.z     -- Print an unsigned 16-bit number with leading zeros.    ;;
;;									  ;;
;;  AUTHOR								  ;;
;;      Joseph Zbiciak  <im14u2c AT globalcrossing DOT net>		 ;;
;;									  ;;
;;  REVISION HISTORY							;;
;;      30-Mar-2003 Initial complete revision			       ;;
;;									  ;;
;;  INPUTS for all variants						 ;;
;;      R0  Number to print.						;;
;;      R2  Width of field.  Ignored by PRNUM16.l.			  ;;
;;      R3  Format word, added to digits to set the color.		  ;;
;;	  Note:  Bit 15 MUST be cleared when building with PRNUM32.       ;;
;;      R4  Pointer to location on screen to print number		   ;;
;;									  ;;
;;  OUTPUTS								 ;;
;;      R0  Zeroed							  ;;
;;      R1  Unmodified						      ;;
;;      R2  Unmodified						      ;;
;;      R3  Unmodified						      ;;
;;      R4  Points to first character after field.			  ;;
;;									  ;;
;;  DESCRIPTION							     ;;
;;      These routines print unsigned 16-bit numbers in a field up to 5     ;;
;;      positions wide.  The number is printed either in left-justified     ;;
;;      or right-justified format.  Right-justified numbers are padded      ;;
;;      with leading blanks or leading zeros.  Left-justified numbers       ;;
;;      are not padded on the right.					;;
;;									  ;;
;;      This code handles fields wider than 5 characters, padding with      ;;
;;      zeros or blanks as necessary.				       ;;
;;									  ;;
;;	      Routine      Value(hex)     Field	Output	     ;;
;;	      ----------   ----------   ----------   ----------	   ;;
;;	      PRNUM16.l      $0045	 n/a	"69"		;;
;;	      PRNUM16.b      $0045	  4	 "  69"	      ;;
;;	      PRNUM16.b      $0045	  6	 "    69"	    ;;
;;	      PRNUM16.z      $0045	  4	 "0069"	      ;;
;;	      PRNUM16.z      $0045	  6	 "000069"	    ;;
;;									  ;;
;;  TECHNIQUES							      ;;
;;      This routine uses repeated subtraction to divide the number	 ;;
;;      to display by various powers of 10.  This is cheaper than a	 ;;
;;      full divide, at least when the input number is large.  It's	 ;;
;;      also easier to get right.  :-)				      ;;
;;									  ;;
;;      The printing routine first pads out fields wider than 5 spaces      ;;
;;      with zeros or blanks as requested.  It then scans the power-of-10   ;;
;;      table looking for the first power of 10 that is <= the number to    ;;
;;      display.  While scanning for this power of 10, it outputs leading   ;;
;;      blanks or zeros, if requested.  This eliminates "leading digit"     ;;
;;      logic from the main digit loop.				     ;;
;;									  ;;
;;      Once in the main digit loop, we discover the value of each digit    ;;
;;      by repeated subtraction.  We build up our digit value while	 ;;
;;      subtracting the power-of-10 repeatedly.  We iterate until we go     ;;
;;      a step too far, and then we add back on power-of-10 to restore      ;;
;;      the remainder.						      ;;
;;									  ;;
;;  NOTES								   ;;
;;      The left-justified variant ignores field width.		     ;;
;;									  ;;
;;      The code is fully reentrant.					;;
;;									  ;;
;;      This code does not handle numbers which are too large to be	 ;;
;;      displayed in the provided field.  If the number is too large,       ;;
;;      non-digit characters will be displayed in the initial digit	 ;;
;;      position.  Also, the run time of this routine may get excessively   ;;
;;      large, depending on the magnitude of the overflow.		  ;;
;;									  ;;
;;      When using with PRNUM32, one must either include PRNUM32 before     ;;
;;      this function, or define the symbol _WITH_PRNUM32.  PRNUM32	 ;;
;;      needs a tiny bit of support from PRNUM16 to handle numbers in       ;;
;;      the range 65536...99999 correctly.				  ;;
;;									  ;;
;;  CODESIZE								;;
;;      73 words, including power-of-10 table			       ;;
;;      80 words, if compiled with PRNUM32.				 ;;
;;									  ;;
;;      To save code size, you can define the following symbols to omit     ;;
;;      some variants:						      ;;
;;									  ;;
;;	  _NO_PRNUM16.l:   Disables PRNUM16.l.  Saves 10 words	    ;;
;;	  _NO_PRNUM16.b:   Disables PRNUM16.b.  Saves 3 words.	    ;;
;;									  ;;
;;      Defining both symbols saves 17 words total, because it omits	;;
;;      some code shared by both routines.				  ;;
;;									  ;;
;;  STACK USAGE							     ;;
;;      This function uses up to 4 words of stack space.		    ;;
;; ======================================================================== ;;

PRNUM16 PROC

    
	;; ---------------------------------------------------------------- ;;
	;;  PRNUM16.l:  Print unsigned, left-justified.		     ;;
	;; ---------------------------------------------------------------- ;;
@@l:    PSHR    R5	      ; save return address
@@l1:   MVII    #$1,    R5      ; set R5 to 1 to counteract screen ptr update
				; in the 'find initial power of 10' loop
	PSHR    R2
	MVII    #5,     R2      ; force effective field width to 5.
	B       @@z2

	;; ---------------------------------------------------------------- ;;
	;;  PRNUM16.b:  Print unsigned with leading blanks.		 ;;
	;; ---------------------------------------------------------------- ;;
@@b:    PSHR    R5
@@b1:   CLRR    R5	      ; let the blank loop do its thing
	INCR    PC	      ; skip the PSHR R5

	;; ---------------------------------------------------------------- ;;
	;;  PRNUM16.z:  Print unsigned with leading zeros.		  ;;
	;; ---------------------------------------------------------------- ;;
@@z:    PSHR    R5
@@z1:   PSHR    R2
@@z2:   PSHR    R1

	;; ---------------------------------------------------------------- ;;
	;;  Find the initial power of 10 to use for display.		;;
	;;  Note:  For fields wider than 5, fill the extra spots above 5    ;;
	;;  with blanks or zeros as needed.				 ;;
	;; ---------------------------------------------------------------- ;;
	MVII    #_PW10+5,R1     ; Point to end of power-of-10 table
	SUBR    R2,     R1      ; Subtract the field width to get right power
	PSHR    R3	      ; save format word

	CMPI    #2,     R5      ; are we leading with zeros?
	BNC     @@lblnk	 ; no:  then do the loop w/ blanks

	CLRR    R5	      ; force R5==0
	ADDI    #$80,   R3      ; yes: do the loop with zeros
	B       @@lblnk
    

@@llp   MVO@    R3,     R4      ; print a blank/zero

	SUBR    R5,     R4      ; rewind pointer if needed.

	INCR    R1	      ; get next power of 10
@@lblnk DECR    R2	      ; decrement available digits
	BEQ     @@ldone
	CMPI    #5,     R2      ; field too wide?
	BGE     @@llp	   ; just force blanks/zeros 'till we're narrower.
	CMP@    R1,     R0      ; Is this power of 10 too big?
	BNC     @@llp	   ; Yes:  Put a blank and go to next

@@ldone PULR    R3	      ; restore format word

	;; ---------------------------------------------------------------- ;;
	;;  The digit loop prints at least one digit.  It discovers digits  ;;
	;;  by repeated subtraction.					;;
	;; ---------------------------------------------------------------- ;;
@@digit TSTR    R0	      ; If the number is zero, print zero and leave
	BNEQ    @@dig1	  ; no: print the number

	MOVR    R3,     R5      ;\    
	ADDI    #$80,   R5      ; |-- print a 0 there.
	MVO@    R5,     R4      ;/    
	B       @@done

@@dig1:
    
@@nxdig MOVR    R3,     R5      ; save display format word
@@cont: ADDI    #$80-8, R5      ; start our digit as one just before '0'
@@spcl:
 
	;; ---------------------------------------------------------------- ;;
	;;  Divide by repeated subtraction.  This divide is constructed     ;;
	;;  to go "one step too far" and then back up.		      ;;
	;; ---------------------------------------------------------------- ;;
@@div:  ADDI    #8,     R5      ; increment our digit
	SUB@    R1,     R0      ; subtract power of 10
	BC      @@div	   ; loop until we go too far
	ADD@    R1,     R0      ; add back the extra power of 10.

	MVO@    R5,     R4      ; display the digit.

	INCR    R1	      ; point to next power of 10
	DECR    R2	      ; any room left in field?
	BPL     @@nxdig	 ; keep going until R2 < 0.

@@done: PULR    R1	      ; restore R1
	PULR    R2	      ; restore R2
	PULR    PC	      ; return

	ENDP
	
    ENDI

    IF DEFINED intybasic_voice
;;==========================================================================;;
;;  SP0256-AL2 Allophones						   ;;
;;									  ;;
;;  This file contains the allophone set that was obtained from an	  ;;
;;  SP0256-AL2.  It is being provided for your convenience.		 ;;
;;									  ;;
;;  The directory "al2" contains a series of assembly files, each one       ;;
;;  containing a single allophone.  This series of files may be useful in   ;;
;;  situations where space is at a premium.				 ;;
;;									  ;;
;;  Consult the Archer SP0256-AL2 documentation (under doc/programming)     ;;
;;  for more information about SP0256-AL2's allophone library.	      ;;
;;									  ;;
;; ------------------------------------------------------------------------ ;;
;;									  ;;
;;  Copyright information:						  ;;
;;									  ;;
;;  The allophone data below was extracted from the SP0256-AL2 ROM image.   ;;
;;  The SP0256-AL2 allophones are NOT in the public domain, nor are they    ;;
;;  placed under the GNU General Public License.  This program is	   ;;
;;  distributed in the hope that it will be useful, but WITHOUT ANY	 ;;
;;  WARRANTY; without even the implied warranty of MERCHANTABILITY or       ;;
;;  FITNESS FOR A PARTICULAR PURPOSE.				       ;;
;;									  ;;
;;  Microchip, Inc. retains the copyright to the data and algorithms	;;
;;  contained in the SP0256-AL2.  This speech data is distributed with      ;;
;;  explicit permission from Microchip, Inc.  All such redistributions      ;;
;;  must retain this notice of copyright.				   ;;
;;									  ;;
;;  No copyright claims are made on this data by the author(s) of SDK1600.  ;;
;;  Please see http://spatula-city.org/~im14u2c/sp0256-al2/ for details.    ;;
;;									  ;;
;;==========================================================================;;

;; ------------------------------------------------------------------------ ;;
_AA:
    DECLE   _AA.end - _AA - 1
    DECLE   $0318, $014C, $016F, $02CE, $03AF, $015F, $01B1, $008E
    DECLE   $0088, $0392, $01EA, $024B, $03AA, $039B, $000F, $0000
_AA.end:  ; 16 decles
;; ------------------------------------------------------------------------ ;;
_AE1:
    DECLE   _AE1.end - _AE1 - 1
    DECLE   $0118, $038E, $016E, $01FC, $0149, $0043, $026F, $036E
    DECLE   $01CC, $0005, $0000
_AE1.end:  ; 11 decles
;; ------------------------------------------------------------------------ ;;
_AO:
    DECLE   _AO.end - _AO - 1
    DECLE   $0018, $010E, $016F, $0225, $00C6, $02C4, $030F, $0160
    DECLE   $024B, $0005, $0000
_AO.end:  ; 11 decles
;; ------------------------------------------------------------------------ ;;
_AR:
    DECLE   _AR.end - _AR - 1
    DECLE   $0218, $010C, $016E, $001E, $000B, $0091, $032F, $00DE
    DECLE   $018B, $0095, $0003, $0238, $0027, $01E0, $03E8, $0090
    DECLE   $0003, $01C7, $0020, $03DE, $0100, $0190, $01CA, $02AB
    DECLE   $00B7, $004A, $0386, $0100, $0144, $02B6, $0024, $0320
    DECLE   $0011, $0041, $01DF, $0316, $014C, $016E, $001E, $00C4
    DECLE   $02B2, $031E, $0264, $02AA, $019D, $01BE, $000B, $00F0
    DECLE   $006A, $01CE, $00D6, $015B, $03B5, $03E4, $0000, $0380
    DECLE   $0007, $0312, $03E8, $030C, $016D, $02EE, $0085, $03C2
    DECLE   $03EC, $0283, $024A, $0005, $0000
_AR.end:  ; 69 decles
;; ------------------------------------------------------------------------ ;;
_AW:
    DECLE   _AW.end - _AW - 1
    DECLE   $0010, $01CE, $016E, $02BE, $0375, $034F, $0220, $0290
    DECLE   $008A, $026D, $013F, $01D5, $0316, $029F, $02E2, $018A
    DECLE   $0170, $0035, $00BD, $0000, $0000
_AW.end:  ; 21 decles
;; ------------------------------------------------------------------------ ;;
_AX:
    DECLE   _AX.end - _AX - 1
    DECLE   $0218, $02CD, $016F, $02F5, $0386, $00C2, $00CD, $0094
    DECLE   $010C, $0005, $0000
_AX.end:  ; 11 decles
;; ------------------------------------------------------------------------ ;;
_AY:
    DECLE   _AY.end - _AY - 1
    DECLE   $0110, $038C, $016E, $03B7, $03B3, $02AF, $0221, $009E
    DECLE   $01AA, $01B3, $00BF, $02E7, $025B, $0354, $00DA, $017F
    DECLE   $018A, $03F3, $00AF, $02D5, $0356, $027F, $017A, $01FB
    DECLE   $011E, $01B9, $03E5, $029F, $025A, $0076, $0148, $0124
    DECLE   $003D, $0000
_AY.end:  ; 34 decles
;; ------------------------------------------------------------------------ ;;
_BB1:
    DECLE   _BB1.end - _BB1 - 1
    DECLE   $0318, $004C, $016C, $00FB, $00C7, $0144, $002E, $030C
    DECLE   $010E, $018C, $01DC, $00AB, $00C9, $0268, $01F7, $021D
    DECLE   $01B3, $0098, $0000
_BB1.end:  ; 19 decles
;; ------------------------------------------------------------------------ ;;
_BB2:
    DECLE   _BB2.end - _BB2 - 1
    DECLE   $00F4, $0046, $0062, $0200, $0221, $03E4, $0087, $016F
    DECLE   $02A6, $02B7, $0212, $0326, $0368, $01BF, $0338, $0196
    DECLE   $0002
_BB2.end:  ; 17 decles
;; ------------------------------------------------------------------------ ;;
_CH:
    DECLE   _CH.end - _CH - 1
    DECLE   $00F5, $0146, $0052, $0000, $032A, $0049, $0032, $02F2
    DECLE   $02A5, $0000, $026D, $0119, $0124, $00F6, $0000
_CH.end:  ; 15 decles
;; ------------------------------------------------------------------------ ;;
_DD1:
    DECLE   _DD1.end - _DD1 - 1
    DECLE   $0318, $034C, $016E, $0397, $01B9, $0020, $02B1, $008E
    DECLE   $0349, $0291, $01D8, $0072, $0000
_DD1.end:  ; 13 decles
;; ------------------------------------------------------------------------ ;;
_DD2:
    DECLE   _DD2.end - _DD2 - 1
    DECLE   $00F4, $00C6, $00F2, $0000, $0129, $00A6, $0246, $01F3
    DECLE   $02C6, $02B7, $028E, $0064, $0362, $01CF, $0379, $01D5
    DECLE   $0002
_DD2.end:  ; 17 decles
;; ------------------------------------------------------------------------ ;;
_DH1:
    DECLE   _DH1.end - _DH1 - 1
    DECLE   $0018, $034F, $016D, $030B, $0306, $0363, $017E, $006A
    DECLE   $0164, $019E, $01DA, $00CB, $00E8, $027A, $03E8, $01D7
    DECLE   $0173, $00A1, $0000
_DH1.end:  ; 19 decles
;; ------------------------------------------------------------------------ ;;
_DH2:
    DECLE   _DH2.end - _DH2 - 1
    DECLE   $0119, $034C, $016D, $030B, $0306, $0363, $017E, $006A
    DECLE   $0164, $019E, $01DA, $00CB, $00E8, $027A, $03E8, $01D7
    DECLE   $0173, $00A1, $0000
_DH2.end:  ; 19 decles
;; ------------------------------------------------------------------------ ;;
_EH:
    DECLE   _EH.end - _EH - 1
    DECLE   $0218, $02CD, $016F, $0105, $014B, $0224, $02CF, $0274
    DECLE   $014C, $0005, $0000
_EH.end:  ; 11 decles
;; ------------------------------------------------------------------------ ;;
_EL:
    DECLE   _EL.end - _EL - 1
    DECLE   $0118, $038D, $016E, $011C, $008B, $03D2, $030F, $0262
    DECLE   $006C, $019D, $01CC, $022B, $0170, $0078, $03FE, $0018
    DECLE   $0183, $03A3, $010D, $016E, $012E, $00C6, $00C3, $0300
    DECLE   $0060, $000D, $0005, $0000
_EL.end:  ; 28 decles
;; ------------------------------------------------------------------------ ;;
_ER1:
    DECLE   _ER1.end - _ER1 - 1
    DECLE   $0118, $034C, $016E, $001C, $0089, $01C3, $034E, $03E6
    DECLE   $00AB, $0095, $0001, $0000, $03FC, $0381, $0000, $0188
    DECLE   $01DA, $00CB, $00E7, $0048, $03A6, $0244, $016C, $01A8
    DECLE   $03E4, $0000, $0002, $0001, $00FC, $01DA, $02E4, $0000
    DECLE   $0002, $0008, $0200, $0217, $0164, $0000, $000E, $0038
    DECLE   $0014, $01EA, $0264, $0000, $0002, $0048, $01EC, $02F1
    DECLE   $03CC, $016D, $021E, $0048, $00C2, $034E, $036A, $000D
    DECLE   $008D, $000B, $0200, $0047, $0022, $03A8, $0000, $0000
_ER1.end:  ; 64 decles
;; ------------------------------------------------------------------------ ;;
_ER2:
    DECLE   _ER2.end - _ER2 - 1
    DECLE   $0218, $034C, $016E, $001C, $0089, $01C3, $034E, $03E6
    DECLE   $00AB, $0095, $0001, $0000, $03FC, $0381, $0000, $0190
    DECLE   $01D8, $00CB, $00E7, $0058, $01A6, $0244, $0164, $02A9
    DECLE   $0024, $0000, $0000, $0007, $0201, $02F8, $02E4, $0000
    DECLE   $0002, $0001, $00FC, $02DA, $0024, $0000, $0002, $0008
    DECLE   $0200, $0217, $0024, $0000, $000E, $0038, $0014, $03EA
    DECLE   $03A4, $0000, $0002, $0048, $01EC, $03F1, $038C, $016D
    DECLE   $021E, $0048, $00C2, $034E, $036A, $000D, $009D, $0003
    DECLE   $0200, $0047, $0022, $03A8, $0000, $0000
_ER2.end:  ; 70 decles
;; ------------------------------------------------------------------------ ;;
_EY:
    DECLE   _EY.end - _EY - 1
    DECLE   $0310, $038C, $016E, $02A7, $00BB, $0160, $0290, $0094
    DECLE   $01CA, $03A9, $00C1, $02D7, $015B, $01D4, $03CE, $02FF
    DECLE   $00EA, $03E7, $0041, $0277, $025B, $0355, $03C9, $0103
    DECLE   $02EA, $03E4, $003F, $0000
_EY.end:  ; 28 decles
;; ------------------------------------------------------------------------ ;;
_FF:
    DECLE   _FF.end - _FF - 1
    DECLE   $0119, $03C8, $0000, $00A7, $0094, $0138, $01C6, $0000
_FF.end:  ; 8 decles
;; ------------------------------------------------------------------------ ;;
_GG1:
    DECLE   _GG1.end - _GG1 - 1
    DECLE   $00F4, $00C6, $00C2, $0200, $0015, $03FE, $0283, $01FD
    DECLE   $01E6, $00B7, $030A, $0364, $0331, $017F, $033D, $0215
    DECLE   $0002
_GG1.end:  ; 17 decles
;; ------------------------------------------------------------------------ ;;
_GG2:
    DECLE   _GG2.end - _GG2 - 1
    DECLE   $00F4, $0106, $0072, $0300, $0021, $0308, $0039, $0173
    DECLE   $00C6, $00B7, $037E, $03A3, $0319, $0177, $0036, $0217
    DECLE   $0002
_GG2.end:  ; 17 decles
;; ------------------------------------------------------------------------ ;;
_GG3:
    DECLE   _GG3.end - _GG3 - 1
    DECLE   $00F8, $0146, $00F2, $0100, $0132, $03A8, $0055, $01F5
    DECLE   $00A6, $02B7, $0291, $0326, $0368, $0167, $023A, $01C6
    DECLE   $0002
_GG3.end:  ; 17 decles
;; ------------------------------------------------------------------------ ;;
_HH1:
    DECLE   _HH1.end - _HH1 - 1
    DECLE   $0218, $01C9, $0000, $0095, $0127, $0060, $01D6, $0213
    DECLE   $0002, $01AE, $033E, $01A0, $03C4, $0122, $0001, $0218
    DECLE   $01E4, $03FD, $0019, $0000
_HH1.end:  ; 20 decles
;; ------------------------------------------------------------------------ ;;
_HH2:
    DECLE   _HH2.end - _HH2 - 1
    DECLE   $0218, $00CB, $0000, $0086, $000F, $0240, $0182, $031A
    DECLE   $02DB, $0008, $0293, $0067, $00BD, $01E0, $0092, $000C
    DECLE   $0000
_HH2.end:  ; 17 decles
;; ------------------------------------------------------------------------ ;;
_IH:
    DECLE   _IH.end - _IH - 1
    DECLE   $0118, $02CD, $016F, $0205, $0144, $02C3, $00FE, $031A
    DECLE   $000D, $0005, $0000
_IH.end:  ; 11 decles
;; ------------------------------------------------------------------------ ;;
_IY:
    DECLE   _IY.end - _IY - 1
    DECLE   $0318, $02CC, $016F, $0008, $030B, $01C3, $0330, $0178
    DECLE   $002B, $019D, $01F6, $018B, $01E1, $0010, $020D, $0358
    DECLE   $015F, $02A4, $02CC, $016F, $0109, $030B, $0193, $0320
    DECLE   $017A, $034C, $009C, $0017, $0001, $0200, $03C1, $0020
    DECLE   $00A7, $001D, $0001, $0104, $003D, $0040, $01A7, $01CA
    DECLE   $018B, $0160, $0078, $01F6, $0343, $01C7, $0090, $0000
_IY.end:  ; 48 decles
;; ------------------------------------------------------------------------ ;;
_JH:
    DECLE   _JH.end - _JH - 1
    DECLE   $0018, $0149, $0001, $00A4, $0321, $0180, $01F4, $039A
    DECLE   $02DC, $023C, $011A, $0047, $0200, $0001, $018E, $034E
    DECLE   $0394, $0356, $02C1, $010C, $03FD, $0129, $00B7, $01BA
    DECLE   $0000
_JH.end:  ; 25 decles
;; ------------------------------------------------------------------------ ;;
_KK1:
    DECLE   _KK1.end - _KK1 - 1
    DECLE   $00F4, $00C6, $00D2, $0000, $023A, $03E0, $02D1, $02E5
    DECLE   $0184, $0200, $0041, $0210, $0188, $00C5, $0000
_KK1.end:  ; 15 decles
;; ------------------------------------------------------------------------ ;;
_KK2:
    DECLE   _KK2.end - _KK2 - 1
    DECLE   $021D, $023C, $0211, $003C, $0180, $024D, $0008, $032B
    DECLE   $025B, $002D, $01DC, $01E3, $007A, $0000
_KK2.end:  ; 14 decles
;; ------------------------------------------------------------------------ ;;
_KK3:
    DECLE   _KK3.end - _KK3 - 1
    DECLE   $00F7, $0046, $01D2, $0300, $0131, $006C, $006E, $00F1
    DECLE   $00E4, $0000, $025A, $010D, $0110, $01F9, $014A, $0001
    DECLE   $00B5, $01A2, $00D8, $01CE, $0000
_KK3.end:  ; 21 decles
;; ------------------------------------------------------------------------ ;;
_LL:
    DECLE   _LL.end - _LL - 1
    DECLE   $0318, $038C, $016D, $029E, $0333, $0260, $0221, $0294
    DECLE   $01C4, $0299, $025A, $00E6, $014C, $012C, $0031, $0000
_LL.end:  ; 16 decles
;; ------------------------------------------------------------------------ ;;
_MM:
    DECLE   _MM.end - _MM - 1
    DECLE   $0210, $034D, $016D, $03F5, $00B0, $002E, $0220, $0290
    DECLE   $03CE, $02B6, $03AA, $00F3, $00CF, $015D, $016E, $0000
_MM.end:  ; 16 decles
;; ------------------------------------------------------------------------ ;;
_NG1:
    DECLE   _NG1.end - _NG1 - 1
    DECLE   $0118, $03CD, $016E, $00DC, $032F, $01BF, $01E0, $0116
    DECLE   $02AB, $029A, $0358, $01DB, $015B, $01A7, $02FD, $02B1
    DECLE   $03D2, $0356, $0000
_NG1.end:  ; 19 decles
;; ------------------------------------------------------------------------ ;;
_NN1:
    DECLE   _NN1.end - _NN1 - 1
    DECLE   $0318, $03CD, $016C, $0203, $0306, $03C3, $015F, $0270
    DECLE   $002A, $009D, $000D, $0248, $01B4, $0120, $01E1, $00C8
    DECLE   $0003, $0040, $0000, $0080, $015F, $0006, $0000
_NN1.end:  ; 23 decles
;; ------------------------------------------------------------------------ ;;
_NN2:
    DECLE   _NN2.end - _NN2 - 1
    DECLE   $0018, $034D, $016D, $0203, $0306, $03C3, $015F, $0270
    DECLE   $002A, $0095, $0003, $0248, $01B4, $0120, $01E1, $0090
    DECLE   $000B, $0040, $0000, $0080, $015F, $019E, $01F6, $028B
    DECLE   $00E0, $0266, $03F6, $01D8, $0143, $01A8, $0024, $00C0
    DECLE   $0080, $0000, $01E6, $0321, $0024, $0260, $000A, $0008
    DECLE   $03FE, $0000, $0000
_NN2.end:  ; 43 decles
;; ------------------------------------------------------------------------ ;;
_OR2:
    DECLE   _OR2.end - _OR2 - 1
    DECLE   $0218, $018C, $016D, $02A6, $03AB, $004F, $0301, $0390
    DECLE   $02EA, $0289, $0228, $0356, $01CF, $02D5, $0135, $007D
    DECLE   $02B5, $02AF, $024A, $02E2, $0153, $0167, $0333, $02A9
    DECLE   $02B3, $039A, $0351, $0147, $03CD, $0339, $02DA, $0000
_OR2.end:  ; 32 decles
;; ------------------------------------------------------------------------ ;;
_OW:
    DECLE   _OW.end - _OW - 1
    DECLE   $0310, $034C, $016E, $02AE, $03B1, $00CF, $0304, $0192
    DECLE   $018A, $022B, $0041, $0277, $015B, $0395, $03D1, $0082
    DECLE   $03CE, $00B6, $03BB, $02DA, $0000
_OW.end:  ; 21 decles
;; ------------------------------------------------------------------------ ;;
_OY:
    DECLE   _OY.end - _OY - 1
    DECLE   $0310, $014C, $016E, $02A6, $03AF, $00CF, $0304, $0192
    DECLE   $03CA, $01A8, $007F, $0155, $02B4, $027F, $00E2, $036A
    DECLE   $031F, $035D, $0116, $01D5, $02F4, $025F, $033A, $038A
    DECLE   $014F, $01B5, $03D5, $0297, $02DA, $03F2, $0167, $0124
    DECLE   $03FB, $0001
_OY.end:  ; 34 decles
;; ------------------------------------------------------------------------ ;;
_PA1:
    DECLE   _PA1.end - _PA1 - 1
    DECLE   $00F1, $0000
_PA1.end:  ; 2 decles
;; ------------------------------------------------------------------------ ;;
_PA2:
    DECLE   _PA2.end - _PA2 - 1
    DECLE   $00F4, $0000
_PA2.end:  ; 2 decles
;; ------------------------------------------------------------------------ ;;
_PA3:
    DECLE   _PA3.end - _PA3 - 1
    DECLE   $00F7, $0000
_PA3.end:  ; 2 decles
;; ------------------------------------------------------------------------ ;;
_PA4:
    DECLE   _PA4.end - _PA4 - 1
    DECLE   $00FF, $0000
_PA4.end:  ; 2 decles
;; ------------------------------------------------------------------------ ;;
_PA5:
    DECLE   _PA5.end - _PA5 - 1
    DECLE   $031D, $003F, $0000
_PA5.end:  ; 3 decles
;; ------------------------------------------------------------------------ ;;
_PP:
    DECLE   _PP.end - _PP - 1
    DECLE   $00FD, $0106, $0052, $0000, $022A, $03A5, $0277, $035F
    DECLE   $0184, $0000, $0055, $0391, $00EB, $00CF, $0000
_PP.end:  ; 15 decles
;; ------------------------------------------------------------------------ ;;
_RR1:
    DECLE   _RR1.end - _RR1 - 1
    DECLE   $0118, $01CD, $016C, $029E, $0171, $038E, $01E0, $0190
    DECLE   $0245, $0299, $01AA, $02E2, $01C7, $02DE, $0125, $00B5
    DECLE   $02C5, $028F, $024E, $035E, $01CB, $02EC, $0005, $0000
_RR1.end:  ; 24 decles
;; ------------------------------------------------------------------------ ;;
_RR2:
    DECLE   _RR2.end - _RR2 - 1
    DECLE   $0218, $03CC, $016C, $030C, $02C8, $0393, $02CD, $025E
    DECLE   $008A, $019D, $01AC, $02CB, $00BE, $0046, $017E, $01C2
    DECLE   $0174, $00A1, $01E5, $00E0, $010E, $0007, $0313, $0017
    DECLE   $0000
_RR2.end:  ; 25 decles
;; ------------------------------------------------------------------------ ;;
_SH:
    DECLE   _SH.end - _SH - 1
    DECLE   $0218, $0109, $0000, $007A, $0187, $02E0, $03F6, $0311
    DECLE   $0002, $0126, $0242, $0161, $03E9, $0219, $016C, $0300
    DECLE   $0013, $0045, $0124, $0005, $024C, $005C, $0182, $03C2
    DECLE   $0001
_SH.end:  ; 25 decles
;; ------------------------------------------------------------------------ ;;
_SS:
    DECLE   _SS.end - _SS - 1
    DECLE   $0218, $01CA, $0001, $0128, $001C, $0149, $01C6, $0000
_SS.end:  ; 8 decles
;; ------------------------------------------------------------------------ ;;
_TH:
    DECLE   _TH.end - _TH - 1
    DECLE   $0019, $0349, $0000, $00C6, $0212, $01D8, $01CA, $0000
_TH.end:  ; 8 decles
;; ------------------------------------------------------------------------ ;;
_TT1:
    DECLE   _TT1.end - _TT1 - 1
    DECLE   $00F6, $0046, $0142, $0100, $0042, $0088, $027E, $02EF
    DECLE   $01A4, $0200, $0049, $0290, $00FC, $00E8, $0000
_TT1.end:  ; 15 decles
;; ------------------------------------------------------------------------ ;;
_TT2:
    DECLE   _TT2.end - _TT2 - 1
    DECLE   $00F5, $00C6, $01D2, $0100, $0335, $00E9, $0042, $027A
    DECLE   $02A4, $0000, $0062, $01D1, $014C, $03EA, $02EC, $01E0
    DECLE   $0007, $03A7, $0000
_TT2.end:  ; 19 decles
;; ------------------------------------------------------------------------ ;;
_UH:
    DECLE   _UH.end - _UH - 1
    DECLE   $0018, $034E, $016E, $01FF, $0349, $00D2, $003C, $030C
    DECLE   $008B, $0005, $0000
_UH.end:  ; 11 decles
;; ------------------------------------------------------------------------ ;;
_UW1:
    DECLE   _UW1.end - _UW1 - 1
    DECLE   $0318, $014C, $016F, $029E, $03BD, $03BD, $0271, $0212
    DECLE   $0325, $0291, $016A, $027B, $014A, $03B4, $0133, $0001
_UW1.end:  ; 16 decles
;; ------------------------------------------------------------------------ ;;
_UW2:
    DECLE   _UW2.end - _UW2 - 1
    DECLE   $0018, $034E, $016E, $02F6, $0107, $02C2, $006D, $0090
    DECLE   $03AC, $01A4, $01DC, $03AB, $0128, $0076, $03E6, $0119
    DECLE   $014F, $03A6, $03A5, $0020, $0090, $0001, $02EE, $00BB
    DECLE   $0000
_UW2.end:  ; 25 decles
;; ------------------------------------------------------------------------ ;;
_VV:
    DECLE   _VV.end - _VV - 1
    DECLE   $0218, $030D, $016C, $010B, $010B, $0095, $034F, $03E4
    DECLE   $0108, $01B5, $01BE, $028B, $0160, $00AA, $03E4, $0106
    DECLE   $00EB, $02DE, $014C, $016E, $00F6, $0107, $00D2, $00CD
    DECLE   $0296, $00E4, $0006, $0000
_VV.end:  ; 28 decles
;; ------------------------------------------------------------------------ ;;
_WH:
    DECLE   _WH.end - _WH - 1
    DECLE   $0218, $00C9, $0000, $0084, $038E, $0147, $03A4, $0195
    DECLE   $0000, $012E, $0118, $0150, $02D1, $0232, $01B7, $03F1
    DECLE   $0237, $01C8, $03B1, $0227, $01AE, $0254, $0329, $032D
    DECLE   $01BF, $0169, $019A, $0307, $0181, $028D, $0000
_WH.end:  ; 31 decles
;; ------------------------------------------------------------------------ ;;
_WW:
    DECLE   _WW.end - _WW - 1
    DECLE   $0118, $034D, $016C, $00FA, $02C7, $0072, $03CC, $0109
    DECLE   $000B, $01AD, $019E, $016B, $0130, $0278, $01F8, $0314
    DECLE   $017E, $029E, $014D, $016D, $0205, $0147, $02E2, $001A
    DECLE   $010A, $026E, $0004, $0000
_WW.end:  ; 28 decles
;; ------------------------------------------------------------------------ ;;
_XR2:
    DECLE   _XR2.end - _XR2 - 1
    DECLE   $0318, $034C, $016E, $02A6, $03BB, $002F, $0290, $008E
    DECLE   $004B, $0392, $01DA, $024B, $013A, $01DA, $012F, $00B5
    DECLE   $02E5, $0297, $02DC, $0372, $014B, $016D, $0377, $00E7
    DECLE   $0376, $038A, $01CE, $026B, $02FA, $01AA, $011E, $0071
    DECLE   $00D5, $0297, $02BC, $02EA, $01C7, $02D7, $0135, $0155
    DECLE   $01DD, $0007, $0000
_XR2.end:  ; 43 decles
;; ------------------------------------------------------------------------ ;;
_YR:
    DECLE   _YR.end - _YR - 1
    DECLE   $0318, $03CC, $016E, $0197, $00FD, $0130, $0270, $0094
    DECLE   $0328, $0291, $0168, $007E, $01CC, $02F5, $0125, $02B5
    DECLE   $00F4, $0298, $01DA, $03F6, $0153, $0126, $03B9, $00AB
    DECLE   $0293, $03DB, $0175, $01B9, $0001
_YR.end:  ; 29 decles
;; ------------------------------------------------------------------------ ;;
_YY1:
    DECLE   _YY1.end - _YY1 - 1
    DECLE   $0318, $01CC, $016E, $0015, $00CB, $0263, $0320, $0078
    DECLE   $01CE, $0094, $001F, $0040, $0320, $03BF, $0230, $00A7
    DECLE   $000F, $01FE, $03FC, $01E2, $00D0, $0089, $000F, $0248
    DECLE   $032B, $03FD, $01CF, $0001, $0000
_YY1.end:  ; 29 decles
;; ------------------------------------------------------------------------ ;;
_YY2:
    DECLE   _YY2.end - _YY2 - 1
    DECLE   $0318, $01CC, $016E, $0015, $00CB, $0263, $0320, $0078
    DECLE   $01CE, $0094, $001F, $0040, $0320, $03BF, $0230, $00A7
    DECLE   $000F, $01FE, $03FC, $01E2, $00D0, $0089, $000F, $0248
    DECLE   $032B, $03FD, $01CF, $0199, $01EE, $008B, $0161, $0232
    DECLE   $0004, $0318, $01A7, $0198, $0124, $03E0, $0001, $0001
    DECLE   $030F, $0027, $0000
_YY2.end:  ; 43 decles
;; ------------------------------------------------------------------------ ;;
_ZH:
    DECLE   _ZH.end - _ZH - 1
    DECLE   $0310, $014D, $016E, $00C3, $03B9, $01BF, $0241, $0012
    DECLE   $0163, $00E1, $0000, $0080, $0084, $023F, $003F, $0000
_ZH.end:  ; 16 decles
;; ------------------------------------------------------------------------ ;;
_ZZ:
    DECLE   _ZZ.end - _ZZ - 1
    DECLE   $0218, $010D, $016F, $0225, $0351, $00B5, $02A0, $02EE
    DECLE   $00E9, $014D, $002C, $0360, $0008, $00EC, $004C, $0342
    DECLE   $03D4, $0156, $0052, $0131, $0008, $03B0, $01BE, $0172
    DECLE   $0000
_ZZ.end:  ; 25 decles

;;==========================================================================;;
;;									  ;;
;;  Copyright information:						  ;;
;;									  ;;
;;  The above allophone data was extracted from the SP0256-AL2 ROM image.   ;;
;;  The SP0256-AL2 allophones are NOT in the public domain, nor are they    ;;
;;  placed under the GNU General Public License.  This program is	   ;;
;;  distributed in the hope that it will be useful, but WITHOUT ANY	 ;;
;;  WARRANTY; without even the implied warranty of MERCHANTABILITY or       ;;
;;  FITNESS FOR A PARTICULAR PURPOSE.				       ;;
;;									  ;;
;;  Microchip, Inc. retains the copyright to the data and algorithms	;;
;;  contained in the SP0256-AL2.  This speech data is distributed with      ;;
;;  explicit permission from Microchip, Inc.  All such redistributions      ;;
;;  must retain this notice of copyright.				   ;;
;;									  ;;
;;  No copyright claims are made on this data by the author(s) of SDK1600.  ;;
;;  Please see http://spatula-city.org/~im14u2c/sp0256-al2/ for details.    ;;
;;									  ;;
;;==========================================================================;;

;* ======================================================================== *;
;*  These routines are placed into the public domain by their author.  All  *;
;*  copyright rights are hereby relinquished on the routines and data in    *;
;*  this file.  -- Joseph Zbiciak, 2008				     *;
;* ======================================================================== *;

;; ======================================================================== ;;
;;  INTELLIVOICE DRIVER ROUTINES					    ;;
;;  Written in 2002 by Joe Zbiciak <intvnut AT gmail.com>		   ;;
;;  http://spatula-city.org/~im14u2c/intv/				  ;;
;; ======================================================================== ;;

;; ======================================================================== ;;
;;  GLOBAL VARIABLES USED BY THESE ROUTINES				 ;;
;;									  ;;
;;  Note that some of these routines may use one or more global variables.  ;;
;;  If you use these routines, you will need to allocate the appropriate    ;;
;;  space in either 16-bit or 8-bit memory as appropriate.  Each global     ;;
;;  variable is listed with the routines which use it and the required      ;;
;;  memory width.							   ;;
;;									  ;;
;;  Example declarations for these routines are shown below, commented out. ;;
;;  You should uncomment these and add them to your program to make use of  ;;
;;  the routine that needs them.  Make sure to assign these variables to    ;;
;;  locations that aren't used for anything else.			   ;;
;; ======================================================================== ;;

			; Used by       Req'd Width     Description
			;-----------------------------------------------------
;IV.QH      EQU $110    ; IV_xxx	8-bit	   Voice queue head
;IV.QT      EQU $111    ; IV_xxx	8-bit	   Voice queue tail
;IV.Q       EQU $112    ; IV_xxx	8-bit	   Voice queue  (8 bytes)
;IV.FLEN    EQU $11A    ; IV_xxx	8-bit	   Length of FIFO data
;IV.FPTR    EQU $320    ; IV_xxx	16-bit	  Current FIFO ptr.
;IV.PPTR    EQU $321    ; IV_xxx	16-bit	  Current Phrase ptr.

;; ======================================================================== ;;
;;  MEMORY USAGE							    ;;
;;									  ;;
;;  These routines implement a queue of "pending phrases" that will be      ;;
;;  played by the Intellivoice.  The user calls IV_PLAY to enqueue a	;;
;;  phrase number.  Phrase numbers indicate either a RESROM sample or       ;;
;;  a compiled in phrase to be spoken.				      ;;
;;									  ;;
;;  The user must compose an "IV_PHRASE_TBL", which is composed of	  ;;
;;  pointers to phrases to be spoken.  Phrases are strings of pointers      ;;
;;  and RESROM triggers, terminated by a NUL.			       ;;
;;									  ;;
;;  Phrase numbers 1 through 42 are RESROM samples.  Phrase numbers	 ;;
;;  43 through 255 index into the IV_PHRASE_TBL.			    ;;
;;									  ;;
;;  SPECIAL NOTES							   ;;
;;									  ;;
;;  Bit 7 of IV.QH and IV.QT is used to denote whether the Intellivoice     ;;
;;  is present.  If Intellivoice is present, this bit is clear.	     ;;
;;									  ;;
;;  Bit 6 of IV.QT is used to denote that we still need to do an ALD $00    ;;
;;  for FIFO'd voice data.						  ;;
;; ======================================================================== ;;
	    

;; ======================================================================== ;;
;;  NAME								    ;;
;;      IV_INIT     Initialize the Intellivoice			     ;;
;;									  ;;
;;  AUTHOR								  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>			       ;;
;;									  ;;
;;  REVISION HISTORY							;;
;;      15-Sep-2002 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;									  ;;
;;  INPUTS for IV_INIT						      ;;
;;      R5      Return address					      ;;
;;									  ;;
;;  OUTPUTS								 ;;
;;      R0      0 if Intellivoice found, -1 if not.			 ;;
;;									  ;;
;;  DESCRIPTION							     ;;
;;      Resets Intellivoice, determines if it is actually there, and	;;
;;      then initializes the IV structure.				  ;;
;; ------------------------------------------------------------------------ ;;
;;		   Copyright (c) 2002, Joseph Zbiciak		     ;;
;; ======================================================================== ;;

IV_INIT     PROC
	    MVII    #$0400, R0	  ;
	    MVO     R0,     $0081       ; Reset the Intellivoice

	    MVI     $0081,  R0	  ; \
	    RLC     R0,     2	   ;  |-- See if we detect Intellivoice
	    BOV     @@no_ivoice	 ; /    once we've reset it.

	    CLRR    R0		  ; 
	    MVO     R0,     IV.FPTR     ; No data for FIFO
	    MVO     R0,     IV.PPTR     ; No phrase being spoken
	    MVO     R0,     IV.QH       ; Clear our queue
	    MVO     R0,     IV.QT       ; Clear our queue
	    JR      R5		  ; Done!

@@no_ivoice:
	    CLRR    R0
	    MVO     R0,     IV.FPTR     ; No data for FIFO
	    MVO     R0,     IV.PPTR     ; No phrase being spoken
	    DECR    R0
	    MVO     R0,     IV.QH       ; Set queue to -1 ("No Intellivoice")
	    MVO     R0,     IV.QT       ; Set queue to -1 ("No Intellivoice")
;	    JR      R5		 ; Done!
	    B       _wait	       ; Special for IntyBASIC!
	    ENDP

;; ======================================================================== ;;
;;  NAME								    ;;
;;      IV_ISR      Interrupt service routine to feed Intellivoice	  ;;
;;									  ;;
;;  AUTHOR								  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>			       ;;
;;									  ;;
;;  REVISION HISTORY							;;
;;      15-Sep-2002 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;									  ;;
;;  INPUTS for IV_ISR						       ;;
;;      R5      Return address					      ;;
;;									  ;;
;;  OUTPUTS								 ;;
;;      R0, R1, R4 trashed.						 ;;
;;									  ;;
;;  NOTES								   ;;
;;      Call this from your main interrupt service routine.		 ;;
;; ------------------------------------------------------------------------ ;;
;;		   Copyright (c) 2002, Joseph Zbiciak		     ;;
;; ======================================================================== ;;
IV_ISR      PROC
	    ;; ------------------------------------------------------------ ;;
	    ;;  Check for Intellivoice.  Leave if none present.	     ;;
	    ;; ------------------------------------------------------------ ;;
	    MVI     IV.QT,  R1	  ; Get queue tail
	    SWAP    R1,     2
	    BPL     @@ok		; Bit 7 set? If yes: No Intellivoice
@@ald_busy:
@@leave     JR      R5		  ; Exit if no Intellivoice.

     
	    ;; ------------------------------------------------------------ ;;
	    ;;  Check to see if we pump samples into the FIFO.
	    ;; ------------------------------------------------------------ ;;
@@ok:       MVI     IV.FPTR, R4	 ; Get FIFO data pointer
	    TSTR    R4		  ; is it zero?
	    BEQ     @@no_fifodata       ; Yes:  No data for FIFO.
@@fifo_fill:
	    MVI     $0081,  R0	  ; Read speech FIFO ready bit
	    SLLC    R0,     1	   ; 
	    BC      @@fifo_busy     

	    MVI@    R4,     R0	  ; Get next word
	    MVO     R0,     $0081       ; write it to the FIFO

	    MVI     IV.FLEN, R0	 ;\
	    DECR    R0		  ; |-- Decrement our FIFO'd data length
	    MVO     R0,     IV.FLEN     ;/
	    BEQ     @@last_fifo	 ; If zero, we're done w/ FIFO
	    MVO     R4,     IV.FPTR     ; Otherwise, save new pointer
	    B       @@fifo_fill	 ; ...and keep trying to load FIFO

@@last_fifo MVO     R0,     IV.FPTR     ; done with FIFO loading.
					; fall into ALD processing.


	    ;; ------------------------------------------------------------ ;;
	    ;;  Try to do an Address Load.  We do this in two settings:     ;;
	    ;;   -- We have no FIFO data to load.			   ;;
	    ;;   -- We've loaded as much FIFO data as we can, but we	;;
	    ;;      might have an address load command to send for it.      ;;
	    ;; ------------------------------------------------------------ ;;
@@fifo_busy:
@@no_fifodata:
	    MVI     $0080,  R0	  ; Read LRQ bit from ALD register
	    SLLC    R0,     1
	    BNC     @@ald_busy	  ; LRQ is low, meaning we can't ALD.
					; So, leave.

	    ;; ------------------------------------------------------------ ;;
	    ;;  We can do an address load (ALD) on the SP0256.  Give FIFO   ;;
	    ;;  driven ALDs priority, since we already started the FIFO     ;;
	    ;;  load.  The "need ALD" bit is stored in bit 6 of IV.QT.      ;;
	    ;; ------------------------------------------------------------ ;;
	    ANDI    #$40,   R1	  ; Is "Need FIFO ALD" bit set?
	    BEQ     @@no_fifo_ald
	    XOR     IV.QT,  R1	  ;\__ Clear the "Need FIFO ALD" bit.
	    MVO     R1,     IV.QT       ;/
	    CLRR    R1
	    MVO     R1,     $80	 ; Load a 0 into ALD (trigger FIFO rd.)
	    JR      R5		  ; done!

	    ;; ------------------------------------------------------------ ;;
	    ;;  We don't need to ALD on behalf of the FIFO.  So, we grab    ;;
	    ;;  the next thing off our phrase list.			 ;;
	    ;; ------------------------------------------------------------ ;;
@@no_fifo_ald:
	    MVI     IV.PPTR, R4	 ; Get phrase pointer.
	    TSTR    R4		  ; Is it zero?
	    BEQ     @@next_phrase       ; Yes:  Get next phrase from queue.

	    MVI@    R4,     R0
	    TSTR    R0		  ; Is it end of phrase?
	    BNEQ    @@process_phrase    ; !=0:  Go do it.

	    MVO     R0,     IV.PPTR     ; 
@@next_phrase:
	    MVI     IV.QT,  R1	  ; reload queue tail (was trashed above)
	    MOVR    R1,     R0	  ; copy QT to R0 so we can increment it
	    ANDI    #$7,    R1	  ; Mask away flags in queue head
	    CMP     IV.QH,  R1	  ; Is it same as queue tail?
	    BEQ     @@leave	     ; Yes:  No more speech for now.

	    INCR    R0
	    ANDI    #$F7,   R0	  ; mask away the possible 'carry'
	    MVO     R0,     IV.QT       ; save updated queue tail

	    ADDI    #IV.Q,  R1	  ; Index into queue
	    MVI@    R1,     R4	  ; get next value from queue
	    CMPI    #43,    R4	  ; Is it a RESROM or Phrase?
	    BNC     @@play_resrom_r4
@@new_phrase:
;	    ADDI    #IV_PHRASE_TBL - 43, R4 ; Index into phrase table
;	    MVI@    R4,     R4	  ; Read from phrase table
	    MVO     R4,     IV.PPTR
	    JR      R5		  ; we'll get to this phrase next time.

@@play_resrom_r4:
	    MVO     R4,     $0080       ; Just ALD it
	    JR      R5		  ; and leave.

	    ;; ------------------------------------------------------------ ;;
	    ;;  We're in the middle of a phrase, so continue interpreting.  ;;
	    ;; ------------------------------------------------------------ ;;
@@process_phrase:
	    
	    MVO     R4,     IV.PPTR     ; save new phrase pointer
	    CMPI    #43,    R0	  ; Is it a RESROM cue?
	    BC      @@play_fifo	 ; Just ALD it and leave.
@@play_resrom_r0
	    MVO     R0,     $0080       ; Just ALD it
	    JR      R5		  ; and leave.
@@play_fifo:
	    MVI     IV.FPTR,R1	  ; Make sure not to stomp existing FIFO
	    TSTR    R1		  ; data.
	    BEQ     @@new_fifo_ok
	    DECR    R4		  ; Oops, FIFO data still playing,
	    MVO     R4,     IV.PPTR     ; so rewind.
	    JR      R5		  ; and leave.

@@new_fifo_ok:
	    MOVR    R0,     R4	  ;
	    MVI@    R4,     R0	  ; Get chunk length
	    MVO     R0,     IV.FLEN     ; Init FIFO chunk length
	    MVO     R4,     IV.FPTR     ; Init FIFO pointer
	    MVI     IV.QT,  R0	  ;\
	    XORI    #$40,   R0	  ; |- Set "Need ALD" bit in QT
	    MVO     R0,     IV.QT       ;/

  IF 1      ; debug code		;\
	    ANDI    #$40,   R0	  ; |   Debug code:  We should only
	    BNEQ    @@qtok	      ; |-- be here if "Need FIFO ALD" 
	    HLT     ;BUG!!	      ; |   was already clear.	 
@@qtok				  ;/    
  ENDI
	    JR      R5		  ; leave.

	    ENDP


;; ======================================================================== ;;
;;  NAME								    ;;
;;      IV_PLAY     Play a voice sample sequence.			   ;;
;;									  ;;
;;  AUTHOR								  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>			       ;;
;;									  ;;
;;  REVISION HISTORY							;;
;;      15-Sep-2002 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;									  ;;
;;  INPUTS for IV_PLAY						      ;;
;;      R5      Invocation record, followed by return address.	      ;;
;;		  1 DECLE    Phrase number to play.		       ;;
;;									  ;;
;;  INPUTS for IV_PLAY.1						    ;;
;;      R0      Address of phrase to play.				  ;;
;;      R5      Return address					      ;;
;;									  ;;
;;  OUTPUTS								 ;;
;;      R0, R1  trashed						     ;;
;;      Z==0    if item not successfully queued.			    ;;
;;      Z==1    if successfully queued.				     ;;
;;									  ;;
;;  NOTES								   ;;
;;      This code will drop phrases if the queue is full.		   ;;
;;      Phrase numbers 1..42 are RESROM samples.  43..255 will index	;;
;;      into the user-supplied IV_PHRASE_TBL.  43 will refer to the	 ;;
;;      first entry, 44 to the second, and so on.  Phrase 0 is undefined.   ;;
;;									  ;;
;; ------------------------------------------------------------------------ ;;
;;		   Copyright (c) 2002, Joseph Zbiciak		     ;;
;; ======================================================================== ;;
IV_PLAY     PROC
	    MVI@    R5,     R0

@@1:	; alternate entry point
	    MVI     IV.QT,  R1	  ; Get queue tail
	    SWAP    R1,     2	   ;\___ Leave if "no Intellivoice"
	    BMI     @@leave	     ;/    bit it set.
@@ok:       
	    DECR    R1		  ;\
	    ANDI    #$7,    R1	  ; |-- See if we still have room
	    CMP     IV.QH,  R1	  ;/
	    BEQ     @@leave	     ; Leave if we're full

@@2:	MVI     IV.QH,  R1	  ; Get our queue head pointer
	    PSHR    R1		  ;\
	    INCR    R1		  ; |
	    ANDI    #$F7,   R1	  ; |-- Increment it, removing
	    MVO     R1,     IV.QH       ; |   carry but preserving flags.
	    PULR    R1		  ;/

	    ADDI    #IV.Q,  R1	  ;\__ Store phrase to queue
	    MVO@    R0,     R1	  ;/

@@leave:    JR      R5		  ; Leave.
	    ENDP

;; ======================================================================== ;;
;;  NAME								    ;;
;;      IV_PLAYW    Play a voice sample sequence.  Wait for queue room.     ;;
;;									  ;;
;;  AUTHOR								  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>			       ;;
;;									  ;;
;;  REVISION HISTORY							;;
;;      15-Sep-2002 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;									  ;;
;;  INPUTS for IV_PLAY						      ;;
;;      R5      Invocation record, followed by return address.	      ;;
;;		  1 DECLE    Phrase number to play.		       ;;
;;									  ;;
;;  INPUTS for IV_PLAY.1						    ;;
;;      R0      Address of phrase to play.				  ;;
;;      R5      Return address					      ;;
;;									  ;;
;;  OUTPUTS								 ;;
;;      R0, R1  trashed						     ;;
;;									  ;;
;;  NOTES								   ;;
;;      This code will wait for a queue slot to open if queue is full.      ;;
;;      Phrase numbers 1..42 are RESROM samples.  43..255 will index	;;
;;      into the user-supplied IV_PHRASE_TBL.  43 will refer to the	 ;;
;;      first entry, 44 to the second, and so on.  Phrase 0 is undefined.   ;;
;;									  ;;
;; ------------------------------------------------------------------------ ;;
;;		   Copyright (c) 2002, Joseph Zbiciak		     ;;
;; ======================================================================== ;;
IV_PLAYW    PROC
	    MVI@    R5,     R0

@@1:	; alternate entry point
	    MVI     IV.QT,  R1	  ; Get queue tail
	    SWAP    R1,     2	   ;\___ Leave if "no Intellivoice"
	    BMI     IV_PLAY.leave       ;/    bit it set.
@@ok:       
	    DECR    R1		  ;\
	    ANDI    #$7,    R1	  ; |-- See if we still have room
	    CMP     IV.QH,  R1	  ;/
	    BEQ     @@1		 ; wait for room
	    B       IV_PLAY.2

	    ENDP

;; ======================================================================== ;;
;;  NAME								    ;;
;;      IV_HUSH     Flush the speech queue, and hush the Intellivoice.      ;;
;;									  ;;
;;  AUTHOR								  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>			       ;;
;;									  ;;
;;  REVISION HISTORY							;;
;;      02-Feb-2018 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;									  ;;
;;  INPUTS for IV_HUSH						      ;;
;;      None.							       ;;
;;									  ;;
;;  OUTPUTS								 ;;
;;      R0 trashed.							 ;;
;;									  ;;
;;  NOTES								   ;;
;;      Returns via IV_WAIT.						;;
;;									  ;;
;; ======================================================================== ;;
IV_HUSH:    PROC
	    MVI     IV.QH,  R0
	    SWAP    R0,     2
	    BMI     IV_WAIT.leave

	    DIS
	    ;; We can't stop a phrase segment that's being FIFOed down.
	    ;; We need to remember if we've committed to pushing ALD.
	    ;; We _can_ stop new phrase segments from going down, and _can_
	    ;; stop new phrases from being started.

	    ;; Set head pointer to indicate we've inserted one item.
	    MVI     IV.QH,  R0  ; Re-read, as an interrupt may have occurred
	    ANDI    #$F0,   R0
	    INCR    R0
	    MVO     R0,     IV.QH

	    ;; Reset tail pointer, keeping "need ALD" bit and other flags.
	    MVI     IV.QT,  R0
	    ANDI    #$F0,   R0
	    MVO     R0,     IV.QT

	    ;; Reset the phrase pointer, to stop a long phrase.
	    CLRR    R0
	    MVO     R0,     IV.PPTR

	    ;; Queue a PA1 in the queue.  Since we're can't guarantee the user
	    ;; has included resrom.asm, let's just use the raw number (5).
	    MVII    #5,     R0
	    MVO     R0,     IV.Q

	    ;; Re-enable interrupts and wait for Intellivoice to shut up.
	    ;;
	    ;; We can't just jump to IV_WAIT.q_loop, as we need to reload
	    ;; IV.QH into R0, and I'm really committed to only using R0.
;	   JE      IV_WAIT
	    EIS
	    ; fallthrough into IV_WAIT
	    ENDP

;; ======================================================================== ;;
;;  NAME								    ;;
;;      IV_WAIT     Wait for voice queue to empty.			  ;;
;;									  ;;
;;  AUTHOR								  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>			       ;;
;;									  ;;
;;  REVISION HISTORY							;;
;;      15-Sep-2002 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;									  ;;
;;  INPUTS for IV_WAIT						      ;;
;;      R5      Return address					      ;;
;;									  ;;
;;  OUTPUTS								 ;;
;;      R0      trashed.						    ;;
;;									  ;;
;;  NOTES								   ;;
;;      This waits until the Intellivoice is nearly completely quiescent.   ;;
;;      Some voice data may still be spoken from the last triggered	 ;;
;;      phrase.  To truly wait for *that* to be spoken, speak a 'pause'     ;;
;;      (eg. RESROM.pa1) and then call IV_WAIT.			     ;;
;; ------------------------------------------------------------------------ ;;
;;		   Copyright (c) 2002, Joseph Zbiciak		     ;;
;; ======================================================================== ;;
IV_WAIT     PROC
	    MVI     IV.QH,  R0
	    CMPI    #$80, R0	    ; test bit 7, leave if set.
	    BC      @@leave

	    ; Wait for queue to drain.
@@q_loop:   CMP     IV.QT,  R0
	    BNEQ    @@q_loop

	    ; Wait for FIFO and LRQ to say ready.
@@s_loop:   MVI     $81,    R0	  ; Read FIFO status.  0 == ready.
	    COMR    R0
	    AND     $80,    R0	  ; Merge w/ ALD status.  1 == ready
	    TSTR    R0
	    BPL     @@s_loop	    ; if bit 15 == 0, not ready.
	    
@@leave:    JR      R5
	    ENDP

;; ======================================================================== ;;
;;  End of File:  ivoice.asm						;;
;; ======================================================================== ;;

;* ======================================================================== *;
;*  These routines are placed into the public domain by their author.  All  *;
;*  copyright rights are hereby relinquished on the routines and data in    *;
;*  this file.  -- Joseph Zbiciak, 2008				     *;
;* ======================================================================== *;

;; ======================================================================== ;;
;;  NAME								    ;;
;;      IV_SAYNUM16 Say a 16-bit unsigned number using RESROM digits	;;
;;									  ;;
;;  AUTHOR								  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>			       ;;
;;									  ;;
;;  REVISION HISTORY							;;
;;      16-Sep-2002 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;									  ;;
;;  INPUTS for IV_SAYNUM16						  ;;
;;      R0      Number to "speak"					   ;;
;;      R5      Return address					      ;;
;;									  ;;
;;  OUTPUTS								 ;;
;;									  ;;
;;  DESCRIPTION							     ;;
;;      "Says" a 16-bit number using IV_PLAYW to queue up the phrase.       ;;
;;      Because the number may be built from several segments, it could     ;;
;;      easily eat up the queue.  I believe the longest number will take    ;;
;;      7 queue entries -- that is, fill the queue.  Thus, this code	;;
;;      could block, waiting for slots in the queue.			;;
;; ======================================================================== ;;

IV_SAYNUM16 PROC
	    PSHR    R5

	    TSTR    R0
	    BEQ     @@zero	  ; Special case:  Just say "zero"

	    ;; ------------------------------------------------------------ ;;
	    ;;  First, try to pull off 'thousands'.  We call ourselves      ;;
	    ;;  recursively to play the the number of thousands.	    ;;
	    ;; ------------------------------------------------------------ ;;
	    CLRR    R1
@@thloop:   INCR    R1
	    SUBI    #1000,  R0
	    BC      @@thloop

	    ADDI    #1000,  R0
	    PSHR    R0
	    DECR    R1
	    BEQ     @@no_thousand

	    CALL    IV_SAYNUM16.recurse

	    CALL    IV_PLAYW
	    DECLE   36  ; THOUSAND
	    
@@no_thousand
	    PULR    R1

	    ;; ------------------------------------------------------------ ;;
	    ;;  Now try to play hundreds.				   ;;
	    ;; ------------------------------------------------------------ ;;
	    MVII    #7-1, R0    ; ZERO
	    CMPI    #100,   R1
	    BNC     @@no_hundred

@@hloop:    INCR    R0
	    SUBI    #100,   R1
	    BC      @@hloop
	    ADDI    #100,   R1

	    PSHR    R1

	    CALL    IV_PLAYW.1

	    CALL    IV_PLAYW
	    DECLE   35  ; HUNDRED

	    PULR    R1
	    B       @@notrecurse    ; skip "PSHR R5"
@@recurse:  PSHR    R5	      ; recursive entry point for 'thousand'

@@no_hundred:
@@notrecurse:
	    MOVR    R1,     R0
	    BEQ     @@leave

	    SUBI    #20,    R1
	    BNC     @@teens

	    MVII    #27-1, R0   ; TWENTY
@@tyloop    INCR    R0
	    SUBI    #10,    R1
	    BC      @@tyloop
	    ADDI    #10,    R1

	    PSHR    R1
	    CALL    IV_PLAYW.1

	    PULR    R0
	    TSTR    R0
	    BEQ     @@leave

@@teens:
@@zero:     ADDI    #7, R0  ; ZERO

	    CALL    IV_PLAYW.1

@@leave     PULR    PC
	    ENDP

;; ======================================================================== ;;
;;  End of File:  saynum16.asm					      ;;
;; ======================================================================== ;;

IV_INIT_and_wait:     EQU IV_INIT

    ELSE

IV_INIT_and_wait:     EQU _wait	; No voice init; just WAIT.

    ENDI

	IF DEFINED intybasic_flash

;; ======================================================================== ;;
;;  JLP "Save Game" support						 ;;
;; ======================================================================== ;;
JF.first    EQU     $8023
JF.last     EQU     $8024
JF.addr     EQU     $8025
JF.row      EQU     $8026
		   
JF.wrcmd    EQU     $802D
JF.rdcmd    EQU     $802E
JF.ercmd    EQU     $802F
JF.wrkey    EQU     $C0DE
JF.rdkey    EQU     $DEC0
JF.erkey    EQU     $BEEF

JF.write:   DECLE   JF.wrcmd,   JF.wrkey    ; Copy JLP RAM to flash row  
JF.read:    DECLE   JF.rdcmd,   JF.rdkey    ; Copy flash row to JLP RAM  
JF.erase:   DECLE   JF.ercmd,   JF.erkey    ; Erase flash sector 

;; ======================================================================== ;;
;;  JF.INIT	 Copy JLP save-game support routine to System RAM	;;
;; ======================================================================== ;;
JF.INIT     PROC
	    PSHR    R5	    
	    MVII    #@@__code,  R5
	    MVII    #JF.SYSRAM, R4
	    REPEAT  5       
	    MVI@    R5,	 R0      ; \_ Copy code fragment to System RAM
	    MVO@    R0,	 R4      ; /
	    ENDR
	    PULR    PC

	    ;; === start of code that will run from RAM
@@__code:   MVO@    R0,	 R1      ; JF.SYSRAM + 0: initiate command
	    ADD@    R1,	 PC      ; JF.SYSRAM + 1: Wait for JLP to return
	    JR      R5		  ; JF.SYSRAM + 2:
	    MVO@    R2,	 R2      ; JF.SYSRAM + 3: \__ simple ISR
	    JR      R5		  ; JF.SYSRAM + 4: /
	    ;; === end of code that will run from RAM
	    ENDP

;; ======================================================================== ;;
;;  JF.CMD	  Issue a JLP Flash command			       ;;
;;									  ;;
;;  INPUT								   ;;
;;      R0  Slot number to operate on				       ;;
;;      R1  Address to copy to/from in JLP RAM			      ;;
;;      @R5 Command to invoke:					      ;;
;;									  ;;
;;	      JF.write -- Copy JLP RAM to Flash			   ;;
;;	      JF.read  -- Copy Flash to JLP RAM			   ;;
;;	      JF.erase -- Erase flash sector			      ;;
;;									  ;;
;;  OUTPUT								  ;;
;;      R0 - R4 not modified.  (Saved and restored across call)	     ;;
;;      JLP command executed						;;
;;									  ;;
;;  NOTES								   ;;
;;      This code requires two short routines in the console's System RAM.  ;;
;;      It also requires that the system stack reside in System RAM.	;;
;;      Because an interrupt may occur during the code's execution, there   ;;
;;      must be sufficient stack space to service the interrupt (8 words).  ;;
;;									  ;;
;;      The code also relies on the fact that the EXEC ISR dispatch does    ;;
;;      not modify R2.  This allows us to initialize R2 for the ISR ahead   ;;
;;      of time, rather than in the ISR.				    ;;
;; ======================================================================== ;;
JF.CMD      PROC

	    MVO     R4,	 JF.SV.R4    ; \
	    MVII    #JF.SV.R0,  R4	  ;  |
	    MVO@    R0,	 R4	  ;  |- Save registers, but not on
	    MVO@    R1,	 R4	  ;  |  the stack.  (limit stack use)
	    MVO@    R2,	 R4	  ; /

	    MVI@    R5,	 R4	  ; Get command to invoke

	    MVO     R5,	 JF.SV.R5    ; save return address

	    DIS
	    MVO     R1,	 JF.addr     ; \_ Save SG arguments in JLP
	    MVO     R0,	 JF.row      ; /
					  
	    MVI@    R4,	 R1	  ; Get command address
	    MVI@    R4,	 R0	  ; Get unlock word
					  
	    MVII    #$100,      R4	  ; \
	    SDBD			    ;  |_ Save old ISR in save area
	    MVI@    R4,	 R2	  ;  |
	    MVO     R2,	 JF.SV.ISR   ; /
					  
	    MVII    #JF.SYSRAM + 3, R2      ; \
	    MVO     R2,	 $100	;  |_ Set up new ISR in RAM
	    SWAP    R2		      ;  |
	    MVO     R2,	 $101	; / 
					  
	    MVII    #$20,       R2	  ; Address of STIC handshake
	    JSRE    R5,  JF.SYSRAM	  ; Invoke the command
					  
	    MVI     JF.SV.ISR,  R2	  ; \
	    MVO     R2,	 $100	;  |_ Restore old ISR 
	    SWAP    R2		      ;  |
	    MVO     R2,	 $101	; /
					  
	    MVII    #JF.SV.R0,  R5	  ; \
	    MVI@    R5,	 R0	  ;  |
	    MVI@    R5,	 R1	  ;  |- Restore registers
	    MVI@    R5,	 R2	  ;  |
	    MVI@    R5,	 R4	  ; /
	    MVI@    R5,	 PC	  ; Return

	    ENDP


	ENDI

	IF DEFINED intybasic_fastmult

; Quarter Square Multiplication
; Assembly code by Joe Zbiciak, 2015
; Released to public domain.

QSQR8_TBL:  PROC
	    DECLE   $3F80, $3F01, $3E82, $3E04, $3D86, $3D09, $3C8C, $3C10
	    DECLE   $3B94, $3B19, $3A9E, $3A24, $39AA, $3931, $38B8, $3840
	    DECLE   $37C8, $3751, $36DA, $3664, $35EE, $3579, $3504, $3490
	    DECLE   $341C, $33A9, $3336, $32C4, $3252, $31E1, $3170, $3100
	    DECLE   $3090, $3021, $2FB2, $2F44, $2ED6, $2E69, $2DFC, $2D90
	    DECLE   $2D24, $2CB9, $2C4E, $2BE4, $2B7A, $2B11, $2AA8, $2A40
	    DECLE   $29D8, $2971, $290A, $28A4, $283E, $27D9, $2774, $2710
	    DECLE   $26AC, $2649, $25E6, $2584, $2522, $24C1, $2460, $2400
	    DECLE   $23A0, $2341, $22E2, $2284, $2226, $21C9, $216C, $2110
	    DECLE   $20B4, $2059, $1FFE, $1FA4, $1F4A, $1EF1, $1E98, $1E40
	    DECLE   $1DE8, $1D91, $1D3A, $1CE4, $1C8E, $1C39, $1BE4, $1B90
	    DECLE   $1B3C, $1AE9, $1A96, $1A44, $19F2, $19A1, $1950, $1900
	    DECLE   $18B0, $1861, $1812, $17C4, $1776, $1729, $16DC, $1690
	    DECLE   $1644, $15F9, $15AE, $1564, $151A, $14D1, $1488, $1440
	    DECLE   $13F8, $13B1, $136A, $1324, $12DE, $1299, $1254, $1210
	    DECLE   $11CC, $1189, $1146, $1104, $10C2, $1081, $1040, $1000
	    DECLE   $0FC0, $0F81, $0F42, $0F04, $0EC6, $0E89, $0E4C, $0E10
	    DECLE   $0DD4, $0D99, $0D5E, $0D24, $0CEA, $0CB1, $0C78, $0C40
	    DECLE   $0C08, $0BD1, $0B9A, $0B64, $0B2E, $0AF9, $0AC4, $0A90
	    DECLE   $0A5C, $0A29, $09F6, $09C4, $0992, $0961, $0930, $0900
	    DECLE   $08D0, $08A1, $0872, $0844, $0816, $07E9, $07BC, $0790
	    DECLE   $0764, $0739, $070E, $06E4, $06BA, $0691, $0668, $0640
	    DECLE   $0618, $05F1, $05CA, $05A4, $057E, $0559, $0534, $0510
	    DECLE   $04EC, $04C9, $04A6, $0484, $0462, $0441, $0420, $0400
	    DECLE   $03E0, $03C1, $03A2, $0384, $0366, $0349, $032C, $0310
	    DECLE   $02F4, $02D9, $02BE, $02A4, $028A, $0271, $0258, $0240
	    DECLE   $0228, $0211, $01FA, $01E4, $01CE, $01B9, $01A4, $0190
	    DECLE   $017C, $0169, $0156, $0144, $0132, $0121, $0110, $0100
	    DECLE   $00F0, $00E1, $00D2, $00C4, $00B6, $00A9, $009C, $0090
	    DECLE   $0084, $0079, $006E, $0064, $005A, $0051, $0048, $0040
	    DECLE   $0038, $0031, $002A, $0024, $001E, $0019, $0014, $0010
	    DECLE   $000C, $0009, $0006, $0004, $0002, $0001, $0000
@@mid:
	    DECLE   $0000, $0000, $0001, $0002, $0004, $0006, $0009, $000C
	    DECLE   $0010, $0014, $0019, $001E, $0024, $002A, $0031, $0038
	    DECLE   $0040, $0048, $0051, $005A, $0064, $006E, $0079, $0084
	    DECLE   $0090, $009C, $00A9, $00B6, $00C4, $00D2, $00E1, $00F0
	    DECLE   $0100, $0110, $0121, $0132, $0144, $0156, $0169, $017C
	    DECLE   $0190, $01A4, $01B9, $01CE, $01E4, $01FA, $0211, $0228
	    DECLE   $0240, $0258, $0271, $028A, $02A4, $02BE, $02D9, $02F4
	    DECLE   $0310, $032C, $0349, $0366, $0384, $03A2, $03C1, $03E0
	    DECLE   $0400, $0420, $0441, $0462, $0484, $04A6, $04C9, $04EC
	    DECLE   $0510, $0534, $0559, $057E, $05A4, $05CA, $05F1, $0618
	    DECLE   $0640, $0668, $0691, $06BA, $06E4, $070E, $0739, $0764
	    DECLE   $0790, $07BC, $07E9, $0816, $0844, $0872, $08A1, $08D0
	    DECLE   $0900, $0930, $0961, $0992, $09C4, $09F6, $0A29, $0A5C
	    DECLE   $0A90, $0AC4, $0AF9, $0B2E, $0B64, $0B9A, $0BD1, $0C08
	    DECLE   $0C40, $0C78, $0CB1, $0CEA, $0D24, $0D5E, $0D99, $0DD4
	    DECLE   $0E10, $0E4C, $0E89, $0EC6, $0F04, $0F42, $0F81, $0FC0
	    DECLE   $1000, $1040, $1081, $10C2, $1104, $1146, $1189, $11CC
	    DECLE   $1210, $1254, $1299, $12DE, $1324, $136A, $13B1, $13F8
	    DECLE   $1440, $1488, $14D1, $151A, $1564, $15AE, $15F9, $1644
	    DECLE   $1690, $16DC, $1729, $1776, $17C4, $1812, $1861, $18B0
	    DECLE   $1900, $1950, $19A1, $19F2, $1A44, $1A96, $1AE9, $1B3C
	    DECLE   $1B90, $1BE4, $1C39, $1C8E, $1CE4, $1D3A, $1D91, $1DE8
	    DECLE   $1E40, $1E98, $1EF1, $1F4A, $1FA4, $1FFE, $2059, $20B4
	    DECLE   $2110, $216C, $21C9, $2226, $2284, $22E2, $2341, $23A0
	    DECLE   $2400, $2460, $24C1, $2522, $2584, $25E6, $2649, $26AC
	    DECLE   $2710, $2774, $27D9, $283E, $28A4, $290A, $2971, $29D8
	    DECLE   $2A40, $2AA8, $2B11, $2B7A, $2BE4, $2C4E, $2CB9, $2D24
	    DECLE   $2D90, $2DFC, $2E69, $2ED6, $2F44, $2FB2, $3021, $3090
	    DECLE   $3100, $3170, $31E1, $3252, $32C4, $3336, $33A9, $341C
	    DECLE   $3490, $3504, $3579, $35EE, $3664, $36DA, $3751, $37C8
	    DECLE   $3840, $38B8, $3931, $39AA, $3A24, $3A9E, $3B19, $3B94
	    DECLE   $3C10, $3C8C, $3D09, $3D86, $3E04, $3E82, $3F01, $3F80
	    DECLE   $4000, $4080, $4101, $4182, $4204, $4286, $4309, $438C
	    DECLE   $4410, $4494, $4519, $459E, $4624, $46AA, $4731, $47B8
	    DECLE   $4840, $48C8, $4951, $49DA, $4A64, $4AEE, $4B79, $4C04
	    DECLE   $4C90, $4D1C, $4DA9, $4E36, $4EC4, $4F52, $4FE1, $5070
	    DECLE   $5100, $5190, $5221, $52B2, $5344, $53D6, $5469, $54FC
	    DECLE   $5590, $5624, $56B9, $574E, $57E4, $587A, $5911, $59A8
	    DECLE   $5A40, $5AD8, $5B71, $5C0A, $5CA4, $5D3E, $5DD9, $5E74
	    DECLE   $5F10, $5FAC, $6049, $60E6, $6184, $6222, $62C1, $6360
	    DECLE   $6400, $64A0, $6541, $65E2, $6684, $6726, $67C9, $686C
	    DECLE   $6910, $69B4, $6A59, $6AFE, $6BA4, $6C4A, $6CF1, $6D98
	    DECLE   $6E40, $6EE8, $6F91, $703A, $70E4, $718E, $7239, $72E4
	    DECLE   $7390, $743C, $74E9, $7596, $7644, $76F2, $77A1, $7850
	    DECLE   $7900, $79B0, $7A61, $7B12, $7BC4, $7C76, $7D29, $7DDC
	    DECLE   $7E90, $7F44, $7FF9, $80AE, $8164, $821A, $82D1, $8388
	    DECLE   $8440, $84F8, $85B1, $866A, $8724, $87DE, $8899, $8954
	    DECLE   $8A10, $8ACC, $8B89, $8C46, $8D04, $8DC2, $8E81, $8F40
	    DECLE   $9000, $90C0, $9181, $9242, $9304, $93C6, $9489, $954C
	    DECLE   $9610, $96D4, $9799, $985E, $9924, $99EA, $9AB1, $9B78
	    DECLE   $9C40, $9D08, $9DD1, $9E9A, $9F64, $A02E, $A0F9, $A1C4
	    DECLE   $A290, $A35C, $A429, $A4F6, $A5C4, $A692, $A761, $A830
	    DECLE   $A900, $A9D0, $AAA1, $AB72, $AC44, $AD16, $ADE9, $AEBC
	    DECLE   $AF90, $B064, $B139, $B20E, $B2E4, $B3BA, $B491, $B568
	    DECLE   $B640, $B718, $B7F1, $B8CA, $B9A4, $BA7E, $BB59, $BC34
	    DECLE   $BD10, $BDEC, $BEC9, $BFA6, $C084, $C162, $C241, $C320
	    DECLE   $C400, $C4E0, $C5C1, $C6A2, $C784, $C866, $C949, $CA2C
	    DECLE   $CB10, $CBF4, $CCD9, $CDBE, $CEA4, $CF8A, $D071, $D158
	    DECLE   $D240, $D328, $D411, $D4FA, $D5E4, $D6CE, $D7B9, $D8A4
	    DECLE   $D990, $DA7C, $DB69, $DC56, $DD44, $DE32, $DF21, $E010
	    DECLE   $E100, $E1F0, $E2E1, $E3D2, $E4C4, $E5B6, $E6A9, $E79C
	    DECLE   $E890, $E984, $EA79, $EB6E, $EC64, $ED5A, $EE51, $EF48
	    DECLE   $F040, $F138, $F231, $F32A, $F424, $F51E, $F619, $F714
	    DECLE   $F810, $F90C, $FA09, $FB06, $FC04, $FD02, $FE01
	    ENDP

; R0 = R0 * R1, where R0 and R1 are unsigned 8-bit values
; Destroys R1, R4
qs_mpy8:    PROC
	    MOVR    R0,	     R4      ;   6
	    ADDI    #QSQR8_TBL.mid, R1      ;   8
	    ADDR    R1,	     R4      ;   6   a + b
	    SUBR    R0,	     R1      ;   6   a - b
@@ok:       MVI@    R4,	     R0      ;   8
	    SUB@    R1,	     R0      ;   8
	    JR      R5		      ;   7
					    ;----
					    ;  49
	    ENDP
	    

; R1 = R0 * R1, where R0 and R1 are 16-bit values
; destroys R0, R2, R3, R4, R5
qs_mpy16:   PROC
	    PSHR    R5		  ;   9
				   
	    ; Unpack lo/hi
	    MOVR    R0,	 R2      ;   6   
	    ANDI    #$FF,       R0      ;   8   R0 is lo(a)
	    XORR    R0,	 R2      ;   6   
	    SWAP    R2		  ;   6   R2 is hi(a)

	    MOVR    R1,	 R3      ;   6   R3 is orig 16-bit b
	    ANDI    #$FF,       R1      ;   8   R1 is lo(b)
	    MOVR    R1,	 R5      ;   6   R5 is lo(b)
	    XORR    R1,	 R3      ;   6   
	    SWAP    R3		  ;   6   R3 is hi(b)
					;----
					;  67
					
	    ; lo * lo		   
	    MOVR    R0,	 R4      ;   6   R4 is lo(a)
	    ADDI    #QSQR8_TBL.mid, R1  ;   8
	    ADDR    R1,	 R4      ;   6   R4 = lo(a) + lo(b)
	    SUBR    R0,	 R1      ;   6   R1 = lo(a) - lo(b)
					
@@pos_ll:   MVI@    R4,	 R4      ;   8   R4 = qstbl[lo(a)+lo(b)]
	    SUB@    R1,	 R4      ;   8   R4 = lo(a)*lo(b)
					;----
					;  42
					;  67 (carried forward)
					;----
					; 109
				       
	    ; lo * hi		  
	    MOVR    R0,	 R1      ;   6   R0 = R1 = lo(a)
	    ADDI    #QSQR8_TBL.mid, R3  ;   8
	    ADDR    R3,	 R1      ;   6   R1 = hi(b) + lo(a)
	    SUBR    R0,	 R3      ;   6   R3 = hi(b) - lo(a)
				       
@@pos_lh:   MVI@    R1,	 R1      ;   8   R1 = qstbl[hi(b)-lo(a)]
	    SUB@    R3,	 R1      ;   8   R1 = lo(a)*hi(b)
					;----
					;  42
					; 109 (carried forward)
					;----
					; 151
				       
	    ; hi * lo		  
	    MOVR    R5,	 R0      ;   6   R5 = R0 = lo(b)
	    ADDI    #QSQR8_TBL.mid, R2  ;   8
	    ADDR    R2,	 R5      ;   6   R3 = hi(a) + lo(b)
	    SUBR    R0,	 R2      ;   6   R2 = hi(a) - lo(b)
				       
@@pos_hl:   ADD@    R5,	 R1      ;   8   \_ R1 = lo(a)*hi(b)+hi(a)*lo(b)
	    SUB@    R2,	 R1      ;   8   /
					;----
					;  42
					; 151 (carried forward)
					;----
					; 193
				       
	    SWAP    R1		  ;   6   \_ shift upper product left 8
	    ANDI    #$FF00,     R1      ;   8   /
	    ADDR    R4,	 R1      ;   6   final product
	    PULR    PC		  ;  12
					;----
					;  32
					; 193 (carried forward)
					;----
					; 225
	    ENDP

	ENDI

	IF DEFINED intybasic_fastdiv

; Fast unsigned division/remainder
; Assembly code by Oscar Toledo G. Jul/10/2015
; Released to public domain.

	; Ultrafast unsigned division/remainder operation
	; Entry: R0 = Dividend
	;	R1 = Divisor
	; Output: R0 = Quotient
	;	 R2 = Remainder
	; Worst case: 6 + 6 + 9 + 496 = 517 cycles
	; Best case: 6 + (6 + 7) * 16 = 214 cycles

uf_udiv16:	PROC
	CLRR R2		; 6
	SLLC R0,1	; 6
	BC @@1		; 7/9
	SLLC R0,1	; 6
	BC @@2		; 7/9
	SLLC R0,1	; 6
	BC @@3		; 7/9
	SLLC R0,1	; 6
	BC @@4		; 7/9
	SLLC R0,1	; 6
	BC @@5		; 7/9
	SLLC R0,1	; 6
	BC @@6		; 7/9
	SLLC R0,1	; 6
	BC @@7		; 7/9
	SLLC R0,1	; 6
	BC @@8		; 7/9
	SLLC R0,1	; 6
	BC @@9		; 7/9
	SLLC R0,1	; 6
	BC @@10		; 7/9
	SLLC R0,1	; 6
	BC @@11		; 7/9
	SLLC R0,1	; 6
	BC @@12		; 7/9
	SLLC R0,1	; 6
	BC @@13		; 7/9
	SLLC R0,1	; 6
	BC @@14		; 7/9
	SLLC R0,1	; 6
	BC @@15		; 7/9
	SLLC R0,1	; 6
	BC @@16		; 7/9
	JR R5

@@1:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@2:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@3:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@4:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@5:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@6:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@7:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@8:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@9:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@10:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@11:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@12:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@13:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@14:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@15:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@16:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
	JR R5
	
	ENDP

	ENDI

	IF DEFINED intybasic_ecs
	ORG $4800	; Available up to $4FFF

	; Disable ECS ROMs so that they don't conflict with us
	MVII    #$2A5F, R0
	MVO     R0,     $2FFF
	MVII    #$7A5F, R0
	MVO     R0,     $7FFF
	MVII    #$EA5F, R0
	MVO     R0,     $EFFF

	B       $1041       ; resume boot

	ENDI

	ORG $200,$200,"-RWB"

Q2:	; Reserved label for #BACKTAB

	ORG $319,$319,"-RWB"
	;
	; 16-bits variables
	; Note IntyBASIC variables grow up starting in $308.
	;
	IF DEFINED intybasic_voice
IV.Q:      RMB 8    ; IV_xxx	16-bit	  Voice queue  (8 words)
IV.FPTR:   RMB 1    ; IV_xxx	16-bit	  Current FIFO ptr.
IV.PPTR:   RMB 1    ; IV_xxx	16-bit	  Current Phrase ptr.
	ENDI

	ORG $323,$323,"-RWB"

_scroll_buffer: RMB 20  ; Sometimes this is unused
_music_gosub:	RMB 1	; GOSUB pointer
_music_table:	RMB 1	; Note table
_music_p:	RMB 1	; Pointer to music
_frame:	 RMB 1   ; Current frame
_read:	  RMB 1   ; Pointer to DATA
_gram_bitmap:   RMB 1   ; Bitmap for definition
_gram2_bitmap:  RMB 1   ; Secondary bitmap for definition
_screen:    RMB 1       ; Pointer to current screen position
_color:     RMB 1       ; Current color

_col0:      RMB 1       ; Collision status for MOB0
_col1:      RMB 1       ; Collision status for MOB1
_col2:      RMB 1       ; Collision status for MOB2
_col3:      RMB 1       ; Collision status for MOB3
_col4:      RMB 1       ; Collision status for MOB4
_col5:      RMB 1       ; Collision status for MOB5
_col6:      RMB 1       ; Collision status for MOB6
_col7:      RMB 1       ; Collision status for MOB7

Q1:			; Reserved label for #MOBSHADOW
_mobs:      RMB 3*8     ; MOB buffer

SCRATCH:    ORG $100,$100,"-RWBN"
	;
	; 8-bits variables
	;
ISRVEC:     RMB 2       ; Pointer to ISR vector (required by Intellivision ROM)
_int:       RMB 1       ; Signals interrupt received
_ntsc:      RMB 1       ; bit 0 = 1=NTSC, 0=PAL. Bit 1 = 1=ECS detected.
_rand:      RMB 1       ; Pseudo-random value
_gram_target:   RMB 1   ; Contains GRAM card number
_gram_total:    RMB 1   ; Contains total GRAM cards for definition
_gram2_target:  RMB 1   ; Contains GRAM card number
_gram2_total:   RMB 1   ; Contains total GRAM cards for definition
_mode_select:   RMB 1   ; Graphics mode selection
_border_color:  RMB 1   ; Border color
_border_mask:   RMB 1   ; Border mask
    IF DEFINED intybasic_keypad
_cnt1_p0:   RMB 1       ; Debouncing 1
_cnt1_p1:   RMB 1       ; Debouncing 2
_cnt1_key:  RMB 1       ; Currently pressed key
_cnt2_p0:   RMB 1       ; Debouncing 1
_cnt2_p1:   RMB 1       ; Debouncing 2
_cnt2_key:  RMB 1       ; Currently pressed key
    ENDI
    IF DEFINED intybasic_scroll
_scroll_x:  RMB 1       ; Scroll X offset
_scroll_y:  RMB 1       ; Scroll Y offset
_scroll_d:  RMB 1       ; Scroll direction
    ENDI
    IF DEFINED intybasic_music
_music_start:	RMB 2	; Start of music

_music_mode: RMB 1      ; Music mode (0= Not using PSG, 2= Simple, 4= Full, add 1 if using noise channel for drums)
_music_frame: RMB 1     ; Music frame (for 50 hz fixed)
_music_tc:  RMB 1       ; Time counter
_music_t:   RMB 1       ; Time base
_music_i1:  RMB 1       ; Instrument 1 
_music_s1:  RMB 1       ; Sample pointer 1
_music_n1:  RMB 1       ; Note 1
_music_i2:  RMB 1       ; Instrument 2
_music_s2:  RMB 1       ; Sample pointer 2
_music_n2:  RMB 1       ; Note 2
_music_i3:  RMB 1       ; Instrument 3
_music_s3:  RMB 1       ; Sample pointer 3
_music_n3:  RMB 1       ; Note 3
_music_s4:  RMB 1       ; Sample pointer 4
_music_n4:  RMB 1       ; Note 4 (really it's drum)

_music_freq10:	RMB 1   ; Low byte frequency A
_music_freq20:	RMB 1   ; Low byte frequency B
_music_freq30:	RMB 1   ; Low byte frequency C
_music_freq11:	RMB 1   ; High byte frequency A
_music_freq21:	RMB 1   ; High byte frequency B
_music_freq31:	RMB 1   ; High byte frequency C
_music_mix:	RMB 1   ; Mixer
_music_noise:	RMB 1   ; Noise
_music_vol1:	RMB 1   ; Volume A
_music_vol2:	RMB 1   ; Volume B
_music_vol3:	RMB 1   ; Volume C
    ENDI
    IF DEFINED intybasic_music_ecs
_music_i5:  RMB 1       ; Instrument 5
_music_s5:  RMB 1       ; Sample pointer 5
_music_n5:  RMB 1       ; Note 5
_music_i6:  RMB 1       ; Instrument 6
_music_s6:  RMB 1       ; Sample pointer 6
_music_n6:  RMB 1       ; Note 6
_music_i7:  RMB 1       ; Instrument 7
_music_s7:  RMB 1       ; Sample pointer 7
_music_n7:  RMB 1       ; Note 7
_music_s8:  RMB 1       ; Sample pointer 8
_music_n8:  RMB 1       ; Note 8 (really it's drum)

_music2_freq10:	RMB 1   ; Low byte frequency A
_music2_freq20:	RMB 1   ; Low byte frequency B
_music2_freq30:	RMB 1   ; Low byte frequency C
_music2_freq11:	RMB 1   ; High byte frequency A
_music2_freq21:	RMB 1   ; High byte frequency B
_music2_freq31:	RMB 1   ; High byte frequency C
_music2_mix:	RMB 1   ; Mixer
_music2_noise:	RMB 1   ; Noise
_music2_vol1:	RMB 1   ; Volume A
_music2_vol2:	RMB 1   ; Volume B
_music2_vol3:	RMB 1   ; Volume C
    ENDI
    IF DEFINED intybasic_music_volume
_music_vol:	RMB 1	; Global music volume
    ENDI
    IF DEFINED intybasic_voice
IV.QH:     RMB 1    ; IV_xxx	8-bit	   Voice queue head
IV.QT:     RMB 1    ; IV_xxx	8-bit	   Voice queue tail
IV.FLEN:   RMB 1    ; IV_xxx	8-bit	   Length of FIFO data
    ENDI


var_AC_I:	RMB 1	; AC_I
var_AK_APP:	RMB 1	; AK_APP
var_AK_CREATOR_HI:	RMB 1	; AK_CREATOR_HI
var_AK_CREATOR_LO:	RMB 1	; AK_CREATOR_LO
var_AK_KEY:	RMB 1	; AK_KEY
var_AK_MODE:	RMB 1	; AK_MODE
var_AK_TRY:	RMB 1	; AK_TRY
var_CARD:	RMB 1	; CARD
var_CONV_IN:	RMB 1	; CONV_IN
var_CONV_OUT:	RMB 1	; CONV_OUT
var_DEAL_COUNT:	RMB 1	; DEAL_COUNT
var_DF_C:	RMB 1	; DF_C
var_DF_I:	RMB 1	; DF_I
var_DF_LEN:	RMB 1	; DF_LEN
var_DF_POS:	RMB 1	; DF_POS
var_DF_STOP:	RMB 1	; DF_STOP
var_FIRST_POLL:	RMB 1	; FIRST_POLL
var_FN_I:	RMB 1	; FN_I
var_FN_LEN:	RMB 1	; FN_LEN
var_FN_OK:	RMB 1	; FN_OK
var_FORCE_REDRAW:	RMB 1	; FORCE_REDRAW
var_GS_CHAR:	RMB 1	; GS_CHAR
var_GS_I:	RMB 1	; GS_I
var_GS_J:	RMB 1	; GS_J
var_GS_PATH:	RMB 1	; GS_PATH
var_HAS_MOVE:	RMB 1	; HAS_MOVE
var_IM_SEL:	RMB 1	; IM_SEL
var_INP_BTN:	RMB 1	; INP_BTN
var_INP_BTN_HIT:	RMB 1	; INP_BTN_HIT
var_INP_BTN_PREV:	RMB 1	; INP_BTN_PREV
var_INP_DIR:	RMB 1	; INP_DIR
var_INP_ISKEY:	RMB 1	; INP_ISKEY
var_INP_KEY:	RMB 1	; INP_KEY
var_INP_KEY_HIT:	RMB 1	; INP_KEY_HIT
var_INP_KEY_PREV:	RMB 1	; INP_KEY_PREV
var_INP_LOCK:	RMB 1	; INP_LOCK
var_INP_NEW:	RMB 1	; INP_NEW
var_INP_RAW:	RMB 1	; INP_RAW
var_INP_ROW:	RMB 1	; INP_ROW
var_INP_SEEN:	RMB 1	; INP_SEEN
var_INP_SETTLE:	RMB 1	; INP_SETTLE
var_LS_MAX:	RMB 1	; LS_MAX
var_MB_CMD:	RMB 1	; MB_CMD
var_MB_DEV:	RMB 1	; MB_DEV
var_MB_ERR:	RMB 1	; MB_ERR
var_MB_NPARAM:	RMB 1	; MB_NPARAM
var_MB_SEQ:	RMB 1	; MB_SEQ
var_MVCODE_A:	RMB 1	; MVCODE_A
var_MVCODE_B:	RMB 1	; MVCODE_B
var_MV_COUNT:	RMB 1	; MV_COUNT
var_MV_FRAMECOUNT:	RMB 1	; MV_FRAMECOUNT
var_MV_GAP:	RMB 1	; MV_GAP
var_MV_LEN:	RMB 1	; MV_LEN
var_MV_SEL:	RMB 1	; MV_SEL
var_MV_TIMELEFT:	RMB 1	; MV_TIMELEFT
var_NET_ERR:	RMB 1	; NET_ERR
var_NE_CUR:	RMB 1	; NE_CUR
var_NE_I:	RMB 1	; NE_I
var_NE_J:	RMB 1	; NE_J
var_NE_LEN:	RMB 1	; NE_LEN
var_P:	RMB 1	; P
var_PM_I:	RMB 1	; PM_I
var_PM_SIZE:	RMB 1	; PM_SIZE
var_POLL_WAIT:	RMB 1	; POLL_WAIT
var_PREV_ACTIVE:	RMB 1	; PREV_ACTIVE
var_PREV_COMMUNITY:	RMB 1	; PREV_COMMUNITY
var_PREV_PLAYERCOUNT:	RMB 1	; PREV_PLAYERCOUNT
var_PREV_ROUND:	RMB 1	; PREV_ROUND
var_ROUND:	RMB 1	; ROUND
var_SEL_I:	RMB 1	; SEL_I
var_SEL_SEAT:	RMB 1	; SEL_SEAT
var_SND_GATE:	RMB 1	; SND_GATE
var_SND_I:	RMB 1	; SND_I
var_SND_POST:	RMB 1	; SND_POST
var_SP_C:	RMB 1	; SP_C
var_SP_FOUND:	RMB 1	; SP_FOUND
var_SP_I:	RMB 1	; SP_I
var_SP_J:	RMB 1	; SP_J
var_SP_K:	RMB 1	; SP_K
var_SP_M:	RMB 1	; SP_M
var_SP_OK:	RMB 1	; SP_OK
var_SP_VALID:	RMB 1	; SP_VALID
var_STREET_REDRAW:	RMB 1	; STREET_REDRAW
var_SUIT:	RMB 1	; SUIT
var_TBL_COUNT:	RMB 1	; TBL_COUNT
var_TBL_SEL:	RMB 1	; TBL_SEL
var_TMP_PC:	RMB 1	; TMP_PC
var_TURN_CHANGED:	RMB 1	; TURN_CHANGED
var_WANT_LEAVE:	RMB 1	; WANT_LEAVE
array_MV_COL:	RMB 5	; MV_COL
array_NE_BUF:	RMB 8	; NE_BUF
array_PREV_BET:	RMB 8	; PREV_BET
array_PREV_CARDS:	RMB 8	; PREV_CARDS
_SCRATCH:	EQU $

SYSTEM:	ORG $2F0, $2F0, "-RWBN"
STACK:	RMB 24
var_&AC_PREV:	RMB 1	; #AC_PREV
var_&COL:	RMB 1	; #COL
var_&DF_COLOR:	RMB 1	; #DF_COLOR
var_&DF_SRC:	RMB 1	; #DF_SRC
var_&FN_SRC:	RMB 1	; #FN_SRC
var_&FN_T:	RMB 1	; #FN_T
var_&FN_TXLEN:	RMB 1	; #FN_TXLEN
var_&GS_C:	RMB 1	; #GS_C
var_&NET_AVAIL:	RMB 1	; #NET_AVAIL
var_&NET_GOTLEN:	RMB 1	; #NET_GOTLEN
var_&NET_READLEN:	RMB 1	; #NET_READLEN
var_&PM_VAL:	RMB 1	; #PM_VAL
var_&PREV_POT:	RMB 1	; #PREV_POT
var_&PREV_PURSE:	RMB 1	; #PREV_PURSE
var_&PREV_RESULT_HASH:	RMB 1	; #PREV_RESULT_HASH
var_&SND_VAL:	RMB 1	; #SND_VAL
var_&TMP_ADDR:	RMB 1	; #TMP_ADDR
var_&TMP_EXPECT:	RMB 1	; #TMP_EXPECT
var_&TMP_HASH:	RMB 1	; #TMP_HASH
var_&TMP_NUM:	RMB 1	; #TMP_NUM
_SYSTEM:	EQU $
