"""Minimal AmigaDOS hunk reader/writer (code/data/bss + reloc32)."""
import struct
def read(path):
    d=open(path,'rb').read(); p=0
    def L():
        nonlocal p; v=struct.unpack('>I',d[p:p+4])[0]; p+=4; return v
    assert L()==0x3f3
    while L(): pass
    n=L(); first=L(); last=L()
    sizes=[L() for _ in range(last-first+1)]
    hunks=[]; cur=None
    while p<len(d):
        t=L()&0x3fffffff
        if t in (0x3e9,0x3ea):
            nl=L(); cur={'type':t,'data':bytearray(d[p:p+nl*4]),'relocs':[]}; p+=nl*4; hunks.append(cur)
        elif t==0x3eb:
            nl=L(); cur={'type':t,'data':bytearray(nl*4),'relocs':[]}; hunks.append(cur)
        elif t==0x3ec:
            while True:
                c=L()
                if c==0: break
                h=L(); cur['relocs']+=[(h,L()) for _ in range(c)]
        elif t==0x3f2: pass
        else: raise Exception('hunk type %x'%t)
    for h,s in zip(hunks,sizes): h['memflags']=s>>30
    return hunks
def write(path,hunks):
    o=bytearray()
    def L(v): o.extend(struct.pack('>I',v))
    L(0x3f3); L(0); L(len(hunks)); L(0); L(len(hunks)-1)
    for h in hunks:
        h['data']+=b'\0'*((-len(h['data']))%4)
        L((len(h['data'])//4)|(h['memflags']<<30))
    for h in hunks:
        L(h['type']); L(len(h['data'])//4)
        if h['type']!=0x3eb: o.extend(h['data'])
        if h['relocs']:
            L(0x3ec)
            for tgt in sorted(set(t for t,_ in h['relocs'])):
                offs=sorted(off for t,off in h['relocs'] if t==tgt)
                L(len(offs)); L(tgt)
                for off in offs: L(off)
            L(0)
        L(0x3f2)
    open(path,'wb').write(o)
