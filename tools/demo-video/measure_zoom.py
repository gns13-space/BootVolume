import sys, numpy as np
from PIL import Image
FR=sys.argv.pop(1)  # 회색조 프레임 폴더(ffmpeg -vf format=gray %03d.png)
W,H=1920,1242; SW=320; SH=int(H*SW/W)
def load(i): return Image.open(f'{FR}/{i:03d}.png')
def small(im): return np.asarray(im.resize((SW,SH),Image.BILINEAR),dtype=np.float32)
def view(ref,z,ax,ay):
    w,h=W/z,H/z; x0=(W-w)*ax; y0=(H-h)*ay
    return np.asarray(ref.transform((SW,SH),Image.EXTENT,(x0,y0,x0+w,y0+h),Image.BILINEAR),dtype=np.float32)
def fit(fr,ref,anchors):
    s=small(fr); best=None
    for ax,ay in anchors:
        for z in np.arange(1.0,2.45,0.02):
            e=np.mean(np.abs(view(ref,z,ax,ay)-s))
            if best is None or e<best[0]: best=(e,z,ax,ay)
    e,z0,ax,ay=best
    for z in np.arange(z0-0.02,z0+0.02,0.002):
        e=np.mean(np.abs(view(ref,z,ax,ay)-s))
        if e<best[0]: best=(e,z,ax,ay)
    return best
ref=load(int(sys.argv[1])); frames=range(int(sys.argv[2]),int(sys.argv[3]))
anch=[(a/4,b/4) for a in range(5) for b in range(5)] if len(sys.argv)>4 else [(1,0)]
for i in frames:
    e,z,ax,ay=fit(load(i),ref,anch); print(f'{(i-1)/30:6.3f} z={z:.3f} ax={ax:.2f} ay={ay:.2f} err={e:.2f}')
