King of Karate - Chipset patch v1.0
===================================

Author:  Leopold "Leon" Tupalski, TULAB
E-mail:  leopoldtupalski@yahoo.com

King of Karate (Centaur 1992) came with the OpalVision card and showed
its 24-bit backgrounds through it; on a plain Amiga you only saw the
fighters on black. This kit makes the game show everything with the
Amiga chipset alone:

  - fights: scrolling full-height panoramas in EHB (64 colours,
    translucent shadows), HAM6, or AGA (256 colours from a 24-bit
    palette, shadows; A1200/A4000/CD32 only), energy bars and scores
    on top of the scenery, fighters at the original height and behind
    the foreground walls in France (from the original priority
    stencil),
  - title screen and high score screen (with its pagoda picture) in
    EHB/HAM/AGA,
  - computer opponent (3 levels) and a CPU-vs-CPU demo,
  - start-up screen for game mode and difficulty,
  - joystick and/or keyboard control, Amiga+Q quits to Workbench,
  - works on AGA and with a relocated VBR.

Unofficial fan patch, not affiliated with Centaur or the makers of
OpalVision. NO GAME FILES ARE INCLUDED - you need your own copy of
the original.

  python3 kokpatch.py <original game dir> <output dir> [--mode ehb|ham|aga]
                      [--title-mode ehb|ham|aga]

Needs Python 3.8+ with numpy on the PC (Windows: "python" instead of
"python3"). The output directory must differ from the game directory.
Copy the output directory to the Amiga and start the KingOfKarate
icon. The *.dat files (old OpalVision pictures) and animframes.dat
are no longer needed there. opal.library is NOT needed.

Amiga: ehb/ham - OCS/ECS/AGA, 1 MB chip + ~1 MB fast RAM or 2 MB chip;
aga - AGA chipset and 2 MB chip RAM. Start it from a plain PAL/NTSC
Workbench screen mode (not Multiscan/DblPAL/Productivity).
Tested on A600 + Furia 68EC020 and A600 68000 + A6095 (KS 3.1, EHB and
HAM) and in WinUAE (AGA). Reports from real A1200/A4000/CD32 welcome.

Start-up screen (before the original F1/F2/F3 stage menu)
  joystick in port 2 or cursor keys:
    up/down     game mode: 2 players / you (left) vs CPU /
                CPU vs you (right) / demo (CPU vs CPU)
    left/right  difficulty: easy / normal / hard
    Fire/Space  continue to the stage menu (Fire/Space there: back)
  Shift and Alt work as Fire too - also on the high score table
  (after the name is entered with Return).

Fight controls - joystick or keyboard (both work at the same time)
                   left fighter            right fighter
  joystick         port 2                  port 1 (mouse port)
  keyboard         W A S D +               cursor keys +
                   left Shift or left Alt  right Shift or right Alt
  Against the computer both keyboard sets and the joystick in port 2
  control your fighter. Shift/Alt = fire; diagonals = two keys.
  Moves ("forward" = the way the fighter faces; he does not turn by
  himself - fire + back turns him):
    forward / back          step
    up + forward            punch
    down + forward          low punch
    down + back             block (hold)
    up                      stance / dodge
    fire + up               eye poke
    fire + up + forward     high kick
    fire + forward          side kick
    fire + down             sweep
    fire + back             turn with side kick
    fire + up + back        back punch, then turn

A winning CPU enters itself as AMIGA in the high scores; the demo
runs unattended.

patches/*.bin are assembled from patches/*.s with vasm (vasmm68k_mot):
  python3 patches/build.py [path to vasmm68k_mot]
rebuilds all of them and patches/layout.txt, byte for byte the same.

Credits
  Patch: Leopold "Leon" Tupalski (TULAB) and Claude (an AI model by
  Anthropic), working human-in-the-loop: Claude wrote the 68000 patch
  code, the graphics converter and the test tools; Leon set the
  direction, tested on real hardware (A600) and in WinUAE and caught
  the bugs.
  Original game (c) 1992 Centaur - code: Marc Hawlitzeck, graphics:
  Greg Niles, music: Bjorn Lynne.
See CzytajTo.txt (Polish) for details. License: see LICENSE.
