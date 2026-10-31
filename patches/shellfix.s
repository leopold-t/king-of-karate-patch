;=====================================================================
; King of Karate - compatibility fixes for AGA machines and CPUs with
; a relocated vector base (VBR).  Appended to the code hunk of KARATE,
; TITLE and HISCORE (all three share the same start-up code).
;
; 1. AgaReset  (replaces "move.w #$7fff,DMACON" at the start of the
;    game code, i.e. right after the system copper is stopped)
;    The game was written for OCS and never touches the AGA-only
;    registers. If Workbench used an AGA screen mode before, FMODE,
;    BPLCON3 and BPLCON4 keep their values and the display is broken.
;    Writes to these registers are ignored on OCS/ECS.
;
; 2. VbrEnter / VbrLeave  (replace "move.l #entry,$80.l" before the
;    TRAP #0 and "move.w #$7fff,DMACON" after it)
;    The game installs its TRAP #0 and interrupt vectors at absolute
;    addresses $68..$80. On a 68010+ whose VBR was moved to Fast RAM
;    (68040/68060 libraries, VBR tools...) those vectors are never
;    used and the game crashes at once. For the duration of the game
;    VBR is set to 0 (with the active vectors copied there) and the
;    old VBR and the zero-page vectors are restored afterwards.
;
; 3. TITLE / HISCORE: KeyHook (in the keyboard interrupt) and, in
;    HISCORE, FireOrQuit: Amiga+Q makes the program finish normally and
;    sets the low-memory flag $18c so that the loader quits to Workbench.
;
; Assembled with -DORG=<offset of this code in the hunk> -DPROG=1/2/3
; (KARATE / TITLE / HISCORE).
; Only PC-relative addressing is used, no relocations.
;=====================================================================
	org	ORG

ENTRY		equ	$12e		; game entry called through TRAP #0
QUITFLAG	equ	$18c
KEYCELL		equ	$196		; held keys: 0 up 1 down 2 left 3 right 4 Space
					; $197: Shift / Alt (any of them = fire)
	ifeq	PROG-2
KEYVAR		equ	$2556		; TITLE: last key code
QUITKEY		equ	$50		; F1 -> title ends
	endc
	ifeq	PROG-3
KEYVAR		equ	$2a3a		; HISCORE: last key code
QUITKEY		equ	$44		; Return -> name entry ends
	endc
LVO_Supervisor	equ	-30
LVO_CacheClearU	equ	-636

; ------------------------------------------------------------------
; called in supervisor mode by the game, A6 = custom base - $5a7c
	bra.w	AgaReset	; +0
	bra.w	VbrEnter	; +4
	bra.w	VbrLeave	; +8
	ifne	PROG-1
	bra.w	KeyHook		; +12
	bra.w	FireOrQuit	; +16
	endc
	ifeq	PROG-3
	bra.w	HsKey		; +20 replaces move.b KEYVAR(pc),d1 at $370
	endc

AgaReset:
	move.w	#$7fff,$5a7c+$096(a6)	; DMACON  (the replaced instruction)
	move.w	#$0000,$5a7c+$1fc(a6)	; FMODE   : OCS fetch mode
	move.w	#$0c00,$5a7c+$106(a6)	; BPLCON3 : bank 0, default
	move.w	#$0011,$5a7c+$10c(a6)	; BPLCON4 : no colour XOR, sprites 16-31
	move.w	#$0024,$5a7c+$104(a6)	; BPLCON2 : KILLEHB off, default priority
	rts

; ------------------------------------------------------------------
; user mode, before TRAP #0
VbrEnter:
	ifne	PROG-1
	clr.w	KEYCELL.w		; no keys held from the previous program
	endc
	movem.l	d0-d1/a0-a1/a5-a6,-(sp)
	lea	VbrUsed(pc),a0
	clr.w	(a0)
	move.l	4.w,a6
	btst	#0,$129(a6)		; AttnFlags: AFF_68010 (also set on 020+)
	beq.s	.novbr
	lea	SupEnter(pc),a5
	jsr	LVO_Supervisor(a6)
	bsr.w	ClearCaches
.novbr:	lea	ENTRY(pc),a0
	move.l	a0,$80.w		; TRAP #0 vector (VBR is 0 now)
	movem.l	(sp)+,d0-d1/a0-a1/a5-a6
	rts

SupEnter:
	dc.l	$4e7a0801		; movec vbr,d0
	lea	OldVbr(pc),a0
	move.l	d0,(a0)
	tst.l	d0
	beq.s	.zero			; already 0 - nothing to do
	move.l	d0,a1			; active table
	lea	SaveZero(pc),a0
	move.w	#$100-8,d1		; save zero-page vectors 2..63
	lea	8.w,a5
.s:	move.b	(a5)+,(a0)+
	subq.w	#1,d1
	bne.s	.s
	lea	8(a1),a1		; copy active vectors 2..63 to zero page
	lea	8.w,a5
	move.w	#$100-8,d1
.c:	move.b	(a1)+,(a5)+
	subq.w	#1,d1
	bne.s	.c
	moveq	#0,d0
	dc.l	$4e7b0801		; movec d0,vbr
	lea	VbrUsed(pc),a0
	move.w	#1,(a0)
.zero:	rte

; ------------------------------------------------------------------
; user mode, after TRAP #0, interrupts already disabled, A6 = $dff000
VbrLeave:
	move.w	#$7fff,$96(a6)		; DMACON  (the replaced instruction)
	movem.l	d0-d1/a0-a1/a5-a6,-(sp)
	move.w	VbrUsed(pc),d0
	beq.s	.x
	move.l	4.w,a6
	lea	SupLeave(pc),a5
	jsr	LVO_Supervisor(a6)
	bsr.w	ClearCaches
.x:	movem.l	(sp)+,d0-d1/a0-a1/a5-a6
	rts

SupLeave:
	lea	SaveZero(pc),a0		; restore zero-page vectors 2..63
	lea	8.w,a5
	move.w	#$100-8,d1
.r:	move.b	(a0)+,(a5)+
	subq.w	#1,d1
	bne.s	.r
	move.l	OldVbr(pc),d0
	dc.l	$4e7b0801		; movec d0,vbr
	lea	VbrUsed(pc),a0
	clr.w	(a0)
	rte

	ifne	PROG-1
; ------------------------------------------------------------------
; KeyHook: replaces "move.b d0,KEYVAR" in the keyboard interrupt
;   d0 = key code; d0-d7/a0-a4 saved by the handler, a1 in use
KeyHook:
	lea	KEYVAR(pc),a0
	move.b	d0,(a0)
	; cursor keys and Space -> $196 (held keys, read by the start-up
	; screen and the stage menu like a joystick)
	lea	KeyBitTab(pc),a2
	move.b	d0,d1
	and.b	#$7f,d1
.kt:	move.b	(a2)+,d2
	bmi.s	.kn
	cmp.b	(a2)+,d1
	bne.s	.kt
	lea	KEYCELL.w,a3
	cmp.b	#8,d2
	blo.s	.kb
	addq.l	#1,a3			; bits 8-11 -> $197 bits 0-3
.kb:	tst.b	d0
	bmi.s	.kup
	bset	d2,(a3)
	bra.s	.kn
.kup:	bclr	d2,(a3)
.kn:
	lea	AmigaHeld(pc),a2
	move.b	d0,d1
	and.b	#$7e,d1
	cmp.b	#$66,d1			; left/right Amiga, down or up
	bne.s	.q
	tst.b	d0
	smi	d1
	not.b	d1
	move.b	d1,(a2)			; $ff while held
	rts
.q:	cmp.b	#$10,d0			; Q
	bne.s	.x
	tst.b	(a2)
	beq.s	.x
	move.l	#1,QUITFLAG.w
	move.b	#QUITKEY,(a0)
.x:	rts

; FireOrQuit: replaces "btst #6,$bfe001" in HISCORE's wait for fire
;   also "presses" fire after a few seconds when the CPU won
FireOrQuit:
	tst.l	QUITFLAG.w
	bne.s	.yes
	ifeq	PROG-3
	cmp.b	#'A',$194.w
	bne.s	.f
	movem.l	d0/a0,-(sp)
	bsr	BeamTick		; Z = 0 on a new frame half
	beq.s	.n
	lea	FireWait(pc),a0
	addq.w	#1,(a0)
.n:	lea	FireWait(pc),a0
	cmp.w	#3*100,(a0)		; (100 ticks per second)
	movem.l	(sp)+,d0/a0
	bhs.s	.yes
	endc
.f:	btst	#4,KEYCELL.w		; Space, Shift or Alt = fire
	bne.s	.yes
	tst.b	KEYCELL+1.w
	bne.s	.yes
	btst	#6,$bfe001
	rts
.yes:	move.w	#4,ccr			; Z = 1: like fire pressed
	rts

	ifeq	PROG-3
; HsKey: replaces "move.b KEYVAR(pc),d1" in the name entry. When the
;   computer won it types AMIGA and Return. Keeps all but d1.
HsKey:	cmp.b	#'A',$194.w
	beq.s	.auto
	move.b	KEYVAR(pc),d1
	rts
.auto:	movem.l	d0/a0,-(sp)
	bsr	BeamTick
	beq.s	.same
	lea	HsCnt(pc),a0
	addq.w	#1,(a0)
	cmp.w	#25,(a0)		; a key every quarter second
	blo.s	.same
	clr.w	(a0)
	lea	HsIdx(pc),a0
	move.w	(a0),d0
	cmp.w	#6,d0
	bhs.s	.same
	addq.w	#1,(a0)
	lea	HsCur(pc),a0
	move.b	HsSeq(pc,d0.w),(a0)
.same:	move.b	HsCur(pc),d1
	movem.l	(sp)+,d0/a0
	rts
HsSeq:	dc.b	$20,$37,$17,$24,$20,$44	; A M I G A Return
HsCur:	dc.b	0,0
HsCnt:	dc.w	0
HsIdx:	dc.w	0
FireWait:	dc.w	0

; BeamTick: Z = 0 when the beam passed line 0 or 256 since the last call
BeamTick:
	move.b	$dff006,d0
	lea	BeamLast(pc),a0
	cmp.b	(a0),d0
	bhs.s	.no
	move.b	d0,(a0)
	moveq	#1,d0			; Z = 0
	rts
.no:	move.b	d0,(a0)
	moveq	#0,d0			; Z = 1
	rts
BeamLast:	dc.w	0
	endc

AmigaHeld:	dc.w	0
KeyBitTab:	dc.b	0,$4c,1,$4d,2,$4f,3,$4e,4,$40	; bit, key code: cursors, Space
		dc.b	8,$60,9,$61,10,$64,11,$65,-1	; Shift, Alt (left, right)
	even
	endc

; flush caches after changing vectors (Kickstart 2.0+ only), A6 = exec
ClearCaches:
	cmp.w	#37,$14(a6)		; LIB_VERSION
	blo.s	.x
	jsr	LVO_CacheClearU(a6)
.x:	rts

	cnop	0,4
OldVbr:		dc.l	0
VbrUsed:	dc.w	0
SaveZero:	dcb.b	$100-8,0
	cnop	0,4
