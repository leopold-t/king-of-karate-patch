#!/usr/bin/env python3
"""King of Karate (Centaur 1992, OpalVision) - Chipset patch v1.0: patcher + converter.
Leopold "Leon" Tupalski (TULAB) and Claude (Anthropic), human-in-the-loop.

Builds an OCS/ECS (or AGA) version of the game from YOUR OWN copy of the
original files. Nothing from the original game is included in this kit.

usage:  python3 kokpatch.py <original game dir> <output dir> [--mode ehb|ham|aga]
                            [--title-mode ehb|ham|aga]

requires: Python 3.8+, numpy   (pip install numpy)
"""
import argparse, hashlib, os, struct, sys, shutil
if sys.version_info < (3, 8):
    sys.exit('Python 3.8 or newer is required.')
try:
    import numpy as np
except ImportError:
    sys.exit('numpy is missing - install it with:  pip install numpy')

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from scripts import hunkio, bgconv
from scripts.palette import DEF, BEACH, REMAP, regs16

ORIGINAL = {   # sha256 of the files this patch was made for
    'KARATE':     '172dfd1f419536add5e1a2487f3b21ee26d5637705714d8acc89305877bf57d9',
    'TITLE':      '4b0499d104d88dca54d5c52b7c76dbf4c9fca8e51e729271dc2035bf2efd54c8',
    'HISCORE':    'dc064fbdccdcd5e0c83f67256b9ed86fe8d83a159c5c12b2afb7bbfc280394d4',
    'loader.exe': 'cf9d464e0207ae599f75c575688fb1bd35c928a0fd9588d5d4dbcd49ea9e6071',
    'animframes.dat': '356fc044df55e9703fe115bdb57985a4329f64d00f6db10ec8a821edcc436452',
    'house1.dat': 'c642ec299a5d83cc02777c8849c6201a7d4ca6a8937adb569f05f64ece6af50d',
    'house2.dat': '7d3d29524001b76681c32606880608fc194cb8062284030add01d1b2cd5a05c9',
    'lview1.dat': '05dc26723b2560f1f6a3bbe158d512027b4bf2acfd45e1f430790bd9b57799c0',
    'lview2.dat': '18c15a262e71f05342f3514d50030e5c471e3529f9f99921ab8fda7fbb049491',
    'beach1.dat': 'b981452b4d7168133e65681c23dd28a9cb7750a5b64a46002466905a13ec7295',
    'beach2.dat': '7c06f830c69323f02e33df4373fa7d1eae02f24b0c58a73f36bf66abbe0c98ef',
    'hscore.dat': 'a6e1e2ad6696b518024703a3f41d96cb1d4be1fc917841b157bcb8e547ee9263',
    'titles.dat': '24216217b5eed39edddb0a2b386d61ce4019db68eaaf46968471a0f38ad09061',
}
# sha256 of the patched executables of this release (v1.0); AGA builds differ
PATCHED = {
    'KARATE': '2a83e1e2ecbc6f80052364260e5750262601e28e21ee1f5be7302232519ad8a5',
    'TITLE': '385d4d681ef92eb6db57a1e57037322f8bcecb6de22c824351349831583d4f9a',
    'HISCORE': 'cd10e1bcb03cf9afbad7db7113bed5f92de8323cd93ef1e2b41ce9502708eac5',
    'loader.exe': '5fa9f0a335bb9aec2ff0048e35ce750452f599fc125d1cf26bae8c0c93fa61d7',
}
PATCHED_AGA = {
    'KARATE': 'cda42906a3b18cfcd1842b229b3d55c4d282b1249f4c1d1dd8f0fd325fb5c1e7',
    'TITLE': '8d7598e5e5ca68ec5b23ce3dec94c20bf84fd6d1addabb0926cb3509c9c65b12',
    'HISCORE': 'aa3723d79865f263e0c133b2f14eab1c9c087800cd74d0ac5415f738bc925c04',
}

def sha(path):
    return hashlib.sha256(open(path, 'rb').read()).hexdigest()

def find(gamedir, name):
    """case-insensitive lookup (Amiga file systems are case-insensitive)"""
    for f in os.listdir(gamedir):
        if f.lower() == name.lower():
            return os.path.join(gamedir, f)
    return None

def strip_relocs(h, ranges):
    h['relocs'] = [(t, o) for t, o in h['relocs'] if not any(a - 3 <= o < b for a, b in ranges)]

LAYOUT = {l.split()[0]: int(l.split()[1]) for l in open(os.path.join(HERE, 'patches', 'layout.txt'))}

def bsr_at(c, at, target, length, op=0x6100):
    c[at:at + length] = struct.pack('>Hh', op, target - (at + 2)) + b'\x4e\x71' * ((length - 4) // 2)

def add_shellfix(h, name, dmaoff, keyhook=None, firehook=None):
    """AGA register reset, relocated-VBR fix and Amiga+Q (patches/shellfix.s),
    appended to the code hunk; hooks into the start-up code shared by all
    programs and (TITLE, HISCORE) into the keyboard interrupt."""
    c = h[0]['data']
    c += b'\0' * ((-len(c)) % 4)
    org = len(c)
    assert org == LAYOUT[name], 'shellfix ORG'
    fix = open(os.path.join(HERE, 'patches', f'shellfix_{name}.bin'), 'rb').read()
    for at in (dmaoff, 0x5e, 0x7e):
        assert c[at:at + 2] in (b'\x23\xfc', b'\x3d\x7c'), 'unexpected code at %x' % at
    bsr_at(c, dmaoff, org + 0, 6)     # AgaReset   (move.w #$7fff,DMACON in the game)
    bsr_at(c, 0x5e, org + 4, 10)      # VbrEnter   (move.l #entry,$80.l)
    bsr_at(c, 0x7e, org + 8, 6)       # VbrLeave   (move.w #$7fff,DMACON after TRAP)
    rng = [(0x5e, 0x68), (0x7e, 0x84), (dmaoff, dmaoff + 6)]
    if keyhook:                       # move.b d0,KEYVAR.l in the keyboard handler
        assert c[keyhook:keyhook + 2] == b'\x13\xc0'
        bsr_at(c, keyhook, org + 12, 6); rng.append((keyhook, keyhook + 6))
    if firehook:                      # btst #6,$bfe001 in the wait for fire
        assert c[firehook:firehook + 4] == b'\x08\x39\x00\x06'
        bsr_at(c, firehook, org + 16, 8); rng.append((firehook, firehook + 8))
    strip_relocs(h[0], rng)
    h[0]['data'] = c + bytearray(fix)

# ---------------------------------------------------------------- KARATE
def patch_karate(src, dst, aga=False):
    h = hunkio.read(src)
    code = h[0]['data']
    ORG = 0x4c00
    assert len(code) == ORG
    patch = open(os.path.join(HERE, 'patches', 'karate_patch_aga.bin' if aga else 'karate_patch.bin'), 'rb').read()
    rng = []
    def jmp(at, target, op=0x4efa):
        code[at:at + 4] = struct.pack('>Hh', op, target - (at + 2))
        rng.append((at, at + 4))
    for at, idx in ((0x460, 0), (0x47e, 1), (0x1058, 2), (0x12e4, 3), (0x16aa, 4), (0x17f2, 5), (0x1b88, 6)):
        jmp(at, ORG + 4 * idx)
    code[0x130c:0x130e] = b'\x4e\x75'; rng.append((0x130c, 0x130e))
    code[0x164:0x168] = b'\x4e\x71\x4e\x71'; rng.append((0x164, 0x168))
    jmp(0x1afe, ORG + 4 * 7, op=0x4eba)
    # computer opponent: player 1 joystick / fire through the patch
    assert code[0x1394:0x1398] == bytes.fromhex('302e5a88')
    jmp(0x1394, ORG + 4 * 8, op=0x6100)          # move.w JOY1DAT,d0 -> bsr P1Joy
    assert code[0x13ec:0x13f4] == bytes.fromhex('0839000700bfe001')
    jmp(0x13ec, ORG + 4 * 9, op=0x6100)          # btst #7,$bfe001 -> bsr P1Fire
    code[0x13f0:0x13f4] = b'\x4e\x71' * 2; rng.append((0x13ec, 0x13f4))
    # the game's blitter waits (shadow masks): read DMACONR once first
    for at in (0x1ab4, 0x1b22):
        assert code[at:at + 8] == bytes.fromhex('082e000e5a7e66f8')
        jmp(at, ORG + 4 * 10, op=0x6100)
        code[at + 4:at + 8] = b'\x4e\x71' * 2; rng.append((at, at + 8))
    code[0x1b02:0x1b08] = b'\x4e\x71' * 3; rng.append((0x1afe, 0x1b08))
    code[0x4ec:0x4f0] = b'.k16'
    strip_relocs(h[0], rng)
    h[0]['data'] = code + bytearray(patch)
    add_shellfix(h, 'karate_aga' if aga else 'karate', 0x178)
    hunkio.write(dst, h)

# ---------------------------------------------------------------- TITLE
def patch_title(src, dst, aga=False):
    # .bg file (header [+ AGA palette] + 352 x 236 picture), copper, start-up screen (640 x 200 x 2)
    BUFSIZE = (128 + 512 + 236 * 44 * 8 if aga else 128 + 236 * 44 * 6) + 64 + 512 + 32000 + 256
    h = hunkio.read(src); c = h[0]['data']; ORG = len(c); assert ORG == 0x3808
    patch = open(os.path.join(HERE, 'patches', 'title_patch_aga.bin' if aga else 'title_patch.bin'), 'rb').read()
    rng = []
    for at in (0x2440, 0x2466):
        c[at:at + 4] = struct.pack('>I', BUFSIZE)
    c[0x2482:0x2482 + 19] = b'karatedat:title.bg\0'
    c[0x8f0:0x8f4] = struct.pack('>Hh', 0x4efa, ORG - (0x8f0 + 2)); rng.append((0x8f0, 0x8f4))
    assert c[0x20a:0x20e] == bytes.fromhex('123a234a')   # move.b KEYVAR(pc),d1
    c[0x20a:0x20e] = struct.pack('>Hh', 0x6100, ORG + 4 - (0x20a + 2)); rng.append((0x20a, 0x20e))
    c[0x70e:0x710] = b'\x4e\x75'; rng.append((0x70e, 0x710))
    strip_relocs(h[0], rng)
    h[0]['data'] = c + bytearray(patch)
    add_shellfix(h, 'title_aga' if aga else 'title', 0x178, keyhook=0x2544)
    hunkio.write(dst, h)

# ---------------------------------------------------------------- HISCORE
def patch_hiscore(src, dst, aga=False):
    """The high score screen showed an OpalVision picture (hscore.dat) under
    the text: now hscore.bg is loaded and shown with the text laid over it
    (patches/hiscore_patch.s)."""
    h = hunkio.read(src); c = h[0]['data']; rng = []
    org = len(c); assert org == 10908
    name = 'hiscore_aga' if aga else 'hiscore'
    patch = open(os.path.join(HERE, 'patches', name.replace('hiscore', 'hiscore_patch') + '.bin'), 'rb').read()
    # buffer for the picture, the displayed bitmap and our copper list
    bufsize = (640 + 2 * 236 * 352 if aga else 128 + 2 * 236 * 264) + 512
    for at in (0x2926, 0x294c):
        assert c[at:at + 4] == struct.pack('>I', 0x7f380)
        c[at:at + 4] = struct.pack('>I', bufsize)
    assert c[0x2968:0x297d] == b'karatedat:hscore.dat\0'
    c[0x2968:0x297c] = b'karatedat:hscore.bg\0'
    c[0x20e:0x212] = b'\x4e\x71\x4e\x71'; rng.append((0x20e, 0x212))   # OpalVision display
    # move.w #$87f0,DMACON -> bsr HsInit (sprite DMA stays off: the game
    # never sets the sprite pointers - random memory showed as blocks)
    assert c[0x200:0x206] == bytes.fromhex('3d7c87f05b12')
    bsr_at(c, 0x200, org + 0, 6); rng.append((0x200, 0x206))
    # end of the text routine: move.l d0,$450(a5) / rts -> bra HsText
    assert c[0x4de:0x4e4] == bytes.fromhex('2b4004504e75')
    bsr_at(c, 0x4de, org + 4, 6, op=0x6000); rng.append((0x4de, 0x4e4))
    # name entry key read -> HsKey (the computer types AMIGA when it won)
    assert c[0x370:0x374] == bytes.fromhex('123a26c8')
    strip_relocs(h[0], rng)
    h[0]['data'] = c + bytearray(patch)
    add_shellfix(h, name, 0x17e, keyhook=0x2a28, firehook=0x226)
    c = h[0]['data']
    sfix = LAYOUT[name]
    c[0x370:0x374] = struct.pack('>Hh', 0x6100, sfix + 20 - (0x370 + 2))
    hunkio.write(dst, h)

# ---------------------------------------------------------------- loader
def patch_loader(src, dst):
    h = hunkio.read(src); c = h[0]['data']
    c[0x4c:0x50] = struct.pack('>I', 0x2c000)   # chip memory check
    org = len(c); assert org == LAYOUT['loader']
    bsr_at(c, 0x00, org + 0, 4)       # clear quit flag at start
    bsr_at(c, 0x88, org + 4, 4, op=0x6000)  # after each program: quit?
    bsr_at(c, 0xd6, org + 8, 4)       # save Workbench colours
    h[0]['data'] = c + bytearray(open(os.path.join(HERE, 'patches', 'loaderfix.bin'), 'rb').read())
    hunkio.write(dst, h)

# ---------------------------------------------------------------- animframes
def remap_anim(karate, src, dst):
    code = hunkio.read(karate)[0]['data']
    anim = bytearray(open(src, 'rb').read())
    regions = set()
    for i in range(56):
        e = 0x4420 + 0x24 * i
        size, dmod, smod, stride = struct.unpack('>4H', code[e:e + 8])
        for half in (0, 1):
            s = struct.unpack('>I', code[e + 8 + 12 * half:e + 12 + 12 * half])[0]
            regions.add((s, size >> 6, stride))
    lut = np.array(REMAP, np.uint8)
    for s, h, stride in regions:
        n = h * stride * 4
        blk = np.frombuffer(bytes(anim[s:s + n]), np.uint8).reshape(h, 4, stride)
        bits = np.unpackbits(blk, axis=2)
        val = bits[:, 0] | (bits[:, 1] << 1) | (bits[:, 2] << 2) | (bits[:, 3] << 3)
        nv = lut[val]
        out = np.stack([(nv >> p) & 1 for p in range(4)], 1).astype(np.uint8)
        anim[s:s + n] = np.packbits(out, axis=2).tobytes()
    open(dst, 'wb').write(anim)

# ---------------------------------------------------------------- graphics
def convert_stage(gamedir, stage, mode, dst):
    fixed = regs16(BEACH if stage == 'beach' else DEF)
    img = bgconv.load_panorama(gamedir, stage)[bgconv.ROW0:bgconv.ROW0 + bgconv.NROWS]
    st = bgconv.load_stencil(gamedir, stage)
    data, regs, idx = bgconv.build(img, fixed, mode, hud=True, stencil=st)
    open(dst, 'wb').write(data)

# colours 0-15 of the high score screen (its copper list; colour 0 = border
# made black - the text never uses it); colour 1 gets a
# gradient from the copper, so the picture must not use it
HISCORE_PAL = [0x000, 0xfff, 0xaaa, 0xaaa, 0x888, 0x555, 0x333, 0x000,
               0x0f0, 0x00f, 0xf0f, 0xf0f, 0xf0f, 0xf0f, 0xf0f, 0xf0f]

def convert_hiscore(datfile, mode, dst):
    img = bgconv.load_single(datfile)[:, 4:356]
    pens = {0: [1, 33], 1: [1], 2: [1, 129]}[mode]
    data, regs, idx = bgconv.build(img, HISCORE_PAL, mode, x0=0, width=352,
                                   excl=(range(img.shape[0]), pens))
    open(dst, 'wb').write(data)

def convert_title(datfile, mode, dst):
    img = bgconv.load_single(datfile)[:, 4:356]
    data, regs, idx = bgconv.build(img, [0x000], mode, x0=0, width=352)
    open(dst, 'wb').write(data)

# ---------------------------------------------------------------- start script
START_SCRIPT = """; King of Karate - Chipset patch v1.0 start script
; (game mode and level are chosen on the title screen)
Assign >NIL: karatedat: ""
loader.exe
"""

# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('gamedir', help='directory with the original King of Karate files')
    ap.add_argument('outdir', help='where to write the patched game')
    ap.add_argument('--mode', choices=('ehb', 'ham', 'aga'), default='ehb',
                    help='fight backgrounds: ehb, ham (OCS/ECS/AGA) or aga (256 colours, A1200/A4000/CD32 only; default ehb)')
    ap.add_argument('--title-mode', choices=('ehb', 'ham', 'aga'), help='title screen (default = --mode)')
    ap.add_argument('--force', action='store_true', help='patch even if checksums differ')
    a = ap.parse_args()
    tmode = a.title_mode or a.mode
    if tmode == 'aga' and a.mode != 'aga':
        sys.exit('--title-mode aga needs --mode aga (AGA machines only)')
    if not os.path.isdir(a.gamedir):
        sys.exit(f'Not a directory: {a.gamedir}')
    if os.path.abspath(a.gamedir) == os.path.abspath(a.outdir):
        sys.exit('The output directory must be different from the original game directory.')
    m = {'ehb': 0, 'ham': 1, 'aga': 2}

    # 1. check the original files
    print('Checking original files...')
    files = {}
    bad = []
    for name, digest in ORIGINAL.items():
        p = find(a.gamedir, name)
        if not p:
            bad.append(f'  missing: {name}')
            continue
        files[name] = p
        if sha(p) != digest:
            bad.append(f'  different version: {name}')
    if bad:
        print('\n'.join(bad))
        if any('missing' in b for b in bad) or not a.force:
            sys.exit('Stopped. (use --force to try a different version anyway)')

    # 2. copy the whole game, then replace/add files
    os.makedirs(a.outdir, exist_ok=True)
    for f in os.listdir(a.gamedir):
        src = os.path.join(a.gamedir, f)
        if os.path.isfile(src):
            shutil.copy2(src, os.path.join(a.outdir, f))
    out = lambda n: os.path.join(a.outdir, n)

    print('Patching executables...')
    patch_karate(files['KARATE'], out(os.path.basename(files['KARATE'])), aga=a.mode == 'aga')
    patch_title(files['TITLE'], out(os.path.basename(files['TITLE'])), aga=tmode == 'aga')
    patch_hiscore(files['HISCORE'], out(os.path.basename(files['HISCORE'])), aga=tmode == 'aga')
    patch_loader(files['loader.exe'], out(os.path.basename(files['loader.exe'])))
    with open(out('KingOfKarate'), 'w', newline='\n') as f:
        f.write(START_SCRIPT)

    print('Remapping fighter colours (animframes.k16)...')
    remap_anim(files['KARATE'], files['animframes.dat'], out('animframes.k16'))

    for st in ('house', 'lview', 'beach'):
        print(f'Converting {st} background ({a.mode.upper()}) - this takes a few seconds...')
        convert_stage(a.gamedir, st, m[a.mode], out(f'{st}.bg'))
    print(f'Converting title screen ({tmode.upper()})...')
    convert_title(files['titles.dat'], m[tmode], out('title.bg'))
    print(f'Converting high score screen ({tmode.upper()})...')
    convert_hiscore(files['hscore.dat'], m[tmode], out('hscore.bg'))

    # 3. verify executables against the tested build
    ref = dict(PATCHED)
    if a.mode == 'aga': ref['KARATE'] = PATCHED_AGA['KARATE']
    if tmode == 'aga':
        ref['TITLE'] = PATCHED_AGA['TITLE']; ref['HISCORE'] = PATCHED_AGA.get('HISCORE', '')
    for name, digest in ref.items():
        if digest and sha(out(os.path.basename(files[name]))) != digest:
            print(f'WARNING: {name} differs from the reference build of this release')
    print(f'\nDone. Copy "{a.outdir}" to your Amiga and start the KingOfKarate icon')
    print('(or: cd <dir>  Execute KingOfKarate).')
    print('opal.library is not needed by this version.')

if __name__ == '__main__':
    main()
