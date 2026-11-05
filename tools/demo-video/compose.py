import sys, subprocess, math
from PIL import Image, ImageDraw
R=sys.argv[1]; out=sys.argv[2]
SW,SH=3420,2214; OW,OH=1920,1242; FPS=30; S=2.0
# 화면 밖으로 민 터미널 창 귀퉁이(오른쪽 아래)를 바로 왼쪽 배경을 좌우로 뒤집어 덮는다. 배경이 실시간 렌더라 미리 찍은 조각은 밝기가 안 맞는다.
PATCH_SRC=(3160,1920,3290,2214); PATCH_AT=(3290,1920)
PATCH_MASK=Image.new('L',(130,294)); PATCH_MASK.putdata([min(255,round(255*y/60)) for y in range(294) for x in range(130)])
# 이전 HTML 장면과 같은 방식: transform-origin 0 0, translate(tx) scale(s) 를 같은 곡선으로 보간
# 키: (출력 시각, 배율, 화면 중심 x pt, 중심 y pt) — 중심은 화면 밖으로 안 나가게 맞춤
WIDE=(1.0,855,553.5); ICON=(2.0,1300,276); PANEL=(2.2,1320,252); HUD=(1.8,1300,308)
# 출력 시각은 저번과 같고, 원본 시각만 take4 의 같은 장면에 맞춤(패널 열림 3.55·끌기·저장 끝·음량 표시 18.1)
SEG=[(0.0,8.0,'v',24.2,32.2),(8.0,9.4,'v',32.2,38.9),(9.4,10.6,'v',38.9,40.1),(10.6,12.4,'v',40.1,40.1),
     (12.4,17.4,'boot',0,0),(17.4,21.0,'v',47.8,51.4)]
DUR=21.0
CAM=[(0.0,WIDE),(1.4,WIDE),(2.5,PANEL),(10.4,PANEL),(11.4,WIDE),
     (17.6,WIDE),(18.2,HUD),(19.4,HUD),(20.1,WIDE)]
def bez(x):  # cubic-bezier(.65,0,.35,1)
    lo,hi=0.0,1.0
    for _ in range(40):
        m=(lo+hi)/2; bx=3*(1-m)**2*m*.65+3*(1-m)*m*m*.35+m**3
        if bx<x: lo=m
        else: hi=m
    m=(lo+hi)/2; return 3*(1-m)*m*m+m**3
def tf(k):  # (배율, 중심) → (s, 왼쪽 위 tx, ty) — 화면 밖 안 나가게
    z,cx,cy=k; vw,vh=1710/z,1107/z
    cx=min(max(cx,vw/2),1710-vw/2); cy=min(max(cy,vh/2),1107-vh/2)
    return z,(cx-vw/2)*z,(cy-vh/2)*z
def cam(t):
    for (t0,a),(t1,b) in zip(CAM,CAM[1:]):
        if t0<=t<=t1:
            k=bez((t-t0)/(t1-t0)) if t1>t0 else 1
            sa,xa,ya=tf(a); sb,xb,yb=tf(b)
            s=sa+(sb-sa)*k; tx=xa+(xb-xa)*k; ty=ya+(yb-ya)*k
            vw,vh=1710/s,1107/s
            return s,tx/s+vw/2,ty/s+vh/2
    return CAM[-1][1]
def seg(t):
    for s in SEG:
        if s[0]<=t<s[1]: return s
    return SEG[-1]
logo=Image.open(f'{R}/applelogo.png'); lb=logo.getchannel('A').getbbox(); logo=logo.crop(lb)
lh=96; logo=logo.resize((round(logo.width*lh/logo.height),lh),Image.LANCZOS)
def boot_frame(bt, last, first):
    # bt: 0..5
    img=Image.new('RGB',(OW,OH),(0,0,0))
    if bt<0.5: return Image.blend(last,img,bt/0.5)
    if 4.3<=bt: return Image.blend(img,first,min(1,(bt-4.3)/0.7))
    la = min(1,(bt-1.0)/0.3) if bt>=1.0 else 0
    if bt>=3.8: la=max(0,1-(bt-3.8)/0.3)
    if la>0:
        L=Image.new('RGBA',(OW,OH),(0,0,0,0)); lx=(OW-logo.width)//2; ly=OH//2-logo.height//2-40
        lg=logo.copy(); lg.putalpha(lg.getchannel('A').point(lambda v:round(v*la))); L.alpha_composite(lg,(lx,ly))
        d=ImageDraw.Draw(L); bw,bh=230,6; bx=(OW-bw)//2; by=ly+logo.height+70
        d.rounded_rectangle((bx,by,bx+bw,by+bh),radius=3,fill=(58,58,60,round(255*la)))
        p=max(0,min(1,(bt-1.3)/2.5)); 
        if p>0: d.rounded_rectangle((bx,by,bx+max(bh,round(bw*p)),by+bh),radius=3,fill=(245,245,247,round(255*la)))
        img=img.convert('RGBA'); img.alpha_composite(L); img=img.convert('RGB')
    return img
dec=subprocess.Popen(['ffmpeg','-v','error','-i',f'{R}/take4.mov','-vf',f'fps={FPS},scale=out_range=full,format=rgb24','-f','rawvideo','-'],stdout=subprocess.PIPE)
enc=subprocess.Popen(['ffmpeg','-v','error','-y','-f','rawvideo','-pix_fmt','rgb24','-s',f'{OW}x{OH}','-r',str(FPS),'-i','-',
   '-c:v','libx264','-preset','slow','-crf','21','-pix_fmt','yuv420p','-color_range','tv','-colorspace','bt709','-color_primaries','bt709','-color_trc','bt709','-movflags','+faststart',out],stdin=subprocess.PIPE)
n=SW*SH*3; si=-1; fr=None
def get(src_t):
    global si, fr
    want=round(src_t*FPS)
    while si<want:
        buf=dec.stdout.read(n)
        if len(buf)<n: break
        si+=1; fr=buf
    im=Image.frombytes('RGB',(SW,SH),fr); im.paste(im.crop(PATCH_SRC).transpose(Image.FLIP_LEFT_RIGHT),PATCH_AT,PATCH_MASK); return im
def render(im,t):
    z,cx,cy=cam(t); vw,vh=1710/z,1107/z
    cx=min(max(cx,vw/2),1710-vw/2); cy=min(max(cy,vh/2),1107-vh/2)
    return im.resize((OW,OH),Image.LANCZOS,box=((cx-vw/2)*S,(cy-vh/2)*S,(cx+vw/2)*S,(cy+vh/2)*S))
last_out=None; first_c=None
for i in range(round(DUR*FPS)):
    t=i/FPS; s=seg(t)
    if s[2]=='boot':
        if first_c is None: first_c=render(get(SEG[5][3]),SEG[5][0])
        o=boot_frame(t-s[0], last_out_frozen, first_c)
    else:
        src=s[3]+(s[4]-s[3])*(t-s[0])/(s[1]-s[0])
        o=render(get(src),t)
        if s is SEG[3]: last_out_frozen=o
    enc.stdin.write(o.tobytes())
dec.kill(); enc.stdin.close(); enc.wait(); print('done', round(DUR*FPS),'frames')
