"""Decoder for OpalVision 24-bit framestore dumps (King of Karate *.dat).
24 planes, 92 bytes per line, 236 lines, hires 736 pixels: planes 0-11 hold
even pixels, 12-23 odd pixels; each colour component is spread over 4 planes,
2 bits per pixel (see opal.library WritePixel24)."""
import numpy as np
W_BYTES, H, NPL = 92, 236, 24
def decode(path):
    d = np.frombuffer(open(path, 'rb').read(), np.uint8)
    P = d[:NPL * W_BYTES * H].reshape(NPL, H, W_BYTES)
    def comp(planes):
        v = np.zeros((H, W_BYTES * 4), np.uint16)
        for k in range(4):
            pl = planes[k]
            hi = np.stack([(pl >> (7 - 2 * p)) & 1 for p in range(4)], -1).reshape(H, -1)
            lo = np.stack([(pl >> (6 - 2 * p)) & 1 for p in range(4)], -1).reshape(H, -1)
            v |= lo << k
            v |= hi << (k + 4)
        return v.astype(np.uint8)
    def rgb(base):
        return np.stack([comp(P[base + 4 * c:base + 4 * c + 4]) for c in range(3)], -1)
    img = np.zeros((H, W_BYTES * 8, 3), np.uint8)
    img[:, 0::2] = rgb(0)
    img[:, 1::2] = rgb(12)
    return img
