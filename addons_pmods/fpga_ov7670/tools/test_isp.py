"""Independent integer/reference vectors, consumed by the RTL test benches."""
from pathlib import Path
import math
import sys

GAMMA=(.5,.625,.75,.875,1.,1.25,1.5,1.75,2.)
DEFAULT=0x030a0a0604
FONT={
 'A':(14,17,17,31,17,17,17),'B':(30,17,17,30,17,17,30),
 'C':(15,16,16,16,16,16,15),'E':(31,16,16,30,16,16,31),
 'F':(31,16,16,30,16,16,16),'G':(15,16,16,23,17,17,15),
 'I':(31,4,4,4,4,4,31),'L':(16,16,16,16,16,16,31),
 'M':(17,27,21,21,17,17,17),'N':(17,25,21,19,17,17,17),
 'O':(14,17,17,17,17,17,14),'R':(30,17,17,30,20,18,17),
 'S':(15,16,16,14,1,1,30),'T':(31,4,4,4,4,4,4),
 'U':(17,17,17,17,17,17,14),
 '0':(14,17,19,21,25,17,14),'1':(4,12,4,4,4,4,14),
 '2':(14,17,1,2,4,8,31),'3':(30,1,1,14,1,1,30),
 '4':(2,6,10,18,31,2,2),'5':(31,16,16,30,1,1,30),
 '6':(14,16,16,30,17,17,14),'7':(31,1,2,4,8,8,8),
 '8':(14,17,17,14,17,17,14),'9':(14,17,17,15,1,1,14),
 '.':(0,0,0,0,0,6,6)}

def hud(mode,enabled,value):
    name=('OFFSET','GAMMA','CONTRAST','SATURATION','SOBEL')[mode]
    number=f'{value//256:2d}' + ('    ' if mode==0 else f'.{(value%256)*1000//256:03d}')
    text=f'{name:10s} {number} {"ON" if enabled else "OFF"}'
    pixels=[]
    for y in range(12):
        for x in range(160):
            i,column=divmod(x,6)
            ch=text[i] if i<len(text) else ' '
            rows=FONT.get(ch,(0,)*7)
            on=2<=y<9 and column<5 and (rows[y-2] & (1<<(4-column)))
            pixels.append(65535 if on else 0)
    return pixels

def channels(p):
    r,g,b=p>>11,(p>>5)&63,p&31
    return (r<<3)|(r>>2),(g<<2)|(g>>4),(b<<3)|(b>>2)

def pack(r,g,b):
    r,g,b=(max(0,min(255,v)) for v in (r,g,b))
    return ((r>>3)<<11)|((g>>2)<<5)|(b>>3)

def luma(p):
    r,g,b=channels(p)
    return (77*r+150*g+29*b+128)//256

def reference(image,mode,enabled,index,value):
    result=[]
    for pos,pixel in enumerate(image):
        r,g,b=channels(pixel)
        if not enabled: out=pixel
        elif mode==0: out=pack(r-value//256,g-value//256,b-value//256)
        elif mode==1:
            out=pack(*(math.floor(255*(v/255)**(1/GAMMA[index])+.5) for v in (r,g,b)))
        elif mode in (2,3):
            pivot=128 if mode==2 else luma(pixel)
            out=pack(*(pivot+((value*(c-pivot)+128)//256) for c in (r,g,b)))
        else:
            x,y=pos%160,pos//160
            if x in (0,159) or y in (0,119): out=0
            else:
                a,b,c,d,f,g,h,i=(luma(image[pos+delta]) for delta in (-161,-160,-159,-1,1,159,160,161))
                gx=c+2*f+i-a-2*d-g
                gy=g+2*h+i-a-2*b-c
                edge=min(255,((abs(gx)+abs(gy))*value+512)//1024)
                out=pack(edge,edge,edge)
        result.append(out)
    return result

def scene(number):
    values=[]
    for p in range(19200):
        x,y=p%160,p//160
        if number==0: v=((p*40503)^(p>>3)^0xa55a)&65535
        elif number==1: v=0x7bef
        elif number==2: v=0xffff if x>=80 else 0
        elif number==3: v=0xffff if y>=60 else 0
        elif number==4: v=pack(x*255//159,y*255//119,(x+y)*255//278)
        else: v=0xffff if (x,y) in ((1,1),(80,60),(158,118)) else 0
        values.append(v)
    return values

def write_hex(path,values):
    path.write_text(''.join(f'{v:04x}\n' for v in values))

def generate(target):
    target.mkdir(parents=True,exist_ok=True)
    write_hex(target/'gamma.hex',[math.floor(255*(v/255)**(1/g)+.5) for g in GAMMA for v in range(256)])
    cases=[]
    for mode in range(4):
        for index in range(9 if mode==1 else 17):
            value=index*1024 if mode==0 else round(GAMMA[index]*256) if mode==1 else index*32
            cases.append((mode,1,index,value,0,512))
    # All bypass modes and identity transforms use full frames, including endpoints.
    cases += [(mode,0,6,384,0,19200) for mode in range(5)]
    cases += [(mode,1,index,256,0,19200) for mode,index in ((1,4),(2,8),(3,8))]
    for pattern in range(1,6):
        for value in (64,256,1024): cases.append((4,1,value//64-1,value,pattern,19200))
    with (target/'cases.txt').open('w') as stream:
        for n,(mode,enabled,index,value,pattern,count) in enumerate(cases):
            image=scene(pattern)
            expected=reference(image,mode,enabled,index,value)
            write_hex(target/f'source{n}.hex',image)
            write_hex(target/f'expected{n}.hex',expected)
            stream.write(f'{n} {mode} {enabled} {index} {value} {count}\n')
    # Panel frames: four point effects, Sobel, unchanged Sobel, bypass.
    image=scene(0);write_hex(target/'panel_source.hex',image)
    for n,mode in enumerate((0,1,2,3,4,4,4)):
        value=(4096,384,320,320,256)[mode]
        expected=reference(image,mode,n!=6,(4,6,10,10,3)[mode],value)
        write_hex(target/f'panel{n}.hex',expected)
        write_hex(target/f'hud{n}.hex',hud(mode,n!=6,value))
    print(f'Generated {len(cases)} independent ISP cases and seven SPI frames in {target}')

if __name__=='__main__': generate(Path(sys.argv[1]))
