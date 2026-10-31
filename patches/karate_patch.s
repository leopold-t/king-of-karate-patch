;=====================================================================
; King of Karate - OCS/ECS background patch for KARATE (fight program)
;
; Replaces OpalVision output with a native 6-bitplane background
; (EHB or HAM6), scrolled by the copper. Fighters are drawn into two
; full-width background copies (double buffered); old fighter areas
; are restored from a clean copy of the panorama.
;
; Assembled with vasm -Fbin at ORG = end of the original code hunk and
; appended to it by mkkarate.py. Only PC-relative / A5-relative
; addressing is used (A5 = start of the code hunk in the game).
;=====================================================================

	org	$4c00

; ---------------- original code addresses --------------------------
O_DOSBASE	equ	$588		; DOSBase (long)
O_ANIMBUF	equ	$47a		; animframes buffer pointer
O_STAGE5_1	equ	$4fb		; 5 stage chars patched by the game
O_LOADANIM	equ	$4b6		; load animframes.dat into ANIMBUF
O_STAGEPTR	equ	$366		; (already called earlier)
O_PREP1		equ	$1a7a		; shadow mask prep fighter 1
O_PREP2		equ	$1a8c		; shadow mask prep fighter 2
O_FRAMETAB	equ	$4420		; fighter frame table ($24 bytes/entry)
O_DBFLAG	equ	$130a		; double buffer flag (word)
O_CLEARED	equ	$17a0		; "something to restore" flag (word)
O_F1FRAME	equ	$17a2
O_F2FRAME	equ	$17a4
O_F1DIR		equ	$17a6
O_F2DIR		equ	$17a8
O_F1SHIFT	equ	$17ca
O_F2SHIFT	equ	$17cc
O_F1OFF		equ	$17ce
O_F2OFF		equ	$17d2
O_F1X		equ	$17d6
O_F1Y		equ	$17d8
O_F2X		equ	$17da
O_F2Y		equ	$17dc
O_ORDER		equ	$1892
O_SCROLL	equ	$1338		; long, 10..346
; relocated operands we read to find data-hunk addresses
R_SHBUF1	equ	$1a86		; lea $100000.l  -> shadow mask buffer 1
R_SHBUF2	equ	$1a98		; lea $100320.l  -> shadow mask buffer 2
R_LIST1		equ	$0ca4		; table entry: game copper list 1 ($101bb4)
R_LIST2		equ	$12f2		; lea $101e20.l  -> game copper list 2
O_PALDET	equ	$818		; returns d0 = $3c (NTSC) / $32 (PAL)

; ---------------- geometry ----------------------------------------
	ifnd	AGA
AGA		equ	0
	endc
BM_W		equ	864		; bitmap width (pixels)
PL		equ	108		; bytes per plane row
	if	AGA
; ---- AGA: 8 planes, 256 colours: 0-15 fighters, 16-127 background,
;      128-255 = 0-127 at half brightness (shadows set plane 8).
;      32 bit fetch (FMODE 1): bitplane pointers on 4 byte boundaries,
;      scrolling in steps of 32 pixels + 0..31 with BPLCON1.
PLANES		equ	8
BGHDR		equ	128+512		; header + 128 colours (24 bit)
FMODEV		equ	1
SCRG		equ	32		; pointer granularity (pixels)
DDFSTRTV	equ	$20
DDFSTOPV	equ	$d0
FETCHB		equ	48		; bytes fetched per plane and line
	else
PLANES		equ	6
BGHDR		equ	128
SCRG		equ	16
DDFSTRTV	equ	$28
DDFSTOPV	equ	$d8
FETCHB		equ	46
	endc
STRIDE		equ	PLANES*PL	; planes interleaved
LASTPL		equ	(PLANES-1)*PL	; shadow (half brite) plane
	if	AGA
SCRMARG		equ	$71-(DDFSTRTV*2+1)	; with 32 bit fetch the data comes 16
					; pixels earlier than with OCS fetch
SCRDMIN		equ	16		; delay 16..47: data covers DIW $71..$1d1
	else
SCRMARG		equ	$71-(DDFSTRTV*2+17)	; pixels fetched left of DIW $71
SCRDMIN		equ	0
	endc
ROWS		equ	236		; bitmap rows = whole background image
HUDIMGROW	equ	20		; image row behind the first HUD line (the
				; OpalVision image starts 20 lines above the
				; HUD: line $2c on PAL; NTSC keeps the same
				; relation). Fighter height differs per stage.
BMSIZE		equ	ROWS*STRIDE
SPARE		equ	40		; spare rows below the picture: fighters and
				; shadows near the bottom must never reach the
				; next allocation (the fighter frame caches)
BUFSIZE		equ	BMSIZE+SPARE*STRIDE
MASKMAX		equ	64		; max rows of the foreground stencil
PANOSIZE	equ	BGHDR+BMSIZE+MASKMAX*PL
; ---- HUD (energy bars, scores): hires 3-plane bitmap of the game,
;      converted to lores and drawn into the background ----
HROWS		equ	25		; rows of the game's HUD bitmap
HRN		equ	23		; rows converted / drawn (0..22)
HBPR		equ	240		; hires bytes per row (3 planes x 80)
HUDSAVSZ	equ	HROWS*HBPR
LBPL		equ	42		; lores bytes per plane row (20 words + pad)
LROW		equ	3*LBPL		; mask, pen bit 0, pen bit 1
HUDLOSZ		equ	HROWS*LROW
QUITFLAG	equ	$18c		; low memory: Amiga+Q -> loader quits
CACHESZ		equ	16384
OLDSTRIDE	equ	300
DSTRIDE		equ	STRIDE-OLDSTRIDE

; custom chip (standard offsets, used with A4 = $dff000)
BLTCON0	equ	$40
BLTCON1	equ	$42
BLTAFWM	equ	$44
BLTALWM	equ	$46
BLTCPT	equ	$48
BLTBPT	equ	$4c
BLTAPT	equ	$50
BLTDPT	equ	$54
BLTSIZE	equ	$58
BLTSIZV	equ	$5c
BLTSIZH	equ	$5e
BLTCMOD	equ	$60
BLTBMOD	equ	$62
BLTAMOD	equ	$64
BLTDMOD	equ	$66
BLTBDAT	equ	$72
BLTADAT	equ	$74
DMACONR	equ	$02
COP1LC	equ	$80
COPJMP1	equ	$88

	ifnd	EXP_NORESTORE
EXP_NORESTORE	equ	0
	endc
	ifnd	EXP_NOCLR56
EXP_NOCLR56	equ	0
	endc
	ifnd	EXP_NOFIGHT
EXP_NOFIGHT	equ	0
	endc

WAITBLIT macro
	tst.b	DMACONR(a4)		; Agnus sets BBUSY a cycle late: on fast
.wb\@:	btst	#14,DMACONR(a4)		; CPUs read once before testing it
	bne.s	.wb\@
	endm

; ---------------- entry table (offsets used by mkkarate.py) -------
	bra.w	NewAlloc	; +0   replaces $460
	bra.w	NewFree		; +4   replaces $47e
	bra.w	StageInit	; +8   replaces $1058
	bra.w	DoSwap		; +12  replaces $12e4
	bra.w	Restore		; +16  replaces $16aa
	bra.w	Draw		; +20  replaces $17f2
	bra.w	Shadows		; +24  replaces $1b88
	bra.w	GetMask		; +28  called from $1afe
	bra.w	P1Joy		; +32  replaces move.w JOY1DAT,d0 at $1394
	bra.w	P1Fire		; +36  replaces btst #7,$bfe001 at $13ec
	bra.w	WaitBlitA6	; +40  replaces the game's blitter waits ($1ab4, $1b22)
;=====================================================================
; variables (in the code hunk, A5-relative)
;=====================================================================
	cnop	0,4
V_FRAMES:	dc.l	0
V_TOD:		dc.l	0
V_PANO:		dc.l	0
V_BUFA:		dc.l	0
V_BUFB:		dc.l	0
V_CACHE1:	dc.l	0
V_CACHE2:	dc.l	0
V_COPMEM:	dc.l	0
V_MAIN:		dc.l	0
V_SECA:		dc.l	0
V_SECB:		dc.l	0
V_MAINCOP2:	dc.l	0
V_C1KEY:	dc.l	-1
V_C2KEY:	dc.l	-1
V_C1MASK:	dc.l	0
V_C2MASK:	dc.l	0
V_LTOP:		dc.w	0		; display line of bitmap row 0
V_R0:		dc.w	0		; bitmap row of fighter row 0
V_TOPA:		dc.l	0
V_TOPB:		dc.l	0
V_BOT:		dc.l	0
V_HUDBM:	dc.l	0		; game HUD bitmap (hires)
V_HUDSAV:	dc.l	0		; copy of it (change detection)
V_HUDLO:	dc.l	0		; lores HUD: mask, pen0, pen1
V_HUDROW:	dc.w	0		; bitmap row of HUD row 0
V_HUDVER:	dc.w	1
V_HUDBX_A:	dc.w	-1
V_HUDBX_B:	dc.w	-1
V_HUDV_A:	dc.w	0
V_HUDV_B:	dc.w	0
V_MASK:		dc.l	0		; foreground stencil (or 0)
V_MROW0:	dc.w	0
V_MROWS:	dc.w	0
V_AMIGA:	dc.w	0		; Amiga key held
V_KEYS:		dc.w	0		; fight keys held: bits 0-5 W S A D LShift LAlt,
					; bits 8-13 cursors up down left right, RShift RAlt
; ---- computer opponent ----
V_MODE:		dc.w	0		; 0 two players, 1 CPU = right, 2 CPU = left,
				; 3 CPU vs CPU (demo)
V_LEVEL:	dc.w	1		; 0 easy, 1 normal, 2 hard
V_CFG:		dc.l	0		; contents of karatedat:kok.cfg
V_AIJ1:		dc.w	0		; joystick value for player 1 (CPU)
V_AIF1:		dc.w	0		; fire for player 1 (1 = pressed)
V_AIST:		ds.w	2*3		; per fighter: output (move 0-15, -1 none),
				; loops to hold it, loops before next decision
V_RND:		dc.w	$1234
V_NIBH:		ds.b	512		; hires byte -> lores nibble << 4 (even, odd row)
V_NIBL:		ds.b	512		; hires byte -> lores nibble
V_RVALID_A:	dc.w	0
V_RVALID_B:	dc.w	0
V_REC_A:	ds.b	32		; old boxes of buffer A: F1,F2,S1,S2
V_REC_B:	ds.b	32
V_NB1:		ds.b	8		; new boxes this frame (row,colbyte,words,rows)
V_NB2:		ds.b	8
V_NS1:		ds.b	8
V_NS2:		ds.b	8
V_FIRST:	dc.w	0		; fighter drawn first (composited)
V_COMP2:	dc.w	0		; 1: second fighter composited too
V_NAME:		ds.b	32
	cnop	0,4

;=====================================================================
; Allocation
;=====================================================================
NewAlloc:
	movem.l	d1-d7/a0-a4/a6,-(sp)
	move.l	4.w,a6
	move.l	#$ba054,d0
	moveq	#1,d1			; MEMF_PUBLIC (fast if available)
	jsr	-198(a6)
	move.l	d0,O_ANIMBUF(a5)
	beq	.fail
	move.l	#PANOSIZE,d0
	bsr	ChipAlloc
	move.l	d0,V_PANO(a5)
	beq	.fail
	move.l	#BUFSIZE,d0
	bsr	ChipAlloc
	move.l	d0,V_BUFA(a5)
	beq	.fail
	move.l	#BUFSIZE,d0
	bsr	ChipAlloc
	move.l	d0,V_BUFB(a5)
	beq	.fail
	move.l	#CACHESZ*2+COPSIZE+HUDLOSZ+HUDSAVSZ,d0
	bsr	ChipAlloc
	move.l	d0,V_CACHE1(a5)
	beq	.fail
	add.l	#CACHESZ,d0
	move.l	d0,V_CACHE2(a5)
	add.l	#CACHESZ,d0
	move.l	d0,V_COPMEM(a5)
	add.l	#COPSIZE,d0
	move.l	d0,V_HUDLO(a5)
	add.l	#HUDLOSZ,d0
	move.l	d0,V_HUDSAV(a5)
	moveq	#-1,d0
	move.l	d0,V_C1KEY(a5)
	move.l	d0,V_C2KEY(a5)
	bsr	ClearRecs
	moveq	#1,d0
	bra.s	.out
.fail:	bsr	NewFree
	moveq	#0,d0
.out:	movem.l	(sp)+,d1-d7/a0-a4/a6
	tst.l	d0
	rts

; d0 = size -> d0 = chip memory (cleared) or 0
ChipAlloc:
	move.l	d1,-(sp)
	move.l	#$10003,d1		; CHIP|PUBLIC|CLEAR
	jsr	-198(a6)
	move.l	(sp)+,d1
	rts

NewFree:
	movem.l	d0-d1/a0-a1/a6,-(sp)
	move.l	4.w,a6
	move.l	O_ANIMBUF(a5),d0
	beq.s	.1
	move.l	d0,a1
	move.l	#$ba054,d0
	jsr	-210(a6)
	clr.l	O_ANIMBUF(a5)
.1:	move.l	V_PANO(a5),d0
	beq.s	.2
	move.l	d0,a1
	move.l	#PANOSIZE,d0
	jsr	-210(a6)
	clr.l	V_PANO(a5)
.2:	move.l	V_BUFA(a5),d0
	beq.s	.3
	move.l	d0,a1
	move.l	#BUFSIZE,d0
	jsr	-210(a6)
	clr.l	V_BUFA(a5)
.3:	move.l	V_BUFB(a5),d0
	beq.s	.4
	move.l	d0,a1
	move.l	#BUFSIZE,d0
	jsr	-210(a6)
	clr.l	V_BUFB(a5)
.4:	move.l	V_CACHE1(a5),d0
	beq.s	.5
	move.l	d0,a1
	move.l	#CACHESZ*2+COPSIZE+HUDLOSZ+HUDSAVSZ,d0
	jsr	-210(a6)
	clr.l	V_CACHE1(a5)
.5:	movem.l	(sp)+,d0-d1/a0-a1/a6
	rts

;=====================================================================
; StageInit - replaces $1058 (Opal upload of the backgrounds)
;=====================================================================
StageInit:
	movem.l	d0-d7/a0-a6,-(sp)
	lea	$dff000,a4
	; ---- re-enable system interrupts for DOS (as the game does) ----
	move.w	$128(a5),d0		; INTENAR saved by the game
	or.w	#$c000,d0
	move.w	#$7fff,$9c(a4)
	move.w	d0,$9a(a4)

	; ---- build file name "karatedat:xxxxx.bg" ----
	lea	V_NAME(a5),a0
	lea	BgPrefix(pc),a1
.p:	move.b	(a1)+,(a0)+
	bne.s	.p
	subq.l	#1,a0
	lea	O_STAGE5_1(a5),a1
	moveq	#5-1,d0
.c:	move.b	(a1)+,(a0)+
	dbf	d0,.c
	lea	BgSuffix(pc),a1
.s:	move.b	(a1)+,(a0)+
	bne.s	.s

	; ---- load background into V_PANO ----
	move.l	O_DOSBASE(a5),a6
	lea	V_NAME(a5),a0
	move.l	a0,d1
	move.l	#1005,d2
	jsr	-30(a6)			; Open
	move.l	d0,d7
	beq.s	.nobg
	move.l	d7,d1
	move.l	V_PANO(a5),d2
	move.l	#PANOSIZE,d3
	jsr	-42(a6)			; Read
	move.l	d7,d1
	jsr	-36(a6)			; Close
.nobg:
	; ---- game mode from karatedat:kok.cfg (written by the start script) ----
	clr.l	V_CFG(a5)
	lea	CfgName(pc),a0
	move.l	a0,d1
	move.l	#1005,d2
	jsr	-30(a6)			; Open
	move.l	d0,d7
	beq.s	.nocfg
	move.l	d7,d1
	lea	V_CFG(a5),a0
	move.l	a0,d2
	moveq	#4,d3
	jsr	-42(a6)			; Read
	move.l	d7,d1
	jsr	-36(a6)			; Close
.nocfg:	bsr	ParseCfg
	; ---- load animframes (remapped) - original routine ----
	bsr	CallLoadAnim

	; ---- system interrupts off again (like the original) ----
	move.w	#$7fff,$9a(a4)
	clr.w	V_KEYS(a5)

	; ---- copy panorama into both draw buffers ----
	move.l	V_PANO(a5),a0
	lea	BGHDR(a0),a0
	move.l	V_BUFA(a5),a1
	move.l	V_BUFB(a5),a2
	move.l	#BMSIZE/4-1,d0
.cp:	move.l	(a0)+,d1
	move.l	d1,(a1)+
	move.l	d1,(a2)+
	subq.l	#1,d0
	bpl.s	.cp

	; ---- display line of fighter row 0 (game adjusted it for PAL) ----
	; game copper list 1, DIWSTRT value of the fighter area = list1+$19e
	move.l	R_LIST1(pc),a0
	move.w	$19e(a0),d1		; fighter DIWSTRT (per stage, PAL adjusted)
	lsr.w	#8,d1
	; first DIWSTRT of the list = HUD line ($40 PAL / $2c NTSC)
.f8e:	cmp.w	#$008e,(a0)+
	beq.s	.h8e
	addq.l	#2,a0
	bra.s	.f8e
.h8e:	move.b	(a0),d0
	and.w	#$ff,d0
	sub.w	#HUDIMGROW,d0
	move.w	d0,V_LTOP(a5)		; display line of image row 0
	sub.w	d0,d1
	move.w	d1,V_R0(a5)		; image row of fighter row 0

	; ---- foreground stencil (France) ----
	move.l	V_PANO(a5),a0
	clr.l	V_MASK(a5)
	move.w	76(a0),V_MROW0(a5)
	move.w	78(a0),d0
	cmp.w	#MASKMAX,d0
	bls.s	.mok
	moveq	#0,d0
.mok:	move.w	d0,V_MROWS(a5)
	beq.s	.nomask
	lea	BGHDR(a0),a0
	add.l	#BMSIZE,a0
	move.l	a0,V_MASK(a5)
.nomask:
	bsr	HudInit
	bsr	BuildCopper
	if	AGA
	bsr	SetPalette
	endif
	bsr	ClearRecs
	moveq	#-1,d0
	move.l	d0,V_C1KEY(a5)
	move.l	d0,V_C2KEY(a5)
	; set scroll pointers for both buffers
	moveq	#0,d0
	bsr	SetScroll
	moveq	#1,d0
	bsr	SetScroll
	; start our copper
	move.l	V_MAIN(a5),COP1LC(a4)
	move.w	#0,COPJMP1(a4)
	movem.l	(sp)+,d0-d7/a0-a6
	rts

	if	AGA
;---------------------------------------------------------------------
; SetPalette (AGA): colours 0-127 from the .bg file (24 bit, $00RRGGBB
;   after the 128 byte header), 128-255 = the same at half brightness
;   (shadow plane). a4 = custom chips.
;---------------------------------------------------------------------
SetPalette:
	movem.l	d0-d7/a0-a1,-(sp)
	move.w	2(a4),-(sp)		; DMACONR
	move.w	#$0080,$96(a4)		; copper off meanwhile: its colour moves
					; would land in the bank being written
	move.l	V_PANO(a5),a0
	lea	128(a0),a0
	moveq	#0,d7			; colour number
.c:	move.w	d7,d0
	and.w	#127,d0
	lsl.w	#2,d0
	move.l	(a0,d0.w),d1		; $00RRGGBB
	cmp.w	#128,d7
	blo.s	.full
	lsr.l	#1,d1
	and.l	#$007f7f7f,d1
.full:	move.l	d1,d4
	swap	d4			; R
	move.w	d1,d5
	lsr.w	#8,d5			; G
	move.w	d1,d6			; B
	; high nibbles -> d2, low nibbles -> d3
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
	; bank = colour / 32 -> BPLCON3 bits 13-15
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
	move.w	d2,(a1)			; LOCT = 0: high nibbles (and low = high)
	or.w	#$0200,d0
	move.w	d0,$106(a4)
	move.w	d3,(a1)			; LOCT = 1: low nibbles
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

CallLoadAnim:
	; $4b6 re-enables ints itself and needs A6 = obfuscated custom base
	movem.l	d0-d7/a0-a6,-(sp)
	move.l	#$c37448df,a6
	add.l	#$3d6b4ca5,a6
	jsr	O_LOADANIM(pc)
	movem.l	(sp)+,d0-d7/a0-a6
	rts

CfgName:	dc.b	'karatedat:kok.cfg',0
BgPrefix:	dc.b	'karatedat:',0
BgSuffix:	dc.b	'.bg',0
	even

;---------------------------------------------------------------------
; Copper lists
;   MAIN : sprites off, COP2LC <- game list 1/2, jump
;   SECA / SECB: background + fighter area for buffer A / B
; the tails of the game lists (list+$190) are patched to jump to SEC.
;---------------------------------------------------------------------
COP_MAIN	equ	0
COP_TOPA	equ	128
COP_TOPB	equ	128+256
COP_BOT		equ	128+512
COP_NULLSPR	equ	128+512+64
COPSIZE		equ	128+512+64+16

BuildCopper:
	move.l	V_COPMEM(a5),a3
	lea	COP_MAIN(a3),a0
	move.l	a0,V_MAIN(a5)
	; DMACON: bitplane DMA on (display is controlled by BPLCON0)
	move.l	#$00968100,(a0)+
	move.l	#$01000200,(a0)+
	; sprite pointers -> null sprite
	lea	COP_NULLSPR(a3),a1
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
	; wait a few lines so the game's buffer swap (right after VBL)
	; is picked up in the same frame - like the original main list
	move.l	#$2001fffe,(a0)+
	; COP2LC (patched by Swap) + COPJMP2
	move.w	#$0084,(a0)+
	lea	V_MAINCOP2(a5),a1
	move.l	a0,(a1)			; address of the hi word value
	lea	COP_TOPA(a3),a1
	move.l	a1,d1
	swap	d1
	move.w	d1,(a0)+
	move.w	#$0086,(a0)+
	swap	d1
	move.w	d1,(a0)+
	move.l	#$008a0000,(a0)+
	move.l	#$fffffffe,(a0)+

	; ---- top sections (display setup, then the game's HUD list) ----
	lea	COP_TOPA(a3),a0
	move.l	a0,V_TOPA(a5)
	move.l	a0,V_SECA(a5)
	move.l	R_LIST1(pc),d2
	bsr	BuildTop
	lea	COP_TOPB(a3),a0
	move.l	a0,V_TOPB(a5)
	move.l	a0,V_SECB(a5)
	move.l	R_LIST2(pc),d2
	bsr	BuildTop
	; ---- bottom: restore pens 1-3 after the HUD gradients ----
	lea	COP_BOT(a3),a0
	move.l	a0,V_BOT(a5)
	move.l	V_PANO(a5),a2
	move.l	#$01820000,d0
	move.w	14(a2),d0
	move.l	d0,(a0)+
	move.l	#$01840000,d0
	move.w	16(a2),d0
	move.l	d0,(a0)+
	move.l	#$01860000,d0
	move.w	18(a2),d0
	move.l	d0,(a0)+
	move.l	#$fffffffe,(a0)+

	; ---- game lists: keep only WAITs and HUD gradients, tail -> BOT ----
	move.l	R_LIST1(pc),a0
	bsr.s	StripList
	move.l	R_LIST2(pc),a0
	bsr.s	StripList
	move.l	R_LIST1(pc),a0
	move.l	V_BOT(a5),d0
	bsr.s	PatchTail
	move.l	R_LIST2(pc),a0
	move.l	V_BOT(a5),d0
	bsr.s	PatchTail
	rts

; a0 = game copper list: every MOVE up to the tail except COLOR01-03
; becomes a no-op (register $1fe), so the list only recolours pens 1-3
; per line (the HUD gradients) on top of our 6-plane display.
StripList:
	movem.l	d0-d1/a0,-(sp)
	move.w	#$190/4-1,d1
.l:	move.w	(a0),d0
	btst	#0,d0
	bne.s	.n			; WAIT / SKIP
	cmp.w	#$182,d0
	beq.s	.n
	cmp.w	#$184,d0
	beq.s	.n
	cmp.w	#$186,d0
	beq.s	.n
	move.w	#$1fe,(a0)
.n:	addq.l	#4,a0
	dbf	d1,.l
	movem.l	(sp)+,d0-d1/a0
	rts

PatchTail:
	lea	$190(a0),a0
	move.w	#$0084,(a0)+
	swap	d0
	move.w	d0,(a0)+
	move.w	#$0086,(a0)+
	swap	d0
	move.w	d0,(a0)+
	move.l	#$008a0000,(a0)+
	rts

;---------------------------------------------------------------------
; BuildTop: a0 = section, d2 = game list to continue with
;   display window = image rows visible on screen (from line $2c),
;   bitplane pointers + scroll (SetScroll), 32 colours, BPLCON0
;---------------------------------------------------------------------
BuildTop:
	move.l	V_PANO(a5),a2		; header
	; first line S = max(L0, $2c), last line E = min(L0+ROWS, $12c)
	move.w	V_LTOP(a5),d1
	cmp.w	#$2c,d1
	bge.s	.s
	move.w	#$2c,d1
.s:	move.w	#$008e,(a0)+		; +0  DIWSTRT
	move.w	d1,d0
	lsl.w	#8,d0
	move.b	#$71,d0
	cmp.w	#1,4(a2)		; mode: HAM -> hide left fringe
	bne.s	.ehb
	move.b	#$7d,d0
.ehb:	move.w	d0,(a0)+
	move.w	#$0090,(a0)+		; +4  DIWSTOP
	move.w	V_LTOP(a5),d0
	add.w	#ROWS,d0
	cmp.w	#$12c,d0
	ble.s	.e
	move.w	#$12c,d0
.e:	lsl.w	#8,d0
	move.b	#$d1,d0
	move.w	d0,(a0)+
	move.l	#$00920000+DDFSTRTV,(a0)+	; +8  DDFSTRT
	move.l	#$00940000+DDFSTOPV,(a0)+	; +12 DDFSTOP
	move.w	#$0108,(a0)+		; +16
	move.w	#STRIDE-FETCHB,(a0)+
	move.w	#$010a,(a0)+		; +20
	move.w	#STRIDE-FETCHB,(a0)+
	move.l	#$01040024,(a0)+	; +24 BPLCON2
	move.l	#$01020000,(a0)+	; +28 BPLCON1 (scroll)
	move.w	#$e0,d0			; +32 BPLxPT
.bp:	move.w	d0,(a0)+
	clr.w	(a0)+
	addq.w	#2,d0
	cmp.w	#$e0+4*PLANES,d0
	bne.s	.bp
	if	AGA
	move.l	#$01fc0000+FMODEV,(a0)+	; FMODE: 32 bit bitplane fetch
	move.l	#$01060c00,(a0)+	; BPLCON3: bank 0, LOCT off
	move.l	#$010c0011,(a0)+	; BPLCON4: no colour XOR
	move.l	#$01000210,(a0)+	; BPLCON0: 8 planes, colour
	; the 256 colours are set once by the CPU (SetPalette)
	else
	lea	12(a2),a1		; colours from the .bg header
	move.w	#$180,d0
.col:	move.w	d0,(a0)+
	move.w	(a1)+,(a0)+
	addq.w	#2,d0
	cmp.w	#$1c0,d0
	bne.s	.col
	move.w	#$0100,(a0)+		; BPLCON0: 6 planes, colour, HAM?
	move.w	#$6200,d0
	cmp.w	#1,4(a2)
	bne.s	.n
	or.w	#$0800,d0
.n:	move.w	d0,(a0)+
	endif
	move.w	#$0084,(a0)+		; COP2LC = game list, COPJMP2
	swap	d2
	move.w	d2,(a0)+
	move.w	#$0086,(a0)+
	swap	d2
	move.w	d2,(a0)+
	move.l	#$008a0000,(a0)+
	rts

SEC_BPLCON1	equ	30		; value word of the BPLCON1 move
SEC_BPLPT	equ	32		; first BPLxPT move

;---------------------------------------------------------------------
; SetScroll(d0 = 0 buffer A, 1 buffer B) - from O_SCROLL
;---------------------------------------------------------------------
SetScroll:
	movem.l	d0-d4/a0-a1,-(sp)
	move.l	V_SECA(a5),a0
	move.l	V_BUFA(a5),d3
	tst.w	d0
	beq.s	.a
	move.l	V_SECB(a5),a0
	move.l	V_BUFB(a5),d3
.a:	move.l	O_SCROLL(a5),d1		; pano x of screen left
	add.w	#80-SCRMARG+SCRDMIN,d1	; bitmap x of the first fetched pixel
					; at the smallest delay (screen left =
					; DIW $71; margin 80)
	; P = that pixel rounded up to SCRG, delay d = P - x + SCRDMIN
	move.w	d1,d2
	add.w	#SCRG-1,d1
	and.w	#-SCRG,d1
	neg.w	d2
	add.w	d1,d2
	add.w	#SCRDMIN,d2		; d2 = delay
	lsr.w	#3,d1			; byte offset
	ext.l	d1
	add.l	d1,d3			; first plane pointer
	move.w	V_LTOP(a5),d1		; skip image rows above line $2c
	sub.w	#$2c,d1
	bge.s	.top
	neg.w	d1
	mulu	#STRIDE,d1
	add.l	d1,d3
.top:
	; BPLCON1: delay bits 0-3 (PF1) / 4-7 (PF2); AGA: 16/32 in 10/14
	move.w	d2,d4
	and.w	#15,d4
	move.w	d4,d1
	lsl.w	#4,d1
	or.w	d1,d4
	if	AGA
	btst	#4,d2
	beq.s	.b4
	or.w	#$4400,d4		; +16
.b4:	btst	#5,d2
	beq.s	.b5
	or.w	#$8800,d4		; +32
.b5:
	endif
	move.w	d4,SEC_BPLCON1(a0)
	lea	SEC_BPLPT+2(a0),a1
	moveq	#PLANES-1,d0
.pl:	swap	d3
	move.w	d3,(a1)
	swap	d3
	move.w	d3,4(a1)
	addq.l	#8,a1
	add.l	#PL,d3
	dbf	d0,.pl
	movem.l	(sp)+,d0-d4/a0-a1
	rts

;=====================================================================
; Swap - replaces $12e4 (double buffer toggle)
;=====================================================================
DoSwap:
	addq.l	#1,V_FRAMES(a5)
	moveq	#0,d0
	move.b	$bfea01,d0
	lsl.l	#8,d0
	move.b	$bfe901,d0
	lsl.l	#8,d0
	move.b	$bfe801,d0
	move.l	d0,V_TOD(a5)
	bsr	PollKeys
	bsr	AiTick
	; ---- the last blits of the frame (planes 5/6 under the fighters,
	; HUD) may still be running: finish them before the buffer is shown
	move.l	a4,-(sp)
	lea	$dff000,a4
	WAITBLIT
	move.l	(sp)+,a4
	move.l	V_TOPA(a5),d0
	not.w	O_DBFLAG(a5)
	beq.s	.1
	move.l	V_TOPB(a5),d0
.1:	move.l	V_MAINCOP2(a5),a0
	swap	d0
	move.w	d0,(a0)
	swap	d0
	move.w	d0,4(a0)
	; ---- the copper picks the new buffer up at line $20. If the beam is
	; already past it, the buffer we are about to draw into is still on
	; screen for this frame: wait until the new one is displayed.
	bsr.s	BeamLine
	cmp.w	#$20,d0
	blo.s	.ok
.w1:	bsr.s	BeamLine		; next frame ...
	cmp.w	#$20,d0
	bhs.s	.w1
.w2:	bsr.s	BeamLine		; ... past the first displayed line
	cmp.w	#$2c,d0
	blo.s	.w2
.ok:	rts

; the game's own wait (shadow mask preparation): A6 = custom - $5a7c
WaitBlitA6:
	tst.b	$5a7e(a6)		; DMACONR: read once first (BBUSY is late)
.w:	btst	#14-8,$5a7e(a6)
	bne.s	.w
	rts

BeamLine:	; d0 = current raster line (0..312)
	move.l	$dff004,d0
	lsr.l	#8,d0
	and.w	#$1ff,d0
	rts

;---------------------------------------------------------------------
; current draw buffer:  O_DBFLAG == 0 -> B   else A
; out: a0 = bitmap, a1 = rect record, d0 = 0 (A) / 1 (B)
;---------------------------------------------------------------------
DrawBuf:
	tst.w	O_DBFLAG(a5)
	beq.s	.b
	move.l	V_BUFA(a5),a0
	lea	V_REC_A(a5),a1
	moveq	#0,d0
	rts
.b:	move.l	V_BUFB(a5),a0
	lea	V_REC_B(a5),a1
	moveq	#1,d0
	rts

BufPtr:	tst.w	O_DBFLAG(a5)
	beq.s	.b
	move.l	V_BUFA(a5),a0
	rts
.b:	move.l	V_BUFB(a5),a0
	rts


ClearRecs:
	movem.l	d0/a0,-(sp)
	lea	V_REC_A(a5),a0
	moveq	#64/4-1,d0
.c:	clr.l	(a0)+
	dbf	d0,.c
	movem.l	(sp)+,d0/a0
	rts

;=====================================================================
; Restore hook - replaces $16aa. The real restore happens in Shadows
; (positions of this frame are known there). Here: like the original,
; clear the shadow mask buffers.
;=====================================================================
Restore:
	movem.l	a4,-(sp)
	lea	$dff000,a4
	WAITBLIT
	move.l	#$01000000,BLTCON0(a4)	; D only, minterm 0
	move.w	#0,BLTDMOD(a4)
	move.l	R_SHBUF1(pc),BLTDPT(a4)
	move.w	#$080b,BLTSIZE(a4)
	WAITBLIT
	move.l	R_SHBUF2(pc),BLTDPT(a4)
	move.w	#$080b,BLTSIZE(a4)
	move.w	#1,O_CLEARED(a5)
	movem.l	(sp)+,a4
	rts

;---------------------------------------------------------------------
; BlitRestore: d0 row, d1 colbyte, d2 words, d3 rows, d4 mode (0 full, 1 plane 6)
;   a2 = dest bitmap, a3 = pano bitmap, a4 = custom
;---------------------------------------------------------------------
BlitRestore:
	movem.l	d0-d6/a0,-(sp)
	tst.w	d2
	ble.s	.x
	tst.w	d3
	ble.s	.x
	mulu	#STRIDE,d0
	ext.l	d1
	add.l	d1,d0			; offset
	tst.w	d4
	bne.s	.p6
	move.w	d3,d5
	mulu	#PLANES,d5		; rows of all planes
	move.w	#PL,d6
	bra.s	.go
.p6:	add.l	#LASTPL,d0
	move.w	d3,d5
	move.w	#STRIDE,d6
.go:	sub.w	d2,d6
	sub.w	d2,d6
	if	AGA=0
	lsl.w	#6,d5
	or.w	d2,d5
	endif
	WAITBLIT
	move.l	#$ffffffff,BLTAFWM(a4)
	move.l	#$09f00000,BLTCON0(a4)	; A->D copy
	move.w	d6,BLTAMOD(a4)
	move.w	d6,BLTDMOD(a4)
	lea	(a3,d0.l),a0
	move.l	a0,BLTAPT(a4)
	lea	(a2,d0.l),a0
	move.l	a0,BLTDPT(a4)
	if	AGA
	move.w	d5,BLTSIZV(a4)		; ECS/AGA big blit (more than 1024 rows)
	move.w	d2,BLTSIZH(a4)
	else
	move.w	d5,BLTSIZE(a4)
	endif
.x:	movem.l	(sp)+,d0-d6/a0
	rts

;---------------------------------------------------------------------
; RestoreDiff: a0 = old box O, a1 = new box N (composited, may be h=0)
;   full restore for O - N, plane-6 restore for O & N
;---------------------------------------------------------------------
RestoreDiff:
	movem.l	d0-d7/a0-a1,-(sp)
	tst.w	6(a0)
	beq	.x
	tst.w	6(a1)
	bne.s	.diff
	; no N: full restore of O
	movem.w	(a0),d0-d3
	moveq	#0,d4
	bsr	BlitRestore
	bra	.x
.diff:	; d5 = oR+oH, d6 = nR+nH
	move.w	(a0),d5
	add.w	6(a0),d5
	move.w	(a1),d6
	add.w	6(a1),d6
	; ---- top strip: rows [oR, min(oR+oH, nR)) ----
	move.w	(a0),d0
	move.w	(a1),d3
	cmp.w	d5,d3
	ble.s	.t1
	move.w	d5,d3
.t1:	sub.w	d0,d3			; rows
	move.w	2(a0),d1
	move.w	4(a0),d2
	moveq	#0,d4
	bsr	BlitRestore		; (ignored if rows <= 0)
	; ---- bottom strip: rows [max(oR, nR+nH), oR+oH) ----
	move.w	(a0),d0
	cmp.w	d6,d0
	bge.s	.b1
	move.w	d6,d0
.b1:	move.w	d5,d3
	sub.w	d0,d3
	move.w	2(a0),d1
	move.w	4(a0),d2
	moveq	#0,d4
	bsr	BlitRestore
	; ---- middle rows [m0, m1) ----
	move.w	(a0),d0			; m0 = max(oR, nR)
	cmp.w	(a1),d0
	bge.s	.m0
	move.w	(a1),d0
.m0:	move.w	d5,d3			; m1 = min(oR+oH, nR+nH)
	cmp.w	d6,d3
	ble.s	.m1
	move.w	d6,d3
.m1:	sub.w	d0,d3			; rows of middle part
	ble	.x
	; columns in bytes: oC, oE = oC+2*oW, nC, nE
	move.w	2(a0),d5		; oC
	move.w	4(a0),d7
	add.w	d7,d7
	add.w	d5,d7			; oE
	move.w	2(a1),d6		; nC
	move.w	4(a1),d2
	add.w	d2,d2
	add.w	d6,d2			; nE
	move.w	d2,-(sp)		; save nE
	; left: [oC, min(oE, nC))
	move.w	d5,d1
	move.w	d6,d2
	cmp.w	d7,d2
	ble.s	.l1
	move.w	d7,d2
.l1:	sub.w	d1,d2
	asr.w	#1,d2
	moveq	#0,d4
	bsr	BlitRestore
	; right: [max(oC, nE), oE)
	move.w	(sp),d1			; nE
	cmp.w	d5,d1
	bge.s	.r1
	move.w	d5,d1
.r1:	move.w	d7,d2
	sub.w	d1,d2
	asr.w	#1,d2
	moveq	#0,d4
	bsr	BlitRestore
	; intersection: [max(oC,nC), min(oE,nE)) -> plane 6 only
	move.w	d5,d1
	cmp.w	d6,d1
	bge.s	.i1
	move.w	d6,d1
.i1:	move.w	(sp)+,d2		; nE
	cmp.w	d7,d2
	ble.s	.i2
	move.w	d7,d2
.i2:	sub.w	d1,d2
	asr.w	#1,d2
	moveq	#1,d4
	bsr	BlitRestore
.x:	movem.l	(sp)+,d0-d7/a0-a1
	rts

; BoxesOverlap: a0, a1 boxes -> Z clear (ne) if they overlap
BoxesOverlap:
	movem.l	d0-d3,-(sp)
	; rows: a.r < b.r+b.h && b.r < a.r+a.h
	move.w	(a1),d0
	add.w	6(a1),d0
	cmp.w	(a0),d0
	ble.s	.no
	move.w	(a0),d0
	add.w	6(a0),d0
	cmp.w	(a1),d0
	ble.s	.no
	; cols (bytes)
	move.w	4(a1),d1
	add.w	d1,d1
	add.w	2(a1),d1
	cmp.w	2(a0),d1
	ble.s	.no
	move.w	4(a0),d1
	add.w	d1,d1
	add.w	2(a0),d1
	cmp.w	2(a1),d1
	ble.s	.no
	moveq	#1,d0			; overlap -> ne
	bra.s	.x
.no:	moveq	#0,d0			; eq
.x:	movem.l	(sp)+,d0-d3
	rts

; MakeBox: d1 = offset (bytes), d2 = words, d3 = rows, a0 = box
MakeBox:
	movem.l	d1,-(sp)
	divu	#STRIDE,d1
	move.w	d1,(a0)			; row
	swap	d1
	move.w	d1,2(a0)		; colbyte
	move.w	d2,4(a0)
	move.w	d3,6(a0)
	movem.l	(sp)+,d1
	rts

;=====================================================================
; Frame cache: copy current frame (data + mask) of fighter n to chip
;   d0 = 0 / 1 (fighter)
;=====================================================================
EnsureCache:
	movem.l	d0-d7/a0-a4,-(sp)
	lea	$dff000,a4
	tst.w	d0
	bne.s	.f2
	move.w	O_F1FRAME(a5),d1
	move.w	O_F1DIR(a5),d2
	lea	V_C1KEY(a5),a3
	move.l	V_CACHE1(a5),a2
	bra.s	.go
.f2:	move.w	O_F2FRAME(a5),d1
	move.w	O_F2DIR(a5),d2
	lea	V_C2KEY(a5),a3
	move.l	V_CACHE2(a5),a2
.go:	move.w	d1,d3
	swap	d3
	move.w	d2,d3			; key = frame<<16 | dir
	cmp.l	(a3),d3
	beq	.done
	move.l	d3,(a3)
	; entry
	lea	O_FRAMETAB(a5),a0
	mulu	#$24,d1
	add.l	d1,a0			; a0 = entry
	moveq	#0,d4
	move.w	(a0),d4
	lsr.w	#6,d4			; rows
	moveq	#0,d5
	move.w	6(a0),d5		; plane stride (bytes)
	add.w	d2,a0			; direction
	move.l	O_ANIMBUF(a5),a1
	move.l	a1,d6
	add.l	8(a0),a1		; data
	add.l	12(a0),d6		; mask
	WAITBLIT			; cache may still be in use
	; data: rows*stride*4 + 2
	move.l	d4,d0
	mulu	d5,d0
	lsl.l	#2,d0
	addq.l	#2+3,d0
	lsr.l	#2,d0
	move.l	a2,a3
.cd:	move.l	(a1)+,(a3)+
	subq.l	#1,d0
	bne.s	.cd
	; fighter 2: gi colours 8..11 -> 12..15  (plane 3 |= plane 4)
	movem.l	(sp),d0			; fighter number (saved d0)
	tst.w	d0
	beq.s	.nor
	move.l	a2,a0			; row start
	move.w	d4,d1
	subq.w	#1,d1
.orr:	move.w	d5,d0
	lsr.w	#1,d0
	subq.w	#1,d0
	lea	(a0,d5.l),a1		; plane 2
	add.l	d5,a1			; plane 3
.orw:	move.w	(a1,d5.l),d2		; plane 4
	or.w	d2,(a1)+
	dbf	d0,.orw
	add.l	d5,a0
	add.l	d5,a0
	add.l	d5,a0
	add.l	d5,a0
	dbf	d1,.orr
.nor:
	; mask after data (keep it 4-aligned)
	move.l	a3,a0
	sub.l	a2,a0			; mask offset in cache
	move.l	a0,-(sp)
	move.l	d6,a1
	move.l	d4,d0
	mulu	d5,d0
	addq.l	#2+3,d0
	lsr.l	#2,d0
.cm:	move.l	(a1)+,(a3)+
	subq.l	#1,d0
	bne.s	.cm
	move.l	(sp)+,d0
	; store mask pointer next to the key
	movem.l	(sp),d1			; d1 = fighter (saved d0)
	tst.w	d1
	bne.s	.m2
	add.l	V_CACHE1(a5),d0
	move.l	d0,V_C1MASK(a5)
	bra.s	.done
.m2:	add.l	V_CACHE2(a5),d0
	move.l	d0,V_C2MASK(a5)
.done:	movem.l	(sp)+,d0-d7/a0-a4
	rts

;---------------------------------------------------------------------
; GetMask - called from the shadow mask prep ($1afe) instead of
;   movea.l ($c,a3),a0 / adda.l $47a.l,a0.   a1 = shadow buffer.
;---------------------------------------------------------------------
GetMask:
	move.l	V_C1MASK(a5),a0
	cmp.l	R_SHBUF1(pc),a1
	beq.s	.1
	move.l	V_C2MASK(a5),a0
.1:	rts

;=====================================================================
; Pos: d0 = x, d1 = y (game coordinates)
;   -> d1 = byte offset (word aligned) in bitmap, d0 = shift << 12
;=====================================================================
Pos:
	add.w	O_SCROLL+2(a5),d0	; bitmap x = x + scroll (margin 80)
	add.w	V_R0(a5),d1
	mulu	#STRIDE,d1
	move.w	d0,-(sp)
	lsr.w	#4,d0
	add.w	d0,d0
	ext.l	d0
	add.l	d0,d1
	move.w	(sp)+,d0
	and.w	#15,d0
	ror.w	#4,d0
	rts


;=====================================================================
; Shadows - replaces $1b88:
;   caches, shadow masks, positions, draw order, restore, shadow blits
;=====================================================================
Shadows:
	movem.l	d0-d7/a0-a4,-(sp)
	bsr	PollKeys
	moveq	#0,d0
	bsr	EnsureCache
	moveq	#1,d0
	bsr	EnsureCache
	movem.l	(sp),d0-d7/a0-a4	; game regs for the prep routines
	jsr	O_PREP1(pc)
	jsr	O_PREP2(pc)
	lea	$dff000,a4
	; ---- positions + boxes ----
	moveq	#0,d7
	bsr	FighterPos
	moveq	#1,d7
	bsr	FighterPos
	; ---- draw order (moved here from Draw, same rules as $17f2) ----
	move.w	O_F2X(a5),d0
	sub.w	O_F1X(a5),d0
	bpl.s	.ab
	neg.w	d0
.ab:	cmp.w	#$91,d0
	bcs.s	.keep
	cmp.w	#$19,O_F1FRAME(a5)
	beq.s	.keep
	cmp.w	#$19,O_F2FRAME(a5)
	beq.s	.keep
	cmp.w	#$30,O_F1FRAME(a5)
	beq.s	.keep
	cmp.w	#$30,O_F2FRAME(a5)
	beq.s	.keep
	not.w	O_ORDER(a5)
.keep:	moveq	#1,d0			; order 0: fighter 2 first
	tst.w	O_ORDER(a5)
	beq.s	.of
	moveq	#0,d0
.of:	move.w	d0,V_FIRST(a5)
	; ---- can both fighters be composited? (new boxes disjoint) ----
	lea	V_NB1(a5),a0
	lea	V_NB2(a5),a1
	bsr	BoxesOverlap
	seq	d0
	and.w	#1,d0
	move.w	d0,V_COMP2(a5)
	; ---- restore old boxes of this buffer ----
	bsr	DrawBuf			; a0 bitmap, a1 record
	move.l	a0,a2
	move.l	a1,-(sp)
	move.l	V_PANO(a5),a3
	lea	BGHDR(a3),a3
	; fighter 1 old box
	lea	V_NB1(a5),a1
	tst.w	V_COMP2(a5)
	bne.s	.u1
	tst.w	V_FIRST(a5)
	beq.s	.u1
	lea	V_NB2(a5),a1
.u1:	move.l	(sp),a0
	bsr	RestoreDiff
	; fighter 2 old box
	lea	V_NB2(a5),a1
	tst.w	V_COMP2(a5)
	bne.s	.u2
	tst.w	V_FIRST(a5)
	bne.s	.u2
	lea	V_NB1(a5),a1
.u2:	lea	8(a0),a0
	bsr	RestoreDiff
	; old shadows: plane 6
	moveq	#2-1,d5
	move.l	(sp),a0
	lea	16(a0),a0
.os:	tst.w	6(a0)
	beq.s	.os2
	movem.w	(a0),d0-d3
	moveq	#1,d4
	bsr	BlitRestore
.os2:	addq.l	#8,a0
	dbf	d5,.os
	; ---- shadows (EHB only) ----
	move.l	V_PANO(a5),a0
	cmp.w	#1,4(a0)		; HAM: no shadows
	beq.s	.noshadow
	lea	V_NS1(a5),a0
	move.l	R_SHBUF1(pc),a1
	move.w	O_F1SHIFT(a5),d0
	bsr	ShadowBlit
	lea	V_NS2(a5),a0
	move.l	R_SHBUF2(pc),a1
	move.w	O_F2SHIFT(a5),d0
	bsr	ShadowBlit
	bra.s	.rec
.noshadow:
	clr.w	V_NS1+6(a5)
	clr.w	V_NS2+6(a5)
.rec:	; ---- remember the new boxes for this buffer ----
	move.l	(sp)+,a1
	lea	V_NB1(a5),a0
	moveq	#32/4-1,d0
.cr:	move.l	(a0)+,(a1)+
	dbf	d0,.cr
	movem.l	(sp)+,d0-d7/a0-a4
	rts

; d7 = fighter: computes shift/offset (game vars) and V_NBx / V_NSx
FighterPos:
	lea	O_FRAMETAB(a5),a1
	tst.w	d7
	bne.s	.f2
	move.w	O_F1FRAME(a5),d0
	mulu	#$24,d0
	add.l	d0,a1
	move.l	$20(a1),d5		; shadow row offset (old stride 300)
	move.w	(a1),d6			; bltsize
	move.w	O_F1DIR(a5),d0
	add.w	d0,a1
	move.w	d0,d1
	moveq	#0,d0
	tst.w	d1
	beq.s	.d1
	moveq	#-$12,d0
.d1:	add.w	O_F1X(a5),d0
	move.w	O_F1Y(a5),d1
	add.w	$10(a1),d0
	add.w	$12(a1),d1
	bsr	Pos
	move.w	d0,O_F1SHIFT(a5)
	move.l	d1,O_F1OFF(a5)
	lea	V_NB1(a5),a0
	lea	V_NS1(a5),a2
	bra.s	.box
.f2:	move.w	O_F2FRAME(a5),d0
	mulu	#$24,d0
	add.l	d0,a1
	move.l	$20(a1),d5
	move.w	(a1),d6
	move.w	O_F2DIR(a5),d0
	add.w	d0,a1
	move.w	d0,d1
	moveq	#0,d0
	tst.w	d1
	beq.s	.d2
	moveq	#-$12,d0
.d2:	add.w	O_F2X(a5),d0
	move.w	O_F2Y(a5),d1
	add.w	$10(a1),d0
	add.w	$12(a1),d1
	bsr	Pos
	move.w	d0,O_F2SHIFT(a5)
	move.l	d1,O_F2OFF(a5)
	lea	V_NB2(a5),a0
	lea	V_NS2(a5),a2
.box:	; fighter box
	moveq	#63,d2
	and.w	d6,d2
	move.w	d6,d3
	lsr.w	#6,d3
	bsr	MakeBox
	; shadow box: offset + rows(d5)*STRIDE, 12 words x 32 rows,
	; clipped to the bottom of the picture
	divu	#OLDSTRIDE,d5
	mulu	#STRIDE,d5
	add.l	d5,d1
	move.l	a2,a0
	moveq	#12,d2
	moveq	#32,d3
	bsr	MakeBox
	move.w	#ROWS,d3
	sub.w	(a0),d3			; rows left below the shadow's top
	bgt.s	.sc
	moveq	#0,d3
.sc:	cmp.w	6(a0),d3
	bge.s	.sx
	move.w	d3,6(a0)
.sx:	rts

; a0 = shadow box, a1 = shadow mask buffer, d0 = shift, a2 = dest bitmap
ShadowBlit:
	move.w	6(a0),d3		; rows (clipped)
	ble.s	.x
	lsl.w	#6,d3
	or.w	#12,d3
	movem.w	(a0),d1-d2		; row, colbyte
	mulu	#STRIDE,d1
	ext.l	d2
	add.l	d2,d1
	lea	(a2,d1.l),a0
	lea	LASTPL(a0),a0		; last plane -> half brite
	WAITBLIT
	move.l	#$ffff0000,BLTAFWM(a4)
	move.l	a1,BLTAPT(a4)
	move.l	a0,BLTCPT(a4)
	move.l	a0,BLTDPT(a4)
	move.w	#-2,BLTAMOD(a4)
	move.w	#STRIDE-24,BLTCMOD(a4)
	move.w	#STRIDE-24,BLTDMOD(a4)
	move.w	#0,BLTCON1(a4)
	or.w	#$0bfa,d0		; A|C
	move.w	d0,BLTCON0(a4)
	move.w	d3,BLTSIZE(a4)
.x:	rts

;=====================================================================
; Draw - replaces $17f2. First fighter is composited onto the clean
; panorama (planes 1-5), the second one is cookie-cut normally.
;=====================================================================
Draw:
	movem.l	d0-d7/a0-a4,-(sp)
	bsr	PollKeys
	lea	$dff000,a4
	move.w	V_FIRST(a5),d7
	moveq	#1,d6			; composite
	bsr.s	DrawFighter
	move.w	V_FIRST(a5),d7
	eor.w	#1,d7
	move.w	V_COMP2(a5),d6
	bsr.s	DrawFighter
	bsr	Foreground
	bsr	HudUpdate
	bsr	HudDraw
	bsr	DrawBuf
	bsr	SetScroll
	movem.l	(sp)+,d0-d7/a0-a4
	rts

; d7 = fighter (0/1), d6 = 1: composite onto panorama
DrawFighter:
	if	EXP_NOFIGHT
	rts
	endif
	move.w	d6,-(sp)
	lea	O_FRAMETAB(a5),a1
	tst.w	d7
	bne.s	.f2
	move.w	O_F1FRAME(a5),d0
	move.w	O_F1SHIFT(a5),d6
	move.l	O_F1OFF(a5),d4
	move.l	V_CACHE1(a5),a2
	move.l	V_C1MASK(a5),a3
	bra.s	.go
.f2:	move.w	O_F2FRAME(a5),d0
	move.w	O_F2SHIFT(a5),d6
	move.l	O_F2OFF(a5),d4
	move.l	V_CACHE2(a5),a2
	move.l	V_C2MASK(a5),a3
.go:	mulu	#$24,d0
	add.l	d0,a1
	move.w	(a1),d5			; bltsize
	moveq	#0,d3
	move.w	6(a1),d3		; source plane stride
	bsr	BufPtr
	add.l	d4,a0			; dest plane 1
	move.l	a0,d1			; C source = dest
	tst.w	(sp)
	beq.s	.nc
	move.l	V_PANO(a5),d1		; C source = panorama
	add.l	#BGHDR,d1
	add.l	d4,d1
.nc:	move.w	2(a1),d2
	add.w	#DSTRIDE,d2		; dest modulo
	WAITBLIT
	move.w	4(a1),BLTBMOD(a4)
	move.w	d2,BLTCMOD(a4)
	move.w	d2,BLTDMOD(a4)
	move.w	#-2,BLTAMOD(a4)
	move.l	#$ffff0000,BLTAFWM(a4)
	move.w	d6,BLTCON1(a4)
	move.w	d6,d0
	or.w	#$0fca,d0
	move.w	d0,BLTCON0(a4)
	; planes 1-4: cookie cut
	moveq	#4-1,d0
	move.l	a2,d2			; B data
.pl:	WAITBLIT
	move.l	d1,BLTCPT(a4)
	move.l	d2,BLTBPT(a4)
	move.l	a3,BLTAPT(a4)
	move.l	a0,BLTDPT(a4)
	move.w	d5,BLTSIZE(a4)
	lea	PL(a0),a0
	add.l	#PL,d1
	add.l	d3,d2
	dbf	d0,.pl
	if	EXP_NOCLR56
	bra	.x
	endif
	; planes 5 and up: clear under mask: D = C AND NOT A (no B channel: a
	; constant BLTBDAT is shifted together with the last word of the
	; previous B blit, which left one set pixel column per word)
	WAITBLIT
	move.w	d6,d0
	or.w	#$0b0a,d0
	move.w	d0,BLTCON0(a4)
	moveq	#PLANES-6,d0		; planes 5 .. last-1: C as planes 1-4
.p5:	WAITBLIT
	move.l	d1,BLTCPT(a4)
	move.l	a3,BLTAPT(a4)
	move.l	a0,BLTDPT(a4)
	move.w	d5,BLTSIZE(a4)
	lea	PL(a0),a0
	add.l	#PL,d1
	dbf	d0,.p5
	WAITBLIT			; last plane: C = destination (shadows)
	move.l	a0,BLTCPT(a4)
	move.l	a3,BLTAPT(a4)
	move.l	a0,BLTDPT(a4)
	move.w	d5,BLTSIZE(a4)
.x:	addq.l	#2,sp
	rts


;=====================================================================
; HUD: the game draws scores and energy bars into a hires 3-plane
; dual-playfield bitmap (pens: PF1 = planes 1+3, PF2 = plane 2 black).
; We keep a lores copy (mask, pen bit 0, pen bit 1) and draw it into
; the background like a sprite; the copper keeps recolouring pens 1-3
; per line exactly like the original HUD.
;=====================================================================
HudInit:
	movem.l	d0-d3/a0-a1,-(sp)
	; nibble tables: hires byte -> 4 lores pixels (OR of pixel pairs)
	lea	V_NIBH(a5),a0
	lea	V_NIBL(a5),a1
	moveq	#0,d0
.t:	moveq	#0,d1
	moveq	#6,d2			; pair (7,6) -> nibble bit 3 ...
.tb:	add.w	d1,d1
	move.w	d0,d3
	lsr.w	d2,d3
	and.w	#3,d3
	beq.s	.t0
	addq.w	#1,d1
.t0:	subq.w	#2,d2
	bpl.s	.tb
	; dither ($aa / $55, the empty part of the energy bars): lores
	; checkerboard instead of OR (which would look full)
	move.b	d1,d2			; odd rows: same unless dither
	cmp.b	#$aa,d0
	beq.s	.d
	cmp.b	#$55,d0
	bne.s	.nd
.d:	moveq	#$a,d1
	moveq	#$5,d2
.nd:	move.b	d1,(a1)
	move.b	d2,256(a1)
	addq.l	#1,a1
	lsl.b	#4,d1
	lsl.b	#4,d2
	move.b	d1,(a0)
	move.b	d2,256(a0)
	addq.l	#1,a0
	addq.w	#1,d0
	cmp.w	#256,d0
	bne.s	.t
	; HUD bitmap pointer and first line: from game list 1 (before StripList)
	move.l	R_LIST1(pc),a0
	move.w	#$190/4-1,d1
	moveq	#0,d2			; found flags
.l:	move.w	(a0),d0
	cmp.w	#$008e,d0
	bne.s	.l1
	bset	#0,d2
	bne.s	.l1
	move.b	2(a0),d0		; HUD DIWSTRT line
	and.w	#$ff,d0
	sub.w	V_LTOP(a5),d0
	move.w	d0,V_HUDROW(a5)
	bra.s	.ln
.l1:	cmp.w	#$00e0,d0
	bne.s	.l2
	move.w	2(a0),V_HUDBM(a5)
.l2:	cmp.w	#$00e2,d0
	bne.s	.ln
	move.w	2(a0),V_HUDBM+2(a5)
.ln:	addq.l	#4,a0
	dbf	d1,.l
	; clear copy and lores image, invalidate both buffers
	move.l	V_HUDLO(a5),a0
	move.w	#(HUDLOSZ+HUDSAVSZ)/2-1,d0
.c:	clr.w	(a0)+
	dbf	d0,.c
	move.w	#1,V_HUDVER(a5)
	move.w	#-1,V_HUDBX_A(a5)
	move.w	#-1,V_HUDBX_B(a5)
	clr.w	V_HUDV_A(a5)
	clr.w	V_HUDV_B(a5)
	movem.l	(sp)+,d0-d3/a0-a1
	rts

; blocks of the HUD (hires byte columns) and which bytes to compare
; to notice a change: start, bytes, first row, rows, planes (bit mask)
HudBlocks:
	dc.w	0,10,0,25,%001		; score player 1 (digits in plane 1)
	dc.w	10,30,10,1,%101		; energy bar 1 (one row tells all)
	dc.w	40,30,10,1,%101		; energy bar 2
	dc.w	70,10,0,25,%001		; score player 2
	dc.w	-1

HudUpdate:
	movem.l	d0-d7/a0-a6,-(sp)
	tst.l	V_HUDBM(a5)
	beq	.x
	lea	HudBlocks(pc),a6
.blk:	movem.w	(a6)+,d0-d4		; start, bytes, row0, rows, planes
	tst.w	d0
	bmi	.x
	; ---- compare sampled bytes ----
	move.l	V_HUDBM(a5),a0
	move.l	V_HUDSAV(a5),a1
	moveq	#0,d5			; plane
.pl:	btst	d5,d4
	beq.s	.pn
	move.w	d2,d6
	mulu	#HBPR,d6
	move.w	d5,d7
	mulu	#80,d7
	add.l	d7,d6
	add.w	d0,d6
	lea	(a0,d6.l),a2
	lea	(a1,d6.l),a3
	move.w	d3,d7
	subq.w	#1,d7
.rw:	move.w	d1,d6
	lsr.w	#1,d6
	subq.w	#1,d6
.cw:	cmpm.w	(a2)+,(a3)+
	bne.s	.changed
	dbf	d6,.cw
	lea	HBPR(a2),a2
	sub.w	d1,a2
	lea	HBPR(a3),a3
	sub.w	d1,a3
	dbf	d7,.rw
.pn:	addq.w	#1,d5
	cmp.w	#3,d5
	bne.s	.pl
	bra	.blk			; unchanged
.changed:
	; ---- copy the whole block (all rows, 3 planes) and convert ----
	move.l	V_HUDBM(a5),a0
	move.l	V_HUDSAV(a5),a1
	add.w	d0,a0
	add.w	d0,a1
	move.w	#HROWS*3-1,d7
.cr:	move.l	a0,a2
	move.l	a1,a3
	move.w	d1,d6
	lsr.w	#1,d6
	subq.w	#1,d6
.cc:	move.w	(a2)+,(a3)+
	dbf	d6,.cc
	lea	80(a0),a0
	lea	80(a1),a1
	dbf	d7,.cr
	move.w	d0,d6
	move.w	d1,d7
	bsr	ConvBlock
	addq.w	#1,V_HUDVER(a5)
	bra	.blk
.x:	movem.l	(sp)+,d0-d7/a0-a6
	rts

; ConvBlock: d6 = first hires byte (even), d7 = bytes (even)
;   HUDSAV (hires) -> HUDLO (lores), rows 0..HRN-1
ConvBlock:
	movem.l	d0-d7/a0-a6,-(sp)
	move.l	V_HUDSAV(a5),a0
	add.w	d6,a0
	move.l	V_HUDLO(a5),a1
	lsr.w	#1,d6
	add.w	d6,a1
	lsr.w	#1,d7
	subq.w	#1,d7			; lores bytes - 1
	moveq	#HRN-1,d5
.row:	; tables for this row's parity
	lea	V_NIBH(a5),a3
	lea	V_NIBL(a5),a4
	moveq	#HRN-1,d0
	sub.w	d5,d0			; row
	btst	#0,d0
	beq.s	.ev
	lea	256(a3),a3
	lea	256(a4),a4
.ev:	cmp.w	#2,d0
	blo.s	.conv			; rows 0, 1: always convert
	; ---- same hires bytes as two rows above? copy its lores bytes ----
	move.l	a0,a2
	lea	-2*HBPR(a0),a6
	moveq	#3-1,d3
.pc:	move.l	a2,d0
	move.l	a6,d1
	move.w	d7,d4
.cw:	cmpm.w	(a6)+,(a2)+
	bne.s	.conv
	dbf	d4,.cw
	move.l	d0,a2
	lea	80(a2),a2
	move.l	d1,a6
	lea	80(a6),a6
	dbf	d3,.pc
	lea	-2*LROW(a1),a2
	move.l	a1,a6
	moveq	#3-1,d3
.cp:	move.l	a2,d0
	move.l	a6,d1
	move.w	d7,d4
.cb:	move.b	(a2)+,(a6)+
	dbf	d4,.cb
	move.l	d0,a2
	lea	LBPL(a2),a2
	move.l	d1,a6
	lea	LBPL(a6),a6
	dbf	d3,.cp
	bra.s	.next
.conv:	move.l	a0,a2
	move.l	a1,a6
	move.w	d7,d4
.b:	moveq	#0,d0
	moveq	#0,d1
	moveq	#0,d2
	moveq	#0,d3
	move.b	(a2),d0			; plane 1 (PF1 bit 0)
	move.b	1(a2),d1
	move.b	160(a2),d2		; plane 3 (PF1 bit 1)
	move.b	161(a2),d3
	move.b	(a3,d0.w),d6
	or.b	(a4,d1.w),d6
	move.b	d6,LBPL(a6)		; pen bit 0
	move.b	(a3,d2.w),d6
	or.b	(a4,d3.w),d6
	move.b	d6,2*LBPL(a6)		; pen bit 1
	or.b	80(a2),d0		; plane 2 (PF2, black)
	or.b	81(a2),d1
	or.b	d2,d0
	or.b	d3,d1
	move.b	(a3,d0.w),d6
	or.b	(a4,d1.w),d6
	move.b	d6,(a6)+		; mask
	addq.l	#2,a2
	dbf	d4,.b
.next:	lea	HBPR(a0),a0
	lea	LROW(a1),a1
	dbf	d5,.row
	movem.l	(sp)+,d0-d7/a0-a6
	rts

; HudDraw: draw the lores HUD into the current draw buffer if the scroll
; position or the HUD changed since this buffer got it.
HudDraw:
	movem.l	d0-d7/a0-a4,-(sp)
	tst.l	V_HUDBM(a5)
	beq	.x
	lea	$dff000,a4
	bsr	DrawBuf			; a0 bitmap, d0 = 0 A / 1 B
	move.l	a0,a2
	lea	V_HUDBX_A(a5),a1
	tst.w	d0
	beq.s	.a
	lea	V_HUDBX_B(a5),a1
.a:	move.l	O_SCROLL(a5),d7
	add.w	#80+16,d7		; bitmap x of HUD pixel 0 (DIW $81)
	move.w	V_HUDVER(a5),d6
	cmp.w	(a1),d7
	bne.s	.go
	cmp.w	4(a1),d6		; V_HUDV_x (2 words after V_HUDBX_x)
	beq	.x
.go:	move.l	V_PANO(a5),a3
	lea	BGHDR(a3),a3
	; restore the old place
	; restore the part of the old place that the new one does not cover
	move.w	(a1),d1
	bmi.s	.new
	lsr.w	#4,d1			; old first word
	move.w	d7,d2
	lsr.w	#4,d2			; new first word
	sub.w	d1,d2			; new - old (words)
	beq.s	.new
	bpl.s	.left
	neg.w	d2			; moved left: restore the right end
	add.w	#LBPL/2,d1
	sub.w	d2,d1
.left:	cmp.w	#LBPL/2,d2
	ble.s	.w
	moveq	#LBPL/2,d2
.w:	add.w	d1,d1
	move.w	V_HUDROW(a5),d0
	moveq	#HRN,d3
	moveq	#0,d4
	bsr	BlitRestore
.new:	move.w	d7,(a1)
	move.w	d6,4(a1)
	; offset in bitmap
	move.w	V_HUDROW(a5),d0
	mulu	#STRIDE,d0
	move.w	d7,d1
	lsr.w	#4,d1
	add.w	d1,d1
	ext.l	d1
	add.l	d1,d0			; d0 = offset
	and.w	#15,d7
	ror.w	#4,d7			; shift << 12
	move.l	V_HUDLO(a5),a0		; mask
	WAITBLIT
	move.l	#$ffffffff,BLTAFWM(a4)
	move.w	#LROW-LBPL,BLTAMOD(a4)
	move.w	#LROW-LBPL,BLTBMOD(a4)
	move.w	#STRIDE-LBPL,BLTCMOD(a4)
	move.w	#STRIDE-LBPL,BLTDMOD(a4)
	move.w	d7,BLTCON1(a4)
	moveq	#0,d5			; plane
.pl:	lea	(a3,d0.l),a1		; C = clean panorama
	lea	(a2,d0.l),a2		; D = buffer
	WAITBLIT
	move.l	a0,BLTAPT(a4)
	move.l	a1,BLTCPT(a4)
	move.l	a2,BLTDPT(a4)
	move.w	d7,d1
	cmp.w	#2,d5
	bhs.s	.nob
	lea	LBPL(a0),a1		; pen bit 0 / 1
	tst.w	d5
	beq.s	.b0
	lea	LBPL(a1),a1
.b0:	move.l	a1,BLTBPT(a4)
	or.w	#$0fca,d1
	bra.s	.go2
.nob:	or.w	#$0b0a,d1		; planes 3-6: pen 1-3 have them 0 (C AND NOT A)
.go2:	move.w	d1,BLTCON0(a4)
	move.w	#(HRN<<6)|(LBPL/2),BLTSIZE(a4)
	sub.l	d0,a2			; back to bitmap base
	add.l	#PL,d0			; next plane
	addq.w	#1,d5
	cmp.w	#PLANES,d5
	bne.s	.pl
.x:	movem.l	(sp)+,d0-d7/a0-a4
	rts

;=====================================================================
; Foreground (France): the OpalVision priority stencil marks parts of
; the image that are in front of the fighters. Copy those pixels back
; from the clean panorama over the new fighter and shadow boxes.
;=====================================================================
Foreground:
	movem.l	d0-d7/a0-a6,-(sp)
	tst.l	V_MASK(a5)
	beq	.x
	lea	$dff000,a4
	bsr	BufPtr
	move.l	a0,a2
	move.l	V_PANO(a5),a3
	lea	80(a3),a6		; stencil rectangles in the header
	lea	BGHDR(a3),a3
	move.w	(a6)+,d7
	subq.w	#1,d7
	bmi	.x
.rect:	lea	V_NB1(a5),a1
	moveq	#4-1,d6			; fighter 1, 2, shadow 1, 2
.box:	movem.w	(a1),d0-d3		; row, colbyte, words, rows
	tst.w	d3
	ble	.nb
	tst.w	d2
	ble	.nb
	; rows: [max(r, R), min(r+h, R+H))
	add.w	d0,d3
	move.w	(a6),d4
	cmp.w	d4,d0
	bge.s	.r0
	move.w	d4,d0
.r0:	add.w	2(a6),d4
	cmp.w	d4,d3
	ble.s	.r1
	move.w	d4,d3
.r1:	sub.w	d0,d3
	ble	.nb
	; columns (bytes): [max(c, C), min(c+2w, C+2W))
	add.w	d2,d2
	add.w	d1,d2			; box end
	move.w	4(a6),d4
	cmp.w	d4,d1
	bge.s	.c0
	move.w	d4,d1
.c0:	move.w	6(a6),d5
	add.w	d5,d5
	add.w	4(a6),d5		; rect end
	cmp.w	d5,d2
	ble.s	.c1
	move.w	d5,d2
.c1:	sub.w	d1,d2			; bytes
	ble	.nb
	moveq	#PLANES,d4		; fighters: all planes
	cmp.w	#2,d6
	bcc.s	.fb
	moveq	#1,d4			; shadows (boxes 3, 4): last plane only
.fb:	bsr.s	FgBlit
.nb:	addq.l	#8,a1
	dbf	d6,.box
	addq.l	#8,a6
	dbf	d7,.rect
.x:	movem.l	(sp)+,d0-d7/a0-a6
	rts

; FgBlit: d0 row, d1 colbyte, d2 bytes, d3 rows, d4 = 6 (planes 1-6) or
;   1 (plane 6 only); a2 buffer, a3 panorama
;   D = stencil ? panorama : buffer
FgBlit:
	movem.l	d0-d7/a0,-(sp)
	move.w	d4,d6
	subq.w	#1,d6			; plane count - 1
	move.w	d0,d4
	sub.w	V_MROW0(a5),d4
	mulu	#PL,d4
	add.w	d1,d4
	move.l	V_MASK(a5),a0
	add.l	d4,a0
	mulu	#STRIDE,d0
	ext.l	d1
	add.l	d1,d0			; offset in bitmap
	tst.w	d6
	bne.s	.all
	add.l	#LASTPL,d0		; last plane only
.all:	lsl.w	#6,d3
	move.w	d2,d4
	lsr.w	#1,d4
	or.w	d4,d3			; bltsize
	move.w	#PL,d4
	sub.w	d2,d4			; stencil modulo
	move.w	#STRIDE,d5
	sub.w	d2,d5
	WAITBLIT
	move.l	#$ffffffff,BLTAFWM(a4)
	move.l	#$0fca0000,BLTCON0(a4)
	move.w	d4,BLTAMOD(a4)
	move.w	d5,BLTBMOD(a4)
	move.w	d5,BLTCMOD(a4)
	move.w	d5,BLTDMOD(a4)
.pl:	WAITBLIT
	move.l	a0,BLTAPT(a4)
	pea	(a3,d0.l)
	move.l	(sp)+,BLTBPT(a4)
	pea	(a2,d0.l)
	move.l	(sp),BLTCPT(a4)
	move.l	(sp)+,BLTDPT(a4)
	move.w	d3,BLTSIZE(a4)
	add.l	#PL,d0
	dbf	d6,.pl
	movem.l	(sp)+,d0-d7/a0
	rts

;=====================================================================
; PollKeys: KARATE runs with interrupts off and never reads the
; keyboard. Poll the CIA serial port; Amiga+Q ends the fight and tells
; the loader to quit to Workbench.
;=====================================================================
PollKeys:
	movem.l	d0-d1,-(sp)
	move.b	$bfed01,d0		; CIA-A ICR (no CIA-A interrupts in use)
	btst	#3,d0
	beq.s	.x
	move.b	$bfec01,d0		; key code
	bset	#6,$bfee01		; handshake (SP low) ...
	not.b	d0
	ror.b	#1,d0
	move.b	$dff006,d1		; ... for about two raster lines
.w1:	cmp.b	$dff006,d1
	beq.s	.w1
	move.b	$dff006,d1
.w2:	cmp.b	$dff006,d1
	beq.s	.w2
	bclr	#6,$bfee01
	bsr.s	FightKey
	move.b	d0,d1
	and.b	#$7e,d1
	cmp.b	#$66,d1			; left/right Amiga (down or up)
	bne.s	.q
	tst.b	d0
	smi	d1
	not.b	d1
	ext.w	d1
	move.w	d1,V_AMIGA(a5)		; -1 while held
	bra.s	.x
.q:	cmp.b	#$10,d0			; Q pressed
	bne.s	.x
	tst.w	V_AMIGA(a5)
	beq.s	.x
	move.l	#1,QUITFLAG.w
	move.w	#$64,$2116(a5)		; main loop ends -> normal exit
.x:	movem.l	(sp)+,d0-d1
	rts

; FightKey: d0 = key code (bit 7 = released) -> V_KEYS
FightKey:
	movem.l	d1-d2/a0,-(sp)
	lea	FightKeyTab(pc),a0
	move.b	d0,d1
	and.b	#$7f,d1
.t:	move.b	(a0)+,d2
	bmi.s	.x
	cmp.b	(a0)+,d1
	bne.s	.t
	tst.b	d0
	bmi.s	.up
	move.w	V_KEYS(a5),d1
	bset	d2,d1
	bra.s	.st
.up:	move.w	V_KEYS(a5),d1
	bclr	d2,d1
.st:	move.w	d1,V_KEYS(a5)
.x:	movem.l	(sp)+,d1-d2/a0
	rts
; bit, key code
FightKeyTab:
	dc.b	0,$11, 1,$21, 2,$20, 3,$22, 4,$60, 5,$64	; W S A D LShift LAlt
	dc.b	8,$4c, 9,$4d, 10,$4f, 11,$4e, 12,$61, 13,$65	; cursors RShift RAlt
	dc.b	-1
	even

;=====================================================================
; Keyboard and joystick of a human player
;   KeyBits: d7 = fighter -> d3 = keys as joystick bits (0 up, 1 down,
;     2 left, 3 right, 4 fire). Two players: W/A/S/D + left Shift/Alt
;     play the left fighter, cursor keys + right Shift/Alt the right one.
;     One player: both sets play the human fighter.
;   HumanInput: d7 = fighter, d1 = JOYxDAT, d2 = fire bit in $bfe001
;     -> d0 = JOYxDAT value (joystick OR keys), d1 = 0 fire pressed / 1
;=====================================================================
KeyBits:
	move.w	V_KEYS(a5),d3
	tst.w	V_MODE(a5)
	bne.s	.both
	tst.w	d7
	beq.s	.lo
	lsr.w	#8,d3
	bra.s	.lo
.both:	move.w	d3,-(sp)
	lsr.w	#8,d3
	or.w	(sp)+,d3
.lo:	btst	#5,d3			; Alt = fire
	beq.s	.f
	bset	#4,d3
.f:	and.w	#$1f,d3
	rts

HumanInput:
	movem.l	d2-d4,-(sp)
	bsr.s	KeyBits
	move.w	d3,d4
	btst	#1,d1			; joystick -> bits
	beq.s	.j1
	bset	#3,d4			; right
.j1:	btst	#9,d1
	beq.s	.j2
	bset	#2,d4			; left
.j2:	move.w	d1,d0
	lsr.w	#1,d0
	eor.w	d1,d0
	btst	#0,d0
	beq.s	.j3
	bset	#1,d4			; down
.j3:	btst	#8,d0
	beq.s	.j4
	bset	#0,d4			; up
.j4:	btst	d2,$bfe001
	bne.s	.j5
	bset	#4,d4			; fire
.j5:	move.w	d4,d0			; opposite directions cancel
	and.w	#$c,d0
	cmp.w	#$c,d0
	bne.s	.c1
	and.w	#~$c,d4
.c1:	move.w	d4,d0
	and.w	#3,d0
	cmp.w	#3,d0
	bne.s	.c2
	and.w	#~3,d4
.c2:	moveq	#0,d0			; bits -> JOYxDAT
	btst	#3,d4
	beq.s	.b1
	or.w	#$0002,d0
.b1:	btst	#2,d4
	beq.s	.b2
	or.w	#$0200,d0
.b2:	move.w	d0,d1
	lsr.w	#1,d1
	or.w	d1,d0			; bit 0 = right, bit 8 = left
	btst	#1,d4
	beq.s	.b3
	eor.w	#$0001,d0		; down
.b3:	btst	#0,d4
	beq.s	.b4
	eor.w	#$0100,d0		; up
.b4:	moveq	#1,d1
	btst	#4,d4
	beq.s	.b5
	moveq	#0,d1
.b5:	movem.l	(sp)+,d2-d4
	rts

;=====================================================================
; Computer opponent
;   kok.cfg: mode 'L' (you left vs CPU) / 'R' (CPU vs you right) /
;   anything else = two players; level 'E' / 'N' / 'H'.
;   The CPU player "presses" joystick directions exactly like a human:
;   player 2 through the game's own unused input override ($1380 value,
;   $1382 fire (0 = pressed), $1384 enable), player 1 through P1Joy /
;   P1Fire. The human always uses the joystick in port 2.
;=====================================================================
O_P2JOY		equ	$1380
O_P2FIRE	equ	$1382
O_P2OVR		equ	$1384
O_DIRTAB1	equ	$1600		; pointer to player 1 direction table
O_DIRTAB2	equ	$1604
O_SEQPOS1	equ	$23de		; position in the current move (0 = start)
O_SEQPOS2	equ	$23e0
O_STUN1		equ	$210a		; being hit / down: input ignored
O_STUN2		equ	$210c

ParseCfg:
	; the title menu leaves its choice at $190: 'K', mode, level
	cmp.b	#'K',$190.w
	bne.s	.file
	move.b	$191.w,V_CFG(a5)
	move.b	$192.w,V_CFG+1(a5)
.file:	moveq	#0,d0
	move.b	V_CFG(a5),d1
	cmp.b	#'L',d1
	bne.s	.1
	moveq	#1,d0			; CPU plays the right fighter
.1:	cmp.b	#'R',d1
	bne.s	.2
	moveq	#2,d0			; CPU plays the left fighter
.2:	cmp.b	#'C',d1
	bne.s	.2a
	moveq	#3,d0			; computer vs computer
.2a:	move.w	d0,V_MODE(a5)
	moveq	#1,d0
	move.b	V_CFG+1(a5),d1
	cmp.b	#'E',d1
	bne.s	.3
	moveq	#0,d0
.3:	cmp.b	#'H',d1
	bne.s	.4
	moveq	#2,d0
.4:	move.w	d0,V_LEVEL(a5)
	clr.w	O_P2OVR(a5)
	lea	V_AIST(a5),a0
	moveq	#2-1,d0
.5:	move.w	#-1,(a0)+
	clr.w	(a0)+
	move.w	#25,(a0)+
	dbf	d0,.5
	rts

; player 1 joystick: real port 2, or the CPU
P1Joy:	btst	#1,V_MODE+1(a5)		; modes 2, 3: CPU plays player 1
	beq.s	.hw
	move.w	V_AIJ1(a5),d0
	rts
.hw:	movem.l	d1-d2/d7,-(sp)
	bsr	PollKeys
	move.w	$dff00c,d1		; JOY1DAT (port 2) + keys
	moveq	#7,d2
	moveq	#0,d7
	bsr	HumanInput
	movem.l	(sp)+,d1-d2/d7
	rts

; player 1 fire: Z = 1 when pressed (like btst #7,$bfe001)
P1Fire:	btst	#1,V_MODE+1(a5)
	beq.s	.hw
	tst.w	V_AIF1(a5)
	beq.s	.no
	move.w	#4,ccr
	rts
.no:	move.w	#0,ccr
	rts
.hw:	movem.l	d0-d2/d7,-(sp)
	move.w	$dff00c,d1
	moveq	#7,d2
	moveq	#0,d7
	bsr	HumanInput
	tst.w	d1			; Z = 1: pressed
	movem.l	(sp)+,d0-d2/d7		; (movem keeps the flags)
	rts

Rnd:	; d0 = 0..255
	move.w	V_RND(a5),d0
	mulu	#25173,d0
	add.w	#13849,d0
	add.w	V_FRAMES+2(a5),d0
	move.w	d0,V_RND(a5)
	lsr.w	#8,d0
	rts

; difficulty: reaction (loops), defend %, attack % (of 256)
AiParams:
	dc.w	14,50,100		; easy
	dc.w	7,130,160		; normal
	dc.w	3,215,220		; hard

; attacks: move index, min dist, max dist (from the game's hit table)
AiAttacks:
	dc.w	1,50,83			; punch
	dc.w	3,30,70			; low punch
	dc.w	9,65,95			; high kick
	dc.w	10,70,125		; side kick
	dc.w	12,24,91		; sweep
	dc.w	-1

AiTick:
	movem.l	d0-d7/a0-a3,-(sp)
	; ---- winner so far (for HISCORE): $194 = 'A' when the CPU leads ----
	clr.b	$194.w
	move.w	#1,O_P2OVR(a5)		; player 2 input comes from O_P2JOY
	move.w	V_MODE(a5),d0
	bne.s	.cpu
	move.w	$dff00a,d1		; two players: port 1 + keys
	moveq	#6,d2
	bra.s	.hum2
.cpu:	moveq	#0,d1			; d1 = 1: CPU is winning
	cmp.w	#3,d0
	beq.s	.cw
	move.w	$71c(a5),d2		; energy player 1
	move.w	$71e(a5),d3		; energy player 2
	cmp.w	#1,d0
	bne.s	.w2
	cmp.w	d3,d2			; CPU = player 2: P1 has less
	bge.s	.wd
	bra.s	.cw
.w2:	cmp.w	d2,d3			; CPU = player 1: P2 has less
	bge.s	.wd
.cw:	move.b	#'A',$194.w
.wd:	move.w	V_MODE(a5),d0
	cmp.w	#2,d0
	bne.s	.h1
	move.w	$dff00c,d1		; human (port 2 + keys) plays player 2
	moveq	#7,d2
.hum2:	moveq	#1,d7
	bsr	HumanInput
	move.w	d0,O_P2JOY(a5)
	move.w	d1,O_P2FIRE(a5)		; 0 = pressed
	bra.s	.h2			; (mode 2: the CPU plays player 1)
.h1:	btst	#0,d0			; modes 1, 3: CPU plays player 2
	beq.s	.h2
	moveq	#1,d7
	bsr.s	AiRun
.h2:	move.w	V_MODE(a5),d0
	btst	#1,d0			; modes 2, 3: CPU plays player 1
	beq.s	.x
	moveq	#0,d7
	bsr.s	AiRun
.x:	movem.l	(sp)+,d0-d7/a0-a3
	rts

; AiRun: d7 = fighter (0 left / player 1, 1 right / player 2)
AiRun:
	lea	V_AIST(a5),a3
	move.w	d7,d0
	mulu	#6,d0
	add.w	d0,a3			; (a3) out, 2(a3) hold, 4(a3) wait
	lea	O_F1X(a5),a0		; me
	lea	O_F2X(a5),a1		; opponent
	move.w	O_F1DIR(a5),d6		; my facing
	move.w	O_F2FRAME(a5),d5	; opponent frame
	move.w	O_SEQPOS1(a5),d4
	or.w	O_STUN1(a5),d4		; busy
	tst.w	d7
	beq.s	.c0
	exg	a0,a1
	move.w	O_F2DIR(a5),d6
	move.w	O_F1FRAME(a5),d5
	move.w	O_SEQPOS2(a5),d4
	or.w	O_STUN2(a5),d4
.c0:	; ---- still holding / waiting? ----
	tst.w	2(a3)
	beq.s	.nohold
	subq.w	#1,2(a3)
	bra	.out
.nohold:
	move.w	#-1,(a3)
	tst.w	4(a3)
	beq.s	.decide
	subq.w	#1,4(a3)
	bra	.out
.decide:
	tst.w	d4			; my move still running: wait
	bne	.out
	lea	AiParams(pc),a2
	move.w	V_LEVEL(a5),d0
	mulu	#6,d0
	add.w	d0,a2
	move.w	(a1),d3			; opponent x
	sub.w	(a0),d3			; dx
	moveq	#0,d2			; facing needed: 0 right, $c left
	tst.w	d3
	bpl.s	.r
	moveq	#$c,d2
	neg.w	d3			; d3 = distance
.r:	; ---- not facing the opponent: turn (with a back punch if close) ----
	cmp.w	d2,d6
	beq.s	.facing
	moveq	#14,d1			; fire + back: turn with side kick
	cmp.w	#50,d3
	blo.s	.turn
	cmp.w	#80,d3
	bhi.s	.turn
	bsr	Rnd
	cmp.w	#128,d0
	bhs.s	.turn
	moveq	#15,d1			; fire + up + back: back punch (300)
.turn:	moveq	#4,d0
	bra	.act
.facing:
	; ---- opponent attacking and in range: defend ----
	lea	AiThreats(pc),a1
.th:	move.w	(a1)+,d0
	bmi.s	.nothreat
	movem.w	(a1)+,d1-d2		; first frame, last frame  (d0 = reach)
	cmp.w	d1,d5
	blo.s	.th
	cmp.w	d2,d5
	bhi.s	.th
	cmp.w	d0,d3
	bhi.s	.nothreat		; out of reach
	bsr	Rnd
	cmp.w	2(a2),d0
	bhs.s	.nothreat		; did not react
	moveq	#5,d1			; down + back: block
	moveq	#10,d0
	cmp.w	#37,d5			; sweep coming: jump (up)
	blo	.act
	cmp.w	#41,d5
	bhi	.act
	moveq	#0,d1
	moveq	#6,d0
	bra	.act
.nothreat:
	; ---- too far / too close ----
	cmp.w	#120,d3
	bls.s	.near
	cmp.w	#136,d3			; eye poke range: only on an idle opponent
	bhi.s	.walk
	cmp.w	#5,d5
	bls.s	.poke
	cmp.w	#49,d5
	blo.s	.walk
.poke:	bsr	Rnd
	cmp.w	4(a2),d0
	bhs.s	.walk
	moveq	#8,d1			; fire + up: eye poke (500)
	moveq	#3,d0
	bra	.act
.walk:	moveq	#2,d1			; forward
	moveq	#6,d0
	bra	.act
.near:	cmp.w	#26,d3
	bhs.s	.att
	moveq	#6,d1			; back
	moveq	#4,d0
	bra	.act
.att:	; ---- attack: random move whose reach covers the distance ----
	bsr	Rnd
	cmp.w	4(a2),d0
	bhs.s	.idle
	bsr	Rnd
	and.w	#3,d0			; try from a random start
	mulu	#6,d0
	lea	AiAttacks(pc),a1
	add.w	d0,a1
	moveq	#5-1,d2
.ta:	tst.w	(a1)
	bpl.s	.ta1
	lea	AiAttacks(pc),a1
.ta1:	movem.w	(a1)+,d1/d4/d5
	cmp.w	d4,d3
	blo.s	.tn
	cmp.w	d5,d3
	bls.s	.hit
.tn:	dbf	d2,.ta
	bra.s	.idle
.hit:	moveq	#3,d0
	bra	.act
.idle:	; nothing to do: sometimes step closer
	bsr	Rnd
	cmp.w	#90,d0
	bhs	.out
	moveq	#2,d1
	moveq	#3,d0
.act:	move.w	d1,(a3)
	move.w	d0,2(a3)
	move.w	(a2),d0			; reaction time + jitter
	move.w	d0,4(a3)
	bsr	Rnd
	and.w	#3,d0
	add.w	d0,4(a3)
.out:	; ---- output: index -> joystick value of this fighter ----
	moveq	#0,d0			; neutral
	moveq	#0,d2			; fire
	move.w	(a3),d1
	bmi.s	.o1
	move.l	O_DIRTAB1(a5),a0
	tst.w	d7
	beq.s	.o0
	move.l	O_DIRTAB2(a5),a0
.o0:	move.w	d1,d3
	and.w	#7,d3
	add.w	d3,d3
	move.w	(a0,d3.w),d0
	btst	#3,d1
	sne	d2
	and.w	#1,d2
.o1:	tst.w	d7
	beq.s	.p1
	move.w	d0,O_P2JOY(a5)		; player 2
	eor.w	#1,d2
	move.w	d2,O_P2FIRE(a5)		; 0 = pressed
	rts
.p1:	move.w	d0,V_AIJ1(a5)		; player 1
	move.w	d2,V_AIF1(a5)
	rts

; opponent attacks: reach, first and last frame before the hit
AiThreats:
	dc.w	95,1,3			; high kick
	dc.w	70,6,8			; low punch
	dc.w	125,21,24		; side kick
	dc.w	91,37,39		; sweep
	dc.w	91,41,41
	dc.w	83,42,42		; punch
	dc.w	-1

	cnop	0,4
PatchEnd:
