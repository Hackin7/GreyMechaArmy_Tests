// Standalone diagnostic; no proprietary BIOS, assets, or runtime required.
typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;
#define REG16(a) (*(volatile u16 *)(a))
#define SAVE ((volatile u8 *)0x0e000000)
#define VIDEO ((volatile u16 *)0x06000000)

static void save32(unsigned offset, u32 value) {
    for (unsigned i=0;i<4;i++) SAVE[offset+i]=(u8)(value>>(8*i));
}

static unsigned ram_check(volatile u32 *p) {
    for (unsigned i=0;i<128;i++) p[i]=0xa55a1234u ^ (i*0x01010101u);
    for (unsigned i=0;i<128;i++) if(p[i]!=(0xa55a1234u ^ (i*0x01010101u))) return 0;
    p[0]=0x11223344;
    ((volatile u8 *)p)[1]=0xaa;
    ((volatile u16 *)p)[1]=0xbbcc;
    if(p[0]!=0xbbccaa44u) return 0;
    return 1;
}

void diagnostic(void) {
    static const char signature[]="GBADIAG1";
    static const u16 bars[]={0x001f,0x03e0,0x7c00,0x03ff,0x7fe0,0x7c1f,0x7fff,0};
    for(unsigned i=0;i<64;i++) SAVE[i]=0;
    for(unsigned i=0;i<8;i++) SAVE[i]=signature[i];
    save32(8,1); // report version
    unsigned passed=0;
    if(ram_check((volatile u32 *)0x02000100)) passed|=1;
    if(ram_check((volatile u32 *)0x03001000)) passed|=2;
    if(*(volatile u32 *)0x02040100==*(volatile u32 *)0x02000100) passed|=4;
    if(*(volatile u32 *)0x03009000==*(volatile u32 *)0x03001000) passed|=8;
    SAVE[32]=0x5a;SAVE[33]=0xa5;
    if(SAVE[32]==0x5a&&SAVE[33]==0xa5) passed|=16;
    REG16(0x04000000)=0x0403;
    volatile u32 *low=(volatile u32 *)0x06000100;
    *low=0x11223344;
    ((volatile u8 *)low)[1]=0xaa; // VRAM byte stores duplicate into a halfword.
    ((volatile u16 *)low)[1]=0xbbcc;
    if(*low==0xbbccaaaau&&*(volatile u32 *)0x06020100==*low) passed|=32;
    volatile u32 *high=(volatile u32 *)0x06010000;
    *high=0x11223344;
    ((volatile u8 *)high)[1]=0xbb;
    if(*high==0x1122bbbbu&&*(volatile u32 *)0x06018000==*high) passed|=64;
    volatile u32 *object=(volatile u32 *)0x06014000;
    *object=0x55667788;
    ((volatile u8 *)object)[0]=0x99; // Byte stores into sprite VRAM are ignored.
    if(*object==0x55667788u) passed|=128;
    save32(12,passed);
    for(unsigned y=0;y<160;y++)
        for(unsigned x=0;x<240;x++) VIDEO[y*240+x]=bars[x/30];
    save32(16,0x600d600d); // RAM checks and full framebuffer fill complete
    unsigned last=0xffff,counter=0;
    for(;;) {
        unsigned keys=(~REG16(0x04000130))&0x3ff;
        if(keys!=last) {
            save32(20,keys);last=keys;
            for(unsigned k=0;k<10;k++)
                for(unsigned y=144;y<156;y++)
                    for(unsigned x=k*24;x<k*24+20;x++)
                        VIDEO[y*240+x]=(keys&(1u<<k))?0x7fff:0;
        }
        save32(24,++counter);
    }
}
