"""Fighter palette reduction: 31 colours (2 x 15) -> 16 registers.

New index layout (same pixels for both fighters):
  0        black (border / background base)
  1..7     skin + belt (shared by both fighters), from old 8..14
  8..11    fighter 1 gi shades
  12..15   fighter 2 gi shades  (= fighter-1 index | 4, done by an OR blit)
"""
import itertools, numpy as np
DEF=[0x000,0xeee,0xddd,0xccc,0xbbb,0xaaa,0xa98,0xa86,0xb74,0xa63,0x952,0x841,0x620,0x310,0x000,0xfff,
     0x333,0xf00,0xe00,0xd00,0xb00,0xa00,0x900,0x800,0x632,0x521,0x421,0x310,0x210,0x200,0x100,0xf05]
BEACH=[0x000,0xfee,0xeed,0xedc,0xdcb,0xca9,0xda8,0xb97,0xc85,0xc74,0xa73,0x952,0x731,0x421,0x321,0xfff,
       0x555,0xeef,0xdde,0xcce,0xbbc,0xa9a,0xa99,0xb97,0xc83,0xb73,0xb62,0x941,0x820,0x310,0x000,0xfff]
COUNTS=[0,24428,26528,30272,34206,40554,46644,46456,35216,28546,15808,15208,14912,9460,19028,22742]
GI=[15,1,2,3,4,5,6,7]           # light -> dark
SKIN=[8,9,10,11,12,13,14]
def rgb(c): return np.array([(c>>8)&15,(c>>4)&15,c&15],float)
def toamiga(v): v=np.clip(np.round(v),0,15).astype(int); return (v[0]<<8)|(v[1]<<4)|v[2]

def best_gi_partition(pals):
    best=None
    for cuts in itertools.combinations(range(1,8),3):
        groups=[GI[a:b] for a,b in zip((0,)+cuts,cuts+(8,))]
        err=0
        for pal in pals:
            for base in (0,16):
                for g in groups:
                    w=np.array([COUNTS[i] for i in g],float)
                    cols=np.array([rgb(pal[base+i]) for i in g])
                    mean=(cols*w[:,None]).sum(0)/w.sum()
                    err+=(w*((cols-mean)**2).sum(1)).sum()
        if best is None or err<best[0]: best=(err,groups)
    return best[1]

GROUPS=best_gi_partition([DEF,BEACH])
REMAP=[0]*16
for k,g in enumerate(GROUPS):
    for i in g: REMAP[i]=8+k
for k,i in enumerate(SKIN): REMAP[i]=1+k

def regs16(pal):
    """16 register values for a stage palette (old 32-entry list)."""
    out=[0]*16
    for k,g in enumerate(GROUPS):
        w=np.array([COUNTS[i] for i in g],float)
        for base,dst in ((0,8+k),(16,12+k)):
            cols=np.array([rgb(pal[base+i]) for i in g])
            out[dst]=toamiga((cols*w[:,None]).sum(0)/w.sum())
    for k,i in enumerate(SKIN):
        out[1+k]=toamiga((rgb(pal[i])+rgb(pal[16+i]))/2)
    out[0]=0x000
    return out

if __name__=='__main__':
    print('gi groups',GROUPS)
    print('remap',REMAP)
    print('default',[f'{c:03x}' for c in regs16(DEF)])
    print('beach  ',[f'{c:03x}' for c in regs16(BEACH)])
