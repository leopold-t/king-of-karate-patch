#!/usr/bin/env python3
"""Convert OpalVision 24-bit backgrounds to Amiga EHB / HAM6 panoramas.

Output file (.bg):
  0   'KBG1'
  4   mode.w   0 = EHB, 1 = HAM6, 2 = AGA (8 planes, 256 colours)
  6   width.w  (pixels, 768)   8 height.w   10 rowbytes.w (576)
  12  32 x palette words (COLOR00..31)
  76  mask_row0.w, mask_rows.w   foreground stencil (0 rows = none)
  80  rects.w, then up to 4 x (row, rows, byte column, words): where the
      stencil is set (the patch only redraws the foreground there)
  ..  pad to 128
  128 bitmap: height rows x 6 planes interleaved x width/8 bytes
      AGA: 128 colours as longs $00RRGGBB first (colours 128-255 are
      the same at half brightness), bitmap at 640 with 8 planes
  ... stencil: mask_rows x width/8 bytes (1 = in front of the fighters)
Panorama pixel x (0..719) is stored at bitmap x = x + PANO_X0.
"""
import sys, struct, numpy as np
from .opal import decode as _decode
def decode(path, **kw): return _decode(path)

W_BM = 864          # bitmap width in pixels
PANO_X0 = 80        # left margin
PANO_W = 720
H = 236
ROW0 = 0            # the whole image is stored
NROWS = 236
HUD_ROWS = range(18, 47)  # image rows behind the energy bars: pens 1-3 are
HUD_PENS = (1, 2, 3)      # recoloured there by the copper (HUD gradients)
ROWBYTES = 6 * (W_BM // 8)

def load_panorama(datdir, stage):
    a = decode(f'{datdir}/{stage}1.dat', layout='planar', hires=True)[:, 16:]
    b = decode(f'{datdir}/{stage}2.dat', layout='planar', hires=True)[:, 16:]
    hi = np.concatenate([a, b], 1).astype(np.float64)       # 1440 x 236 hires
    lo = (hi[:, 0::2] + hi[:, 1::2]) / 2                    # 720 lores
    return lo                                               # 0..255

def load_stencil(datdir, stage):
    """OpalVision priority stencil: lowest bit of blue. Only images that use
    it have it mostly clear (France/house); elsewhere it is image noise."""
    m = []
    for k in (1, 2):
        a = decode(f'{datdir}/{stage}{k}.dat')[:, 16:]
        m.append(a[:, :, 2] & 1)
    m = np.concatenate(m, 1).astype(bool)                 # 1440 x 236 hires
    if m.mean() > 0.2:
        return None
    return m[:, 0::2] | m[:, 1::2]                        # 720 lores

def load_single(datfile):
    a = decode(datfile, layout='planar', hires=True)[:, 16:].astype(np.float64)
    return (a[:, 0::2] + a[:, 1::2]) / 2                    # 360 x 236

def a12(c):  # amiga 12-bit -> 0..255 rgb
    return np.array([(c >> 8 & 15) * 17, (c >> 4 & 15) * 17, (c & 15) * 17], np.float64)

def half(c):
    return ((c >> 9 & 7) << 8) | ((c >> 5 & 7) << 4) | (c >> 1 & 7)

def to12(v):
    v = np.clip(np.round(np.asarray(v) / 17.0), 0, 15).astype(int)
    return (v[0] << 8) | (v[1] << 4) | v[2]

# perceptual-ish weights
WGT = np.array([0.30, 0.59, 0.11]) ** 0.5 * 1.7

def nearest(pix, pal):
    d = (((pix[:, None, :] - pal[None, :, :]) * WGT) ** 2).sum(2)
    return d.argmin(1)

def ehb_palette(img, fixed16, iters=12, seed=1):
    """fixed16: fixed regs at the start (fighters). Optimise the rest of 32."""
    nfree = 32 - len(fixed16)
    pix = img.reshape(-1, 3)
    rng = np.random.default_rng(seed)
    sample = pix[rng.choice(len(pix), min(60000, len(pix)), replace=False)]
    # init free regs with k-means++ style spread
    free = [sample[rng.integers(len(sample))]]
    for _ in range(nfree - 1):
        d = np.min([((sample - f) ** 2).sum(1) for f in free], 0)
        free.append(sample[rng.choice(len(sample), p=d / d.sum())])
    free = [to12(f) for f in free]
    for _ in range(iters):
        regs = list(fixed16) + free
        pal = np.array([a12(c) for c in regs] + [a12(half(c)) for c in regs])
        idx = nearest(sample, pal)
        new = []
        nf = len(fixed16)
        for j in range(nfree):
            r = nf + j
            sel_full = sample[idx == r]
            sel_half = sample[idx == r + 32] * 2.0
            pts = np.concatenate([sel_full, sel_half]) if len(sel_half) else sel_full
            if len(pts) == 0:
                # re-seed on worst pixel
                err = (((sample - pal[idx]) * WGT) ** 2).sum(1)
                new.append(to12(sample[err.argmax()]))
            else:
                new.append(to12(np.clip(pts.mean(0), 0, 255)))
        if new == free: break
        free = new
    return list(fixed16) + free

def dither(img, pal_rgb, strength=0.75, excl_rows=(), excl_idx=()):
    """Floyd-Steinberg error diffusion to palette indices (serpentine).
    Rows in excl_rows never use the palette indices in excl_idx."""
    h, w, _ = img.shape
    work = img.copy()
    out = np.zeros((h, w), np.int32)
    for y in range(h):
        rng = range(w) if y % 2 == 0 else range(w - 1, -1, -1)
        dirn = 1 if y % 2 == 0 else -1
        for x in rng:
            p = np.clip(work[y, x], 0, 255)
            d = (((pal_rgb - p) * WGT) ** 2).sum(1)
            if y in excl_rows: d[list(excl_idx)] = np.inf
            k = int(d.argmin())
            out[y, x] = k
            e = (p - pal_rgb[k]) * strength
            xn = x + dirn
            if 0 <= xn < w: work[y, xn] += e * 7 / 16
            if y + 1 < h:
                xp = x - dirn
                if 0 <= xp < w: work[y + 1, xp] += e * 3 / 16
                work[y + 1, x] += e * 5 / 16
                if 0 <= xn < w: work[y + 1, xn] += e * 1 / 16
    return out

def ham_encode(img, base16, maxage=3, excl_rows=(), excl_idx=()):
    """Greedy HAM6 encoding with error diffusion.
    Every colour channel is refreshed (modify or base colour) at least
    every `maxage`+1 pixels, so HAM fringes (left screen edge, right of
    the fighters) are at most a few pixels long."""
    h, w, _ = img.shape
    base = np.array([a12(c) for c in base16])
    out = np.zeros((h, w), np.int32)
    work = img.copy()
    for y in range(h):
        prev = a12(base16[0])
        age = [0, 0, 0]
        for x in range(w):
            p = np.clip(work[y, x], 0, 255)
            cands = []
            d = (((base - p) * WGT) ** 2).sum(1)
            if y in excl_rows: d[list(excl_idx)] = np.inf
            k = int(d.argmin()); cands.append((d[k], k, base[k], (0, 0, 0)))
            q = np.clip(np.round(p / 17), 0, 15)
            for ctl, ch in ((2, 0), (3, 1), (1, 2)):      # R, G, B modify
                na = [a + 1 for a in age]; na[ch] = 0
                if max(na) > maxage:
                    continue
                c = prev.copy(); c[ch] = q[ch] * 17
                dd = (((c - p) * WGT) ** 2).sum()
                cands.append((dd, (ctl << 4) | int(q[ch]), c, tuple(na)))
            dbest, code, col, na = min(cands, key=lambda t: t[0])
            out[y, x] = code
            prev = col
            age = list(na)
            e = (p - col) * 0.5
            if x + 1 < w: work[y, x + 1] += e * 7 / 16
            if y + 1 < h:
                if x > 0: work[y + 1, x - 1] += e * 3 / 16
                work[y + 1, x] += e * 5 / 16
                if x + 1 < w: work[y + 1, x + 1] += e * 1 / 16
    return out

def planes_interleaved(idx6, width_px, x0, nplanes=6):
    """idx6: (h, w) pixel values -> bytes, planes interleaved, bitmap width width_px."""
    h, w = idx6.shape
    full = np.zeros((h, width_px), np.int32)
    full[:, x0:x0 + w] = idx6
    out = bytearray()
    for y in range(h):
        for p in range(nplanes):
            bits = ((full[y] >> p) & 1).astype(np.uint8)
            out += np.packbits(bits).tobytes()
    return bytes(out)

def render(idx6, regs, mode):
    regs = list(regs)
    if mode == 2:
        return aga_rgb(regs)[idx6].astype(np.uint8)
    if mode == 0:
        pal = np.array([a12(c) for c in regs] + [a12(half(c)) for c in regs])
        return pal[idx6].astype(np.uint8)
    # HAM
    h, w = idx6.shape
    out = np.zeros((h, w, 3))
    base = np.array([a12(c) for c in regs[:16]])
    for y in range(h):
        prev = base[0].copy()
        for x in range(w):
            v = idx6[y, x]; ctl, dat = v >> 4, v & 15
            if ctl == 0: prev = base[dat].copy()
            elif ctl == 1: prev[2] = dat * 17
            elif ctl == 2: prev[0] = dat * 17
            else: prev[1] = dat * 17
            out[y, x] = prev
    return out.astype(np.uint8)

# ---------------- AGA: 128 colours (24 bit) + half brightness copies
def rgb24(c):
    return np.array([c >> 16 & 255, c >> 8 & 255, c & 255], np.float64)

def half24(c):
    return (c >> 1) & 0x7f7f7f

def to24(v):
    v = np.clip(np.round(np.asarray(v)), 0, 255).astype(int)
    return (int(v[0]) << 16) | (int(v[1]) << 8) | int(v[2])

def aga_rgb(regs128):
    return np.array([rgb24(c) for c in regs128] + [rgb24(half24(c)) for c in regs128])

def aga_palette(img, fixed16, iters=14, seed=1):
    """fixed16: 12 bit fighter colours (0-15). Optimise colours 16-127;
    128-255 are colours 0-127 at half brightness (shadow plane)."""
    fixed = [(((c >> 8 & 15) * 17) << 16) | (((c >> 4 & 15) * 17) << 8) | ((c & 15) * 17) for c in fixed16]
    nfree = 128 - len(fixed)
    pix = img.reshape(-1, 3)
    rng = np.random.default_rng(seed)
    sample = pix[rng.choice(len(pix), min(60000, len(pix)), replace=False)]
    free = [sample[rng.integers(len(sample))]]
    dmin = ((sample - free[0]) ** 2).sum(1)
    for _ in range(nfree - 1):
        f = sample[rng.choice(len(sample), p=dmin / dmin.sum())]
        free.append(f)
        dmin = np.minimum(dmin, ((sample - f) ** 2).sum(1))
    free = [to24(f) for f in free]
    nf = len(fixed)
    for _ in range(iters):
        regs = fixed + free
        pal = aga_rgb(regs)
        idx = nearest_chunked(sample, pal)
        new = []
        for j in range(nfree):
            r = nf + j
            pts = np.concatenate([sample[idx == r], sample[idx == r + 128] * 2.0])
            if len(pts) == 0:
                err = (((sample - pal[idx]) * WGT) ** 2).sum(1)
                new.append(to24(sample[err.argmax()]))
            else:
                new.append(to24(np.clip(pts.mean(0), 0, 255)))
        if new == free: break
        free = new
    return fixed + free

def nearest_chunked(pix, pal, n=8000):
    return np.concatenate([nearest(pix[i:i + n], pal) for i in range(0, len(pix), n)])

def dither_fast(img, pal_rgb, strength=0.5, excl_rows=(), excl_idx=()):
    """Error diffusion (row by row, vectorised): error goes to the next
    row only, which is enough with 240 colours and much faster."""
    h, w, _ = img.shape
    out = np.zeros((h, w), np.int32)
    carry = np.zeros((w, 3))
    pal_ok = pal_rgb.copy()
    for y in range(h):
        row = np.clip(img[y] + carry, 0, 255)
        if y in excl_rows:
            p = pal_rgb.copy(); p[list(excl_idx)] = 1e9
        else:
            p = pal_ok
        k = nearest(row, p)
        out[y] = k
        e = (row - pal_rgb[k]) * strength
        carry = e * 0.5
        carry[1:] += e[:-1] * 0.25
        carry[:-1] += e[1:] * 0.25
    return out

def kmeans16(img, iters=15, seed=2):
    pix = img.reshape(-1, 3)
    rng = np.random.default_rng(seed)
    sample = pix[rng.choice(len(pix), min(40000, len(pix)), replace=False)]
    cent = sample[rng.choice(len(sample), 16, replace=False)].copy()
    for _ in range(iters):
        idx = nearest(sample, cent)
        for j in range(16):
            sel = sample[idx == j]
            if len(sel): cent[j] = sel.mean(0)
    return [to12(c) for c in cent]

def build(img, fixed16, mode, x0=PANO_X0, width=W_BM, hud=False, stencil=None, excl=None):
    """hud: keep pens 1-3 out of the rows behind the energy bars.
    stencil: (rows, w) bool foreground mask, stored after the bitmap."""
    xr = HUD_ROWS if hud else ()
    if excl:                   # (rows, palette indices) that must not be used
        xr = set(excl[0])
        xpens = list(excl[1])
    else:
        xpens = None
    nplanes = 6
    if mode == 2:
        nplanes = 8
        regs = aga_palette(img, fixed16)
        pal = aga_rgb(regs)
        idx = dither_fast(img, pal, excl_rows=xr, excl_idx=xpens or (list(HUD_PENS) + [i + 128 for i in HUD_PENS]))
    elif mode == 0:
        regs = ehb_palette(img, fixed16)
        pal = np.array([a12(c) for c in regs] + [a12(half(c)) for c in regs])
        idx = dither(img, pal, excl_rows=xr, excl_idx=xpens or (list(HUD_PENS) + [i + 32 for i in HUD_PENS]))
    else:
        base = list(fixed16) if len(fixed16) >= 16 else (list(fixed16) + kmeans16(img))[:16]
        regs = base + [0] * 16
        idx = ham_encode(img, base, excl_rows=xr, excl_idx=xpens or HUD_PENS)
    m0 = mrows = 0
    rects = []
    tail = b''
    if stencil is not None and stencil.any():
        ys = np.nonzero(stencil.any(1))[0]
        m0, m1 = int(ys.min()), int(ys.max()) + 1
        mrows = m1 - m0
        full = np.zeros((mrows, width), np.uint8)
        full[:, x0:x0 + stencil.shape[1]] = stencil[m0:m1]
        tail = np.packbits(full, axis=1).tobytes()
        # column segments (16-pixel words) that contain stencil pixels
        wcols = full.reshape(mrows, -1, 16).any(2)          # rows x words
        used = wcols.any(0)
        w = 0
        while w < len(used):
            if not used[w]:
                w += 1; continue
            e = w
            while e < len(used) and used[e]: e += 1
            rs = np.nonzero(wcols[:, w:e].any(1))[0]
            rects.append((m0 + int(rs.min()), int(rs.max() - rs.min() + 1), 2 * w, e - w))
            w = e
        assert len(rects) <= 4, rects
    hdr = b'KBG1' + struct.pack('>HHHH', mode, width, img.shape[0], nplanes * width // 8)
    if mode == 2:
        hdr += struct.pack('>32H', *[((c >> 20 & 15) << 8) | ((c >> 12 & 15) << 4) | (c >> 4 & 15) for c in regs[:32]])
    else:
        hdr += struct.pack('>32H', *regs)
    hdr += struct.pack('>HH', m0, mrows)
    hdr += struct.pack('>H', len(rects)) + b''.join(struct.pack('>4H', *r) for r in rects)
    hdr = hdr.ljust(128, b'\0')
    if mode == 2:
        hdr += struct.pack('>128I', *regs)
    return hdr + planes_interleaved(idx, width, x0, nplanes) + tail, regs, idx

