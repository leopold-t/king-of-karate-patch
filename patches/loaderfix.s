;=====================================================================
; King of Karate - loader.exe additions
;  - clear the quit flag at start
;  - after each program: if Amiga+Q was pressed ($18c set), restore the
;    Workbench colours (the loader blacks them out) and quit
; Assembled with -DORG=<end of the loader code hunk>.
;=====================================================================
	org	ORG
QUITFLAG	equ	$18c
L_OPENINT	equ	$15e		; original first call
L_OPENWIN	equ	$126		; opens window, gets viewport
L_CLOSEWIN	equ	$14a
INTBASE		equ	$184
GFXBASE		equ	$1ae
DOSBASE		equ	$278
VPORT		equ	$146
NCOLS		equ	24

	bra.w	LStart		; +0  replaces bsr $15e at $0
	bra.w	LAfter		; +4  replaces moveq #0,d0 / rts at $88
	bra.w	LSaveCols	; +8  replaces bsr $126 at $d6

LStart:	clr.l	QUITFLAG.w
	clr.b	$193.w			; show the start-up screen again
	bra.w	L_OPENINT

LAfter:	tst.l	QUITFLAG.w
	bne.s	.q
	moveq	#0,d0
	rts
.q:	clr.l	QUITFLAG.w
	addq.l	#4,sp			; leave the endless TITLE/KARATE/HISCORE loop
	move.w	SavedOk(pc),d0
	beq.s	.nc
	move.l	GFXBASE(pc),a6
	move.l	VPORT(pc),a0
	lea	SavedCols(pc),a1
	moveq	#NCOLS,d0
	jsr	-192(a6)		; LoadRGB4
.nc:	move.l	4.w,a6
	move.l	INTBASE(pc),a1
	jsr	-414(a6)		; CloseLibrary
	move.l	GFXBASE(pc),a1
	jsr	-414(a6)
	move.l	DOSBASE(pc),a1
	jsr	-414(a6)
	moveq	#0,d0
	rts				; back to the CLI / script

LSaveCols:
	bsr.w	L_OPENWIN
	movem.l	d0-d3/a0-a3/a6,-(sp)
	move.l	VPORT(pc),d0
	beq.s	.x
	move.l	d0,a0
	move.l	4(a0),d0		; vp->ColorMap
	beq.s	.x
	move.l	d0,a2
	move.l	GFXBASE(pc),a6
	lea	SavedCols(pc),a3
	moveq	#0,d2
.c:	move.l	a2,a0
	move.l	d2,d0
	jsr	-582(a6)		; GetRGB4
	move.w	d0,(a3)+
	addq.w	#1,d2
	cmp.w	#NCOLS,d2
	bne.s	.c
	lea	SavedOk(pc),a0
	move.w	#1,(a0)
.x:	movem.l	(sp)+,d0-d3/a0-a3/a6
	rts

SavedOk:	dc.w	0
SavedCols:	ds.w	NCOLS
	cnop	0,4
