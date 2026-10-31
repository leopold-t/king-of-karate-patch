#!/usr/bin/env python3
"""Rebuild patches/*.bin from patches/*.s with the vasm assembler
(vasmm68k_mot, http://sun.hasenbraten.de/vasm/ - Motorola syntax).

usage:  python3 build.py [path to vasmm68k_mot]

Assembles karate_patch, title_patch, hiscore_patch (OCS and AGA
variants), then shellfix for every program at the address where it is
appended (written to layout.txt, read by kokpatch.py) and loaderfix.
The result is identical byte for byte to the files of the release.
"""
import os, subprocess, sys, shutil
HERE = os.path.dirname(os.path.abspath(__file__))
V = sys.argv[1] if len(sys.argv) > 1 else (shutil.which('vasmm68k_mot') or 'vasmm68k_mot')

def asm(src, out, **d):
    cmd = [V, '-quiet', '-Fbin', '-no-opt', '-m68000'] + [f'-D{k}={v}' for k, v in d.items()] + \
          ['-o', os.path.join(HERE, out), os.path.join(HERE, src)]
    subprocess.run(cmd, check=True)
    return os.path.getsize(os.path.join(HERE, out))

al = lambda x: (x + 3) & ~3
k = asm('karate_patch.s', 'karate_patch.bin')
ka = asm('karate_patch.s', 'karate_patch_aga.bin', AGA=1)
t = asm('title_patch.s', 'title_patch.bin')
ta = asm('title_patch.s', 'title_patch_aga.bin', AGA=1)
h = asm('hiscore_patch.s', 'hiscore_patch.bin')
ha = asm('hiscore_patch.s', 'hiscore_patch_aga.bin', AGA=1)
# code hunk sizes of the original programs: KARATE $4c00, TITLE $3808, HISCORE 10908
orgs = {'karate': al(0x4c00 + k), 'karate_aga': al(0x4c00 + ka), 'title': al(0x3808 + t),
        'title_aga': al(0x3808 + ta), 'hiscore': al(10908 + h), 'hiscore_aga': al(10908 + ha)}
for n, p in (('karate', 1), ('karate_aga', 1), ('title', 2), ('title_aga', 2), ('hiscore', 3), ('hiscore_aga', 3)):
    asm('shellfix.s', f'shellfix_{n}.bin', ORG=orgs[n], PROG=p)
orgs['loader'] = 640
asm('loaderfix.s', 'loaderfix.bin', ORG=640)
with open(os.path.join(HERE, 'layout.txt'), 'w') as f:
    for n, o in orgs.items():
        f.write(f'{n} {o}\n')
print('OK', orgs)
