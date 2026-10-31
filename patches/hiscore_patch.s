;=====================================================================
; King of Karate - HISCORE patch
;   The high score screen showed an OpalVision picture (hscore.dat)
;   under the game's hires text. Here the picture (hscore.bg, EHB / HAM
;   / AGA, converted like the title) is shown natively; the game keeps
;   drawing its text into its own hires 4-plane bitmap (not displayed)
;   and every text update is converted to lores and laid over the
;   picture (left pixel of each hires pair wins, else the right one).
;   Text pens 0-15 = colours 0-15 (the game's copper gradient on
;   colour 1 is kept), planes 5+ are cleared under the text.
;   Appended to the HISCORE code hunk at ORG 10908, PC/A5 relative.
;=====================================================================
	org	10908

	ifnd	AGA
AGA		equ	0
	endc
	if	AGA
BGHDR		equ	128+512
HPL		equ	8		; display planes
	else
BGHDR		equ	128
HPL		equ	6
	endc
PW		equ	44		; bytes per plane row (352 pixels)
PROW		equ	HPL*PW
PROWS		equ	236
PSIZE		equ	PROWS*PROW
DISPOFF		equ	BGHDR+PSIZE	; displayed bitmap after the .bg file
COPOFF		equ	DISPOFF+PSIZE
BUFSIZE		equ	COPOFF+512	; (kokpatch.py allocates this much)

TROWB		equ	320		; game text bitmap: 4 planes x 80 bytes
TROWS		equ	200
OPALOFF		equ	20		; picture starts 20 lines above the text

O_BUF		equ	$293a		; chip buffer (alloc at $2920, file read at $2956)
O_TEXTBM	equ	$1ce		; operand of lea <text bitmap>,a0 (relocated)
O_COPLIST	equ	$1f4		; operand of move.l #<copper list>,COP1LC
GRADIDX		equ	37		; first entry of the gradient part of the list

	bra.w	HsInit		; +0  replaces move.w #$87f0,DMACON at $200
	bra.w	HsText		; +4  replaces move.l d0,$450(a5) / rts at $4de

; ------------------------------------------------------------------
HsInit:
	; the game switched sprite DMA on but never sets the sprite
	; pointers: random memory was shown as flickering blocks
	move.w	#$87d0,$dff096
	movem.l	d0-d2/a0-a1,-(sp)
	lea	HsOn(pc),a0
	clr.w	(a0)
	move.l	O_BUF(a5),d0
	beq.s	.x
	move.l	d0,a0
	cmp.l	#'KBG1',(a0)
	bne.s	.x
	lea	HsOn(pc),a1
	move.w	#1,(a1)			; picture loaded: switch on at first text
	; tables: hires byte -> 4 lores bits (even pixels / odd pixels)
	lea	TabE(pc),a0
	lea	TabO(pc),a1
	moveq	#0,d0
.t:	moveq	#0,d1
	moveq	#0,d2
	btst	#7,d0
	beq.s	.e7
	bset	#3,d1
.e7:	btst	#5,d0
	beq.s	.e5
	bset	#2,d1
.e5:	btst	#3,d0
	beq.s	.e3
	bset	#1,d1
.e3:	btst	#1,d0
	beq.s	.e1
	bset	#0,d1
.e1:	btst	#6,d0
	beq.s	.o6
	bset	#3,d2
.o6:	btst	#4,d0
	beq.s	.o4
	bset	#2,d2
.o4:	btst	#2,d0
	beq.s	.o2
	bset	#1,d2
.o2:	btst	#0,d0
	beq.s	.o0
	bset	#0,d2
.o0:	move.b	d1,(a0)+
	move.b	d2,(a1)+
	addq.w	#1,d0
	cmp.w	#256,d0
	bne.s	.t
.x:	movem.l	(sp)+,d0-d2/a0-a1
	rts

; ------------------------------------------------------------------
; HsText: end of the game's text routine ($4b2): d1 = text line (top),
;   32 lines high. Convert that band and show it.
HsText:
	move.l	d0,$450(a5)		; (replaced instruction)
	movem.l	d0-d7/a0-a6,-(sp)
	move.w	HsOn(pc),d2
	beq.s	.x
	lea	$dff000,a6
	tst.b	2(a6)			; let the game's blits finish
.wb:	btst	#14,2(a6)
	bne.s	.wb
	cmp.w	#1,d2
	bne.s	.on
	move.w	d1,-(sp)
	bsr	HsStart
	move.w	(sp)+,d1
.on:	move.w	d1,d0
	bpl.s	.y0
	moveq	#0,d0
.y0:	move.w	d0,d7
	add.w	#32,d7
	cmp.w	#TROWS,d7
	bls.s	.y1
	move.w	#TROWS,d7
.y1:	bsr	ConvRows
.x:	movem.l	(sp)+,d0-d7/a0-a6
	rts

; HsStart: copy the picture to the display bitmap, build our copper list
HsStart:
	lea	HsOn(pc),a0
	move.w	#2,(a0)
	move.l	O_BUF(a5),a2
	lea	BGHDR(a2),a0
	move.l	a2,a1
	add.l	#DISPOFF,a1
	move.l	#PSIZE/4-1,d0
.cp:	move.l	(a0)+,(a1)+
	subq.l	#1,d0
	bpl.s	.cp
	; first text line from the game's list (PAL: moved down by its code)
	move.l	O_COPLIST(a5),a3
	move.w	14(a3),d1		; DIWSTRT value
	lsr.w	#8,d1
	sub.w	#OPALOFF,d1		; d1 = line of picture row 0
	move.l	a2,a0
	add.l	#COPOFF,a0
	move.l	a0,a4
	; display window
	move.w	d1,d2
	cmp.w	#$2c,d2
	bge.s	.s
	move.w	#$2c,d2
.s:	lsl.w	#8,d2
	move.b	#$71,d2
	move.w	#$008e,(a0)+
	move.w	d2,(a0)+
	move.w	d1,d2
	add.w	#PROWS,d2
	cmp.w	#$12c,d2
	ble.s	.e
	move.w	#$12c,d2
.e:	lsl.w	#8,d2
	move.b	#$d1,d2
	move.w	#$0090,(a0)+
	move.w	d2,(a0)+
	move.l	#$00920030,(a0)+
	move.l	#$009400d8,(a0)+
	move.l	#$01080000+PROW-PW,(a0)+
	move.l	#$010a0000+PROW-PW,(a0)+
	move.l	#$01020000,(a0)+
	move.l	#$01040024,(a0)+
	; bitplane pointers (rows above line $2c are skipped)
	move.l	a2,d3
	add.l	#DISPOFF,d3
	move.w	d1,d2
	sub.w	#$2c,d2
	bge.s	.top
	neg.w	d2
	mulu	#PROW,d2
	add.l	d2,d3
.top:	move.w	#$e0,d0
	moveq	#HPL-1,d2
.bp:	move.w	d0,(a0)+
	swap	d3
	move.w	d3,(a0)+
	addq.w	#2,d0
	move.w	d0,(a0)+
	swap	d3
	move.w	d3,(a0)+
	addq.w	#2,d0
	add.l	#PW,d3
	dbf	d2,.bp
	if	AGA
	move.l	#$01fc0000,(a0)+	; FMODE 0
	move.l	#$01060c00,(a0)+	; BPLCON3
	move.l	#$010c0011,(a0)+	; BPLCON4
	move.l	#$01000210,(a0)+	; 8 planes
	else
	lea	12(a2),a1		; 32 colours
	move.w	#$180,d0
.col:	move.w	d0,(a0)+
	move.w	(a1)+,(a0)+
	addq.w	#2,d0
	cmp.w	#$1c0,d0
	bne.s	.col
	move.w	#$0100,(a0)+
	move.w	#$6200,d0
	tst.w	4(a2)
	beq.s	.ehb
	move.w	#$6a00,d0		; HAM
.ehb:	move.w	d0,(a0)+
	endif
	; continue with the game's colour 1 gradient
	lea	GRADIDX*4(a3),a1
	move.l	a1,d0
	move.w	#$0084,(a0)+
	swap	d0
	move.w	d0,(a0)+
	move.w	#$0086,(a0)+
	swap	d0
	move.w	d0,(a0)+
	move.l	#$008a0000,(a0)+
	move.l	#$fffffffe,(a0)+
	move.l	a4,$80(a6)		; COP1LC: from the next frame on
	if	AGA
	; the game's list may still run once (it sets colours 0-15):
	; set the palette when ours has taken over
.f1:	move.l	4(a6),d0		; wait for the next frame ...
	lsr.l	#8,d0
	and.w	#$1ff,d0
	cmp.w	#$20,d0
	bhs.s	.f1
.f2:	move.l	4(a6),d0		; ... past the top of the copper list
	lsr.l	#8,d0
	and.w	#$1ff,d0
	cmp.w	#$20,d0
	blo.s	.f2
	bsr	SetPalette
	endif
	rts

; ConvRows: text lines d0 .. d7-1 -> display bitmap
ConvRows:
	move.l	O_BUF(a5),a2
	lea	BufP(pc),a1
	move.l	a2,(a1)
	move.l	O_TEXTBM(a5),a0		; game text bitmap
	lea	TabE(pc),a3
	lea	TabO(pc),a4
.row:	cmp.w	d7,d0
	bhs	.done
	movem.w	d0/d7,-(sp)
	move.l	BufP(pc),a2
	move.w	d0,d1
	mulu	#TROWB,d1
	lea	(a0,d1.l),a1		; text row
	move.w	d0,d1
	add.w	#OPALOFF,d1
	mulu	#PROW,d1
	add.l	a2,d1
	move.l	d1,a5
	lea	BGHDR+2(a5),a5		; clean picture (column 2 = hpos $81)
	move.l	d1,a6
	add.l	#DISPOFF+2,a6		; display
	moveq	#40-1,d6		; hires words
.w:	movem.l	a5-a6,-(sp)
	move.w	(a1),d0
	or.w	80(a1),d0
	or.w	160(a1),d0
	or.w	240(a1),d0
	bne.s	.txt
	moveq	#HPL-1,d1		; no text: picture
.cl:	move.b	(a5),(a6)
	lea	PW(a5),a5
	lea	PW(a6),a6
	dbf	d1,.cl
	bra	.nx
.txt:	; left (even) and right (odd) pixels of the 4 planes:
	; d2 = L bytes, d3 = R bytes, plane 1 in the low byte
	moveq	#0,d2
	moveq	#0,d3
	moveq	#4-1,d1
	lea	240(a1),a2		; plane 4 first
.pl:	lsl.l	#8,d2
	lsl.l	#8,d3
	moveq	#0,d4
	move.b	(a2),d4
	move.b	(a3,d4.w),d5
	lsl.b	#4,d5
	move.b	(a4,d4.w),d4
	lsl.b	#4,d4
	move.b	d5,d2
	move.b	d4,d3
	moveq	#0,d4
	move.b	1(a2),d4
	move.b	(a3,d4.w),d5
	or.b	d5,d2
	move.b	(a4,d4.w),d5
	or.b	d5,d3
	lea	-80(a2),a2
	dbf	d1,.pl
	move.l	d2,d4			; d4.b = mL (OR of the L bytes)
	move.l	d4,d5
	swap	d5
	or.w	d5,d4
	move.w	d4,d5
	lsr.w	#8,d5
	or.b	d5,d4
	move.l	d3,d5			; d5.b = mR, then mask = mL | mR
	move.l	d5,d1
	swap	d1
	or.w	d1,d5
	move.w	d5,d1
	lsr.w	#8,d1
	or.b	d1,d5
	or.b	d4,d5
	; t = (L and mL) or (R and not mL): left pixel wins
	move.b	d4,d1
	lsl.w	#8,d1
	move.b	d4,d1
	move.w	d1,d0
	swap	d1
	move.w	d0,d1
	and.l	d1,d2
	not.l	d1
	and.l	d1,d3
	or.l	d3,d2
	not.b	d5			; d5 = not mask
	moveq	#4-1,d1
.p4:	move.b	(a5),d0
	and.b	d5,d0
	or.b	d2,d0
	move.b	d0,(a6)
	lsr.l	#8,d2
	lea	PW(a5),a5
	lea	PW(a6),a6
	dbf	d1,.p4
	moveq	#HPL-5,d1
.p5:	move.b	(a5),d0
	and.b	d5,d0
	move.b	d0,(a6)
	lea	PW(a5),a5
	lea	PW(a6),a6
	dbf	d1,.p5
.nx:	movem.l	(sp)+,a5-a6
	addq.l	#2,a1
	addq.l	#1,a5
	addq.l	#1,a6
	dbf	d6,.w
	movem.w	(sp)+,d0/d7
	addq.w	#1,d0
	bra	.row
.done:	rts

	if	AGA
; SetPalette: colours 0-127 from the .bg file (24 bit), 128-255 at half
;   brightness. a2 = .bg buffer, a6 = custom chips.
SetPalette:
	movem.l	d0-d7/a0-a1,-(sp)
	move.w	2(a6),-(sp)		; DMACONR
	move.w	#$0080,$96(a6)		; copper off meanwhile: its colour moves
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
	lea	$180(a6),a1
	add.w	d1,a1
	move.w	d0,$106(a6)
	move.w	d2,(a1)
	or.w	#$0200,d0
	move.w	d0,$106(a6)
	move.w	d3,(a1)
	addq.w	#1,d7
	cmp.w	#256,d7
	bne	.c
	move.w	#$0c00,$106(a6)
	move.w	(sp)+,d0
	and.w	#$0080,d0
	beq.s	.nc
	move.w	#$8080,$96(a6)		; copper on again
.nc:	movem.l	(sp)+,d0-d7/a0-a1
	rts
	endif

	cnop	0,4
BufP:	dc.l	0
HsOn:	dc.w	0			; 0 off, 1 picture loaded, 2 shown
TabE:	ds.b	256
TabO:	ds.b	256
	cnop	0,4
