;=====================================================================
; King of Karate - TITLE patch
;  - shows title.bg (EHB/HAM) natively instead of the OpalVision picture
;  - start-up screen before the stage menu: game mode and difficulty
;    (joystick in port 2), "Quit to Workbench: Amiga+Q",
;    "Press Fire to continue". Shown once per start of the game and
;    again when Fire is pressed on the stage menu.
;  - demo mode: the stage is chosen automatically after a few seconds
; The choice goes to low memory $190 ('K', mode, level) for KARATE.
;   appended to the TITLE code hunk, PC/A5-relative only.
;=====================================================================
	org	$3808			; end of the original TITLE code hunk

O_BUF		equ	$2454		; chip buffer allocated by the game
	ifnd	AGA
AGA		equ	0
	endc
	if	AGA
BGHDR		equ	128+512		; header + 128 colours (24 bit)
TPLANES		equ	8
	else
BGHDR		equ	128
TPLANES		equ	6
	endc
TW		equ	352
TH		equ	236
TPL		equ	TW/8		; 44
TROW		equ	TPLANES*TPL
BMSIZE		equ	TH*TROW
COPOFF		equ	BGHDR+BMSIZE+64	; our copper list inside the buffer
SETUPOFF	equ	COPOFF+512	; start-up screen: 2 planes 640 x 200 (hires)
SPL		equ	80
SROW		equ	2*SPL
SROWS		equ	200
SCOPOFF		equ	SETUPOFF+SROWS*SROW
BUFSIZE		equ	SCOPOFF+256

KEYVAR		equ	$2556		; last key code (keyboard interrupt)
QUITFLAG	equ	$18c
MODECELL	equ	$190		; 'K', mode ('2' 'L' 'R' 'C'), level ('E' 'N' 'H')
SHOWNCELL	equ	$193		; 'S' once the start-up screen was shown
					; (cleared by the loader at start)
KEYCELL		equ	$196		; keys held (shellfix KeyHook): bit 0 up,
					; 1 down, 2 left, 3 right (cursors), 4 Space

	bra.w	TitleShow	; +0 replaces $8f0
	bra.w	TitleHook	; +4 replaces move.b KEYVAR(pc),d1 at $20a

;---------------------------------------------------------------------
TitleShow:
	movem.l	d0-d7/a0-a4,-(sp)
	clr.w	KEYCELL.w
	bsr	LoadMode
	cmp.b	#'S',SHOWNCELL.w
	beq.s	.t
	bsr	SetupScreen
.t:	bsr	TitleCopper
	movem.l	(sp)+,d0-d7/a0-a4
	rts

TitleCopper:
	movem.l	d0-d3/a0-a2/a4,-(sp)
	lea	$dff000,a4
	move.l	O_BUF(a5),a2		; .bg file (header + bitmap)
	move.l	a2,a0
	add.l	#COPOFF,a0
	move.l	#$00968100,(a0)+	; bitplane DMA on
	move.l	#$01000200,(a0)+
	bsr	NullSprites
	move.l	#$008e2c71,(a0)+	; DIWSTRT
	move.l	#$009018d1,(a0)+	; DIWSTOP (line 280)
	move.l	#$00920030,(a0)+	; DDFSTRT
	move.l	#$009400d8,(a0)+	; DDFSTOP
	move.w	#$0108,(a0)+
	move.w	#TROW-TPL,(a0)+
	move.w	#$010a,(a0)+
	move.w	#TROW-TPL,(a0)+
	move.l	#$01020000,(a0)+
	move.l	#$01040024,(a0)+
	if	AGA
	bsr	SetPalette		; 256 colours (CPU)
	move.l	#$01fc0000,(a0)+	; FMODE 0 (still picture)
	move.l	#$01060c00,(a0)+	; BPLCON3
	move.l	#$010c0011,(a0)+	; BPLCON4
	else
	lea	12(a2),a1		; colours
	move.w	#$180,d0
.col:	move.w	d0,(a0)+
	move.w	(a1)+,(a0)+
	addq.w	#2,d0
	cmp.w	#$1c0,d0
	bne.s	.col
	endif
	lea	BGHDR(a2),a1		; bitplane pointers
	move.l	a1,d1
	moveq	#TPLANES,d2
	moveq	#TPL,d3
	bsr	PlanePtrs
	move.w	#$0100,(a0)+
	if	AGA
	move.w	#$0210,d0		; 8 planes
	else
	move.w	#$6200,d0
	tst.w	4(a2)
	beq.s	.ehb
	or.w	#$0800,d0
.ehb:
	endif
	move.w	d0,(a0)+
	move.l	#$fffffffe,(a0)+
	move.l	a2,a0
	add.l	#COPOFF,a0
	move.l	a0,$80(a4)
	move.w	#0,$88(a4)
	movem.l	(sp)+,d0-d3/a0-a2/a4
	rts

	if	AGA
; SetPalette: colours 0-127 from the .bg file (24 bit), 128-255 at half
;   brightness. a2 = .bg buffer, a4 = custom chips. Keeps all registers.
SetPalette:
	movem.l	d0-d7/a0-a1,-(sp)
	move.w	2(a4),-(sp)		; DMACONR
	move.w	#$0080,$96(a4)		; copper off meanwhile: its colour moves
					; would land in the bank being written
	lea	128(a2),a0
	moveq	#0,d7
.c:	move.w	d7,d0
	and.w	#127,d0
	lsl.w	#2,d0
	move.l	(a0,d0.w),d1
	cmp.w	#128,d7
	blo.s	.full
	lsr.l	#1,d1
	and.l	#$007f7f7f,d1
.full:	move.l	d1,d4
	swap	d4
	move.w	d1,d5
	lsr.w	#8,d5
	move.w	d1,d6
	move.w	d4,d2
	and.w	#$f0,d2
	lsl.w	#4,d2
	move.w	d5,d0
	and.w	#$f0,d0
	or.w	d0,d2
	move.w	d6,d0
	and.w	#$f0,d0
	lsr.w	#4,d0
	or.w	d0,d2
	move.w	d4,d3
	and.w	#$0f,d3
	lsl.w	#8,d3
	move.w	d5,d0
	and.w	#$0f,d0
	lsl.w	#4,d0
	or.w	d0,d3
	move.w	d6,d0
	and.w	#$0f,d0
	or.w	d0,d3
	move.w	d7,d0
	lsr.w	#5,d0
	ror.w	#3,d0
	or.w	#$0c00,d0
	move.w	d7,d1
	and.w	#31,d1
	add.w	d1,d1
	lea	$180(a4),a1
	add.w	d1,a1
	move.w	d0,$106(a4)
	move.w	d2,(a1)
	or.w	#$0200,d0
	move.w	d0,$106(a4)
	move.w	d3,(a1)
	addq.w	#1,d7
	cmp.w	#256,d7
	bne	.c
	move.w	#$0c00,$106(a4)
	move.w	(sp)+,d0
	and.w	#$0080,d0
	beq.s	.nc
	move.w	#$8080,$96(a4)		; copper on again
.nc:	movem.l	(sp)+,d0-d7/a0-a1
	rts
	endif

; a0 = copper pointer, a2 = buffer: sprites -> null sprite (header pad)
NullSprites:
	lea	120(a2),a1
	move.l	a1,d1
	move.w	#$120,d0
.sp:	move.w	d0,(a0)+
	swap	d1
	move.w	d1,(a0)+
	addq.w	#2,d0
	move.w	d0,(a0)+
	swap	d1
	move.w	d1,(a0)+
	addq.w	#2,d0
	cmp.w	#$140,d0
	bne.s	.sp
	rts

; a0 = copper, d1 = first plane, d2 = planes, d3 = plane step
PlanePtrs:
	move.w	#$e0,d0
.bp:	move.w	d0,(a0)+
	swap	d1
	move.w	d1,(a0)+
	addq.w	#2,d0
	move.w	d0,(a0)+
	swap	d1
	move.w	d1,(a0)+
	addq.w	#2,d0
	add.l	d3,d1
	subq.w	#1,d2
	bne.s	.bp
	rts

;---------------------------------------------------------------------
; mode / level <-> low memory
LoadMode:
	lea	MVars(pc),a3
	clr.w	(a3)			; mode: two players
	move.w	#1,2(a3)		; level: normal
	cmp.b	#'K',MODECELL.w
	bne.s	StoreMode
	move.b	MODECELL+1.w,d0
	lea	ModeChars(pc),a0
	moveq	#3,d2
.fm:	cmp.b	(a0,d2.w),d0
	beq.s	.fm1
	dbf	d2,.fm
	moveq	#0,d2
.fm1:	move.w	d2,(a3)
	move.b	MODECELL+2.w,d0
	lea	LevelChars(pc),a0
	moveq	#2,d2
.fl:	cmp.b	(a0,d2.w),d0
	beq.s	.fl1
	dbf	d2,.fl
	moveq	#1,d2
.fl1:	move.w	d2,2(a3)
StoreMode:
	lea	MVars(pc),a3
	lea	MODECELL.w,a0
	move.b	#'K',(a0)+
	move.w	(a3),d0
	move.b	ModeChars(pc,d0.w),(a0)+
	move.w	2(a3),d0
	move.b	LevelChars(pc,d0.w),(a0)+
	rts
ModeChars:	dc.b	'2LRC'
LevelChars:	dc.b	'ENH',0

; wait for the next frame (beam passes line 16)
NextFrame:
.w1:	cmp.b	#16,$dff006
	beq.s	.w1
.w2:	cmp.b	#16,$dff006
	bne.s	.w2
	rts

; d0 = joystick port 2 bits: 0 up, 1 down, 2 left, 3 right, 4 fire
ReadJoy:
	movem.l	d1-d2,-(sp)
	move.w	$dff00c,d1
	moveq	#0,d0
	btst	#1,d1
	beq.s	.1
	bset	#3,d0
.1:	btst	#9,d1
	beq.s	.2
	bset	#2,d0
.2:	move.w	d1,d2
	lsr.w	#1,d1
	eor.w	d2,d1			; bit 0 down, bit 8 up
	btst	#0,d1
	beq.s	.3
	bset	#1,d0
.3:	btst	#8,d1
	beq.s	.4
	bset	#0,d0
.4:	btst	#7,$bfe001
	bne.s	.5
	bset	#4,d0
.5:	moveq	#$1f,d1			; cursor keys and Space
	and.b	KEYCELL.w,d1
	or.w	d1,d0
	tst.b	KEYCELL+1.w		; Shift / Alt = fire too
	beq.s	.6
	bset	#4,d0
.6:
	movem.l	(sp)+,d1-d2
	rts

;---------------------------------------------------------------------
; TitleHook: in the stage menu's wait loop (replaces the key read).
;   Fire -> start-up screen again; demo mode -> random stage after a
;   few seconds. Out: d1.b = key code. Keeps everything else.
;---------------------------------------------------------------------
TitleHook:
	movem.l	d0/d2-d7/a0-a4,-(sp)
	lea	HVars(pc),a3
	move.b	$dff006,d0		; once per frame (beam wrapped)
	move.b	(a3),d2
	move.b	d0,(a3)
	cmp.b	d2,d0
	bhs	.key
	cmp.b	#$80,d0			; ignore the wrap at line 256
	bhs	.key
	bsr	ReadJoy
	move.w	2(a3),d2		; previous
	move.w	d0,2(a3)
	not.w	d2
	and.w	d2,d0
	btst	#4,d0			; Fire pressed: back to the start-up screen
	beq.s	.demo
	bsr	SetupScreen
	bsr	TitleCopper
	move.w	#$10,2(a3)		; fire counts as held
	clr.w	4(a3)
	bra.s	.key
.demo:	lea	MVars(pc),a0
	cmp.w	#3,(a0)
	bne.s	.key
	addq.w	#1,4(a3)
	cmp.w	#4*50,4(a3)		; about 4 seconds
	blo.s	.key
	clr.w	4(a3)
	move.w	$dff006,d0		; "random" stage F1..F3
	and.w	#$ff,d0
	divu	#3,d0
	swap	d0
	add.b	#$50,d0
	lea	KEYVAR(pc),a0
	move.b	d0,(a0)
.key:	movem.l	(sp)+,d0/d2-d7/a0-a4
	move.b	KEYVAR(pc),d1
	rts
HVars:	dc.w	0,$10,0			; last beam line, joystick, demo frames

;---------------------------------------------------------------------
; SetupScreen: 2-plane text screen; loops until Fire (or Amiga+Q)
;---------------------------------------------------------------------
SetupScreen:
	movem.l	d0-d7/a0-a4,-(sp)
	move.b	#'S',SHOWNCELL.w
	lea	$dff000,a4
	move.l	O_BUF(a5),a2
	; ---- copper ----
	move.l	a2,a0
	add.l	#SCOPOFF,a0
	move.l	a0,-(sp)
	move.l	#$00968100,(a0)+
	move.l	#$01000200,(a0)+
	bsr	NullSprites
	move.l	#$008e2c81,(a0)+	; 640 x 200 hires from line $2c
	move.l	#$0090f4c1,(a0)+
	move.l	#$0092003c,(a0)+
	move.l	#$009400d4,(a0)+
	move.l	#$01080000+SPL,(a0)+
	move.l	#$010a0000+SPL,(a0)+
	move.l	#$01020000,(a0)+
	move.l	#$01040000,(a0)+
	move.l	#$01800000,(a0)+	; black
	move.l	#$01820fff,(a0)+	; white
	move.l	#$01840fc2,(a0)+	; yellow
	move.l	#$01860889,(a0)+	; grey
	move.l	a2,d1
	add.l	#SETUPOFF,d1
	moveq	#2,d2
	moveq	#SPL,d3
	bsr	PlanePtrs
	move.l	#$0100a200,(a0)+	; hires, 2 planes
	move.l	#$fffffffe,(a0)+
	; ---- clear the bitmap, static texts ----
	move.l	a2,a0
	add.l	#SETUPOFF,a0
	move.l	a0,a2			; a2 = setup bitmap from here on
	move.w	#SROWS*SROW/4-1,d0
.cl:	clr.l	(a0)+
	dbf	d0,.cl
	lea	TxtTitle(pc),a0
	moveq	#3*8,d0
	moveq	#2,d4
	moveq	#4,d5			; 4 x 2 hires pixels per font pixel
	moveq	#2,d6
	bsr	PutText
	moveq	#2,d5			; normal text: 2 x 1
	moveq	#1,d6
	lea	TxtSub(pc),a0
	moveq	#6*8,d0
	moveq	#3,d4
	bsr	PutText
	lea	TxtMode(pc),a0
	moveq	#10*8,d0
	moveq	#1,d4
	bsr	PutText
	lea	TxtLevel(pc),a0
	move.w	#15*8,d0
	moveq	#1,d4
	bsr	PutText
	moveq	#1,d5			; small print: 1 x 1
	lea	TxtPort(pc),a0
	move.w	#19*8,d0
	moveq	#3,d4
	bsr	PutText
	lea	TxtKeys(pc),a0
	move.w	#20*8+3,d0
	moveq	#3,d4
	bsr	PutText
	moveq	#2,d5
	lea	TxtQuit(pc),a0
	move.w	#22*8,d0
	moveq	#1,d4
	bsr	PutText
	lea	TxtFire(pc),a0
	move.w	#24*8-2,d0
	moveq	#2,d4
	bsr	PutText
	bsr	DrawValues
	move.l	(sp)+,a0
	bsr	NextFrame
	move.l	a0,$80(a4)
	move.w	#0,$88(a4)
	; ---- loop ----
	moveq	#$1f,d7			; joystick state (all held: wait for release)
.lp:	bsr	NextFrame
	tst.l	QUITFLAG.w
	bne.s	.out
	bsr	ReadJoy
	move.w	d7,d1
	move.w	d0,d7
	not.w	d1
	and.w	d1,d0			; newly pressed
	beq.s	.lp
	btst	#4,d0
	bne.s	.out
	lea	MVars(pc),a3
	move.w	(a3),d1			; mode
	btst	#0,d0
	beq.s	.m1
	subq.w	#1,d1
.m1:	btst	#1,d0
	beq.s	.m2
	addq.w	#1,d1
.m2:	and.w	#3,d1
	move.w	d1,(a3)
	move.w	2(a3),d1		; level
	btst	#2,d0
	beq.s	.l1
	subq.w	#1,d1
	bpl.s	.l1
	moveq	#2,d1
.l1:	btst	#3,d0
	beq.s	.l2
	addq.w	#1,d1
	cmp.w	#3,d1
	bne.s	.l2
	moveq	#0,d1
.l2:	move.w	d1,2(a3)
	bsr	StoreMode
	bsr	DrawValues
	bra.s	.lp
.out:	movem.l	(sp)+,d0-d7/a0-a4
	rts

; DrawValues: mode and level lines (a2 = setup bitmap)
DrawValues:
	movem.l	d0-d6/a0-a1/a3,-(sp)
	move.l	a2,a0			; clear text rows 12 and 17
	add.l	#12*8*SROW,a0
	bsr.s	ClrRow
	move.l	a2,a0
	add.l	#17*8*SROW,a0
	bsr.s	ClrRow
	lea	MVars(pc),a3
	move.w	(a3),d0
	add.w	d0,d0
	lea	ModeNames(pc),a0
	add.w	(a0,d0.w),a0
	moveq	#12*8,d0
	moveq	#2,d4
	moveq	#2,d5
	moveq	#1,d6
	bsr	PutText
	lea	TxtNoLevel(pc),a0
	moveq	#3,d4
	tst.w	(a3)
	beq.s	.v
	move.w	2(a3),d0
	add.w	d0,d0
	lea	LevelNames(pc),a0
	add.w	(a0,d0.w),a0
	moveq	#2,d4
.v:	move.w	#17*8,d0
	bsr	PutText
	movem.l	(sp)+,d0-d6/a0-a1/a3
	rts

ClrRow:	move.w	#8*SROW/4-1,d0
.c:	clr.l	(a0)+
	dbf	d0,.c
	rts

; PutText: a0 string, d0 pixel row, d4 colour (1-3), d5 = horizontal
;   scale (hires pixels per font pixel: 1, 2 or 4), d6 = vertical scale.
;   Centred on the 640 pixel wide screen; a2 = setup bitmap.
PutText:
	movem.l	d0-d7/a0-a1/a3-a4,-(sp)
	move.l	a0,a1
	moveq	#-1,d1
.n:	addq.w	#1,d1
	tst.b	(a1)+
	bne.s	.n
	lsl.w	#3,d1
	mulu	d5,d1			; width in pixels
	neg.w	d1
	add.w	#640,d1
	lsr.w	#1,d1			; d1 = x of the first pixel
	mulu	#SROW,d0
	lea	(a2,d0.l),a3		; a3 = first row
.ch:	moveq	#0,d2
	move.b	(a0)+,d2
	beq.s	.x
	sub.w	#32,d2
	lsl.w	#3,d2
	lea	Font(pc),a4
	add.w	d2,a4			; glyph
	move.l	a3,a1			; row pointer
	moveq	#8-1,d3			; glyph rows
.gy:	move.b	(a4)+,d2
	move.w	d6,d7			; vertical repeats
	subq.w	#1,d7
.ry:	movem.w	d1-d2,-(sp)
	moveq	#8-1,d0			; font pixels
.px:	add.b	d2,d2
	bcc.s	.skip
	movem.w	d0-d1,-(sp)
	move.w	d5,-(sp)		; horizontal repeats
.rx:	move.w	d1,d0
	lsr.w	#3,d0			; byte
	not.w	d1			; bit = 7 - (x & 7) (bset uses mod 8)
	btst	#0,d4
	beq.s	.c1
	bset	d1,(a1,d0.w)
.c1:	btst	#1,d4
	beq.s	.c2
	bset	d1,SPL(a1,d0.w)
.c2:	not.w	d1
	addq.w	#1,d1
	subq.w	#1,(sp)
	bne.s	.rx
	addq.l	#2,sp
	movem.w	(sp)+,d0-d1
.skip:	add.w	d5,d1
	dbf	d0,.px
	movem.w	(sp)+,d1-d2
	lea	SROW(a1),a1
	dbf	d7,.ry
	dbf	d3,.gy
	move.w	d5,d0
	lsl.w	#3,d0
	add.w	d0,d1			; next character
	bra.s	.ch
.x:	movem.l	(sp)+,d0-d7/a0-a1/a3-a4
	rts

TxtTitle:	dc.b	'King of Karate',0
TxtSub:		dc.b	'(c) 1992 Centaur - OCS/ECS/AGA patch',0
TxtPort:	dc.b	'Use the joystick in Port 2 or the cursor keys to select options',0
TxtKeys:	dc.b	'Fight keys: W A S D + left Shift or Alt  /  cursor keys + right Shift or Alt',0
TxtMode:	dc.b	'Game mode - Up / Down to select:',0
TxtLevel:	dc.b	'Difficulty - Left / Right to select:',0
TxtNoLevel:	dc.b	'-',0
TxtQuit:	dc.b	'Quit to Workbench: Amiga+Q',0
TxtFire:	dc.b	'Press Fire or Space to continue',0
	even
ModeNames:	dc.w	M0-ModeNames,M1-ModeNames,M2-ModeNames,M3-ModeNames
LevelNames:	dc.w	L0-LevelNames,L1-LevelNames,L2-LevelNames
M0:	dc.b	'< 2 players >',0
M1:	dc.b	'< You (left) vs CPU >',0
M2:	dc.b	'< CPU vs You (right) >',0
M3:	dc.b	'< Demo: CPU vs CPU >',0
L0:	dc.b	'< Easy >',0
L1:	dc.b	'< Normal >',0
L2:	dc.b	'< Hard >',0
	even
MVars:	dc.w	0,1			; mode, level
Font:
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00	; ' '
	dc.b	$20,$20,$20,$20,$20,$00,$20,$00	; '!'
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00	; '"'
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00	; '#'
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00	; '$'
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00	; '%'
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00	; '&'
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00	; "'"
	dc.b	$20,$40,$80,$80,$80,$40,$20,$00	; '('
	dc.b	$20,$10,$08,$08,$08,$10,$20,$00	; ')'
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00	; '*'
	dc.b	$00,$20,$20,$f8,$20,$20,$00,$00	; '+'
	dc.b	$00,$00,$00,$00,$30,$10,$20,$00	; ','
	dc.b	$00,$00,$00,$f8,$00,$00,$00,$00	; '-'
	dc.b	$00,$00,$00,$00,$00,$60,$60,$00	; '.'
	dc.b	$08,$10,$10,$20,$40,$40,$80,$00	; '/'
	dc.b	$70,$88,$98,$a8,$c8,$88,$70,$00	; '0'
	dc.b	$20,$60,$20,$20,$20,$20,$70,$00	; '1'
	dc.b	$70,$88,$08,$10,$20,$40,$f8,$00	; '2'
	dc.b	$f0,$08,$08,$70,$08,$08,$f0,$00	; '3'
	dc.b	$10,$30,$50,$90,$f8,$10,$10,$00	; '4'
	dc.b	$f8,$80,$f0,$08,$08,$88,$70,$00	; '5'
	dc.b	$30,$40,$80,$f0,$88,$88,$70,$00	; '6'
	dc.b	$f8,$08,$10,$20,$40,$40,$40,$00	; '7'
	dc.b	$70,$88,$88,$70,$88,$88,$70,$00	; '8'
	dc.b	$70,$88,$88,$78,$08,$10,$60,$00	; '9'
	dc.b	$00,$60,$60,$00,$60,$60,$00,$00	; ':'
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00	; ';'
	dc.b	$10,$20,$40,$80,$40,$20,$10,$00	; '<'
	dc.b	$00,$00,$f8,$00,$f8,$00,$00,$00	; '='
	dc.b	$40,$20,$10,$08,$10,$20,$40,$00	; '>'
	dc.b	$70,$88,$08,$10,$20,$00,$20,$00	; '?'
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00	; '@'
	dc.b	$70,$88,$88,$f8,$88,$88,$88,$00	; 'A'
	dc.b	$f0,$88,$88,$f0,$88,$88,$f0,$00	; 'B'
	dc.b	$70,$88,$80,$80,$80,$88,$70,$00	; 'C'
	dc.b	$f0,$88,$88,$88,$88,$88,$f0,$00	; 'D'
	dc.b	$f8,$80,$80,$f0,$80,$80,$f8,$00	; 'E'
	dc.b	$f8,$80,$80,$f0,$80,$80,$80,$00	; 'F'
	dc.b	$70,$88,$80,$b8,$88,$88,$78,$00	; 'G'
	dc.b	$88,$88,$88,$f8,$88,$88,$88,$00	; 'H'
	dc.b	$70,$20,$20,$20,$20,$20,$70,$00	; 'I'
	dc.b	$38,$10,$10,$10,$10,$90,$60,$00	; 'J'
	dc.b	$88,$90,$a0,$c0,$a0,$90,$88,$00	; 'K'
	dc.b	$80,$80,$80,$80,$80,$80,$f8,$00	; 'L'
	dc.b	$88,$d8,$a8,$a8,$88,$88,$88,$00	; 'M'
	dc.b	$88,$88,$c8,$a8,$98,$88,$88,$00	; 'N'
	dc.b	$70,$88,$88,$88,$88,$88,$70,$00	; 'O'
	dc.b	$f0,$88,$88,$f0,$80,$80,$80,$00	; 'P'
	dc.b	$70,$88,$88,$88,$a8,$90,$68,$00	; 'Q'
	dc.b	$f0,$88,$88,$f0,$a0,$90,$88,$00	; 'R'
	dc.b	$78,$80,$80,$70,$08,$08,$f0,$00	; 'S'
	dc.b	$f8,$20,$20,$20,$20,$20,$20,$00	; 'T'
	dc.b	$88,$88,$88,$88,$88,$88,$70,$00	; 'U'
	dc.b	$88,$88,$88,$88,$88,$50,$20,$00	; 'V'
	dc.b	$88,$88,$88,$a8,$a8,$a8,$50,$00	; 'W'
	dc.b	$88,$88,$50,$20,$50,$88,$88,$00	; 'X'
	dc.b	$88,$88,$50,$20,$20,$20,$20,$00	; 'Y'
	dc.b	$f8,$08,$10,$20,$40,$80,$f8,$00	; 'Z'
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00	; '['
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00	; '\\'
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00	; ']'
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00	; '^'
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00	; '_'
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00	; '`'
	dc.b	$00,$00,$70,$08,$78,$88,$78,$00	; 'a'
	dc.b	$80,$80,$f0,$88,$88,$88,$f0,$00	; 'b'
	dc.b	$00,$00,$70,$80,$80,$80,$70,$00	; 'c'
	dc.b	$08,$08,$78,$88,$88,$88,$78,$00	; 'd'
	dc.b	$00,$00,$70,$88,$f8,$80,$70,$00	; 'e'
	dc.b	$30,$40,$f0,$40,$40,$40,$40,$00	; 'f'
	dc.b	$00,$00,$78,$88,$88,$78,$08,$70	; 'g'
	dc.b	$80,$80,$f0,$88,$88,$88,$88,$00	; 'h'
	dc.b	$20,$00,$60,$20,$20,$20,$70,$00	; 'i'
	dc.b	$10,$00,$30,$10,$10,$10,$90,$60	; 'j'
	dc.b	$80,$80,$90,$a0,$c0,$a0,$90,$00	; 'k'
	dc.b	$60,$20,$20,$20,$20,$20,$70,$00	; 'l'
	dc.b	$00,$00,$d0,$a8,$a8,$a8,$88,$00	; 'm'
	dc.b	$00,$00,$f0,$88,$88,$88,$88,$00	; 'n'
	dc.b	$00,$00,$70,$88,$88,$88,$70,$00	; 'o'
	dc.b	$00,$00,$f0,$88,$88,$f0,$80,$80	; 'p'
	dc.b	$00,$00,$78,$88,$88,$78,$08,$08	; 'q'
	dc.b	$00,$00,$b0,$c0,$80,$80,$80,$00	; 'r'
	dc.b	$00,$00,$78,$80,$70,$08,$f0,$00	; 's'
	dc.b	$40,$40,$f0,$40,$40,$40,$30,$00	; 't'
	dc.b	$00,$00,$88,$88,$88,$88,$78,$00	; 'u'
	dc.b	$00,$00,$88,$88,$88,$50,$20,$00	; 'v'
	dc.b	$00,$00,$88,$88,$a8,$a8,$50,$00	; 'w'
	dc.b	$00,$00,$88,$50,$20,$50,$88,$00	; 'x'
	dc.b	$00,$00,$88,$88,$88,$78,$08,$70	; 'y'
	dc.b	$00,$00,$f8,$10,$20,$40,$f8,$00	; 'z'
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00	; '{'
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00	; '|'
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00	; '}'
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00	; '~'
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00	; '\x7f'

	cnop	0,4
