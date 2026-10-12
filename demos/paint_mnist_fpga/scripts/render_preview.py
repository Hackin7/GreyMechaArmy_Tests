"""Validate decoded panel SPI pixels against a reference and render round previews."""
from pathlib import Path
from PIL import Image, ImageDraw
from gen_font import FONT

COLOURS={0:0xffff,1:0x001f,2:0x07e0,3:0xf800,4:0xfda0}


def rgb(word):
    return ((word>>11)*255//31, ((word>>5)&63)*255//63, (word&31)*255//31)


def text(words, caption, x, y, scale):
    for i,ch in enumerate(caption):
        for ry,row in enumerate(FONT.get(ch,['00000']*7)):
            for rx,v in enumerate(row):
                if v=='1':
                    for dy in range(scale):
                        for dx in range(scale):
                            words[(y+ry*scale+dy)*240+x+(i*6+rx)*scale+dx]=0xffff


def expected_frame(case,image):
    words=[0]*57600
    selected=2 if case==2 else 3
    cursor=(70,40) if case==2 else (28,28)
    for sy in range(64):
        for sx in range(96):
            colour=0
            if sx<56 and sy<56:
                n=(sy//2)*28+sx//2
                cell=(n%28)//7+1 if case==2 else (3 if case==0 and image[n] else 0)
                colour=COLOURS[cell]
            swatch=0
            if 66<sx<78 and 5<sy<29: swatch=3
            if 80<sx<92 and 5<sy<29: swatch=1
            if 66<sx<78 and 34<sy<58: swatch=2
            if 80<sx<92 and 34<sy<58: swatch=4
            if swatch:
                colour=COLOURS[swatch]
                if swatch==selected and (sx in (67,77,81,91) or sy in (6,28,35,57)):
                    colour=0xffff
            if abs(sx-cursor[0])<=1 and abs(sy-cursor[1])<=1: colour=0xf81f
            for dy in range(2):
                for dx in range(2): words[(56+sy*2+dy)*240+24+sx*2+dx]=colour
    text(words,'MNIST PAINT',54,26,2)
    text(words,'DIGIT: -- ' if case==1 else ('DIGIT: 7 *' if case==2 else 'DIGIT: 0  '),60,194,2)
    text(words,'A DRAW B CLEAR',78,216,1)
    return words


def main():
    image=[int(v,16) for v in Path('build/generated/images.mem').read_text().split()][:784]
    previews=[]
    for case in range(3):
        words=[int(v,16) for v in Path('build/frame{}.rgb'.format(case)).read_text().split()]
        expected=expected_frame(case,image)
        if len(words)!=57600: raise AssertionError('Incomplete panel frame')
        for i,(got,want) in enumerate(zip(words,expected)):
            if got!=want:
                raise AssertionError('Frame {} pixel ({},{}) got={:04x} expected={:04x}'.format(
                    case,i%240,i//240,got,want))
            if got and ((i%240-119.5)**2+(i//240-119.5)**2)>120**2:
                raise AssertionError('Visible content clipped by circular panel')
        square=Image.new('RGB',(240,240))
        square.putdata([rgb(v) for v in words])
        square.save('build/frame{}.png'.format(case))
        mask=Image.new('L',(240,240),0)
        ImageDraw.Draw(mask).ellipse((0,0,239,239),fill=255)
        rounded=Image.composite(square,Image.new('RGB',(240,240),(40,40,40)),mask)
        rounded=rounded.resize((480,480),Image.Resampling.NEAREST)
        rounded.save('build/preview{}.png'.format(case))
        previews.append(rounded)
        print('PASS panel oracle frame={} all 57600 RGB565 pixels; circular content fits'.format(case))
    sheet=Image.new('RGB',(1440,480),(40,40,40))
    for i,preview in enumerate(previews): sheet.paste(preview,(480*i,0))
    sheet.save('build/previews.png')


if __name__=='__main__':
    main()
