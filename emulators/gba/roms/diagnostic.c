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

// Check the executed ARM instructions and the following MRS, including the
// pipeline that carries their flags. Expected values are fixed test vectors.
#define ALU_TEST(name, opcode) \
static unsigned name(u32 a,u32 b,u32 carry,u32 expected,u32 nzcv) { \
    u32 result,flags; \
    __asm__ volatile("msr cpsr_f,%2\n\t" opcode " %0,%3,%4\n\tmrs %1,cpsr" \
        : "=&r"(result),"=&r"(flags) : "r"(carry<<29),"r"(a),"r"(b) : "cc"); \
    return result==expected&&(flags&0xf0000000u)==nzcv; \
}
ALU_TEST(test_add,"adds")
ALU_TEST(test_adc,"adcs")
ALU_TEST(test_sub,"subs")
ALU_TEST(test_sbc,"sbcs")

static unsigned arithmetic_check(void) {
    if(!test_add(0xffffffff,1,0,0,0x60000000)) return 1;
    if(!test_add(0x7fffffff,1,0,0x80000000,0x90000000)) return 2;
    if(!test_add(0x80000000,0x80000000,0,0,0x70000000)) return 3;
    if(!test_adc(0xffffffff,0,1,0,0x60000000)) return 4;
    if(!test_adc(0x7fffffff,0,1,0x80000000,0x90000000)) return 5;
    if(!test_adc(0xffffffff,0,0,0xffffffff,0x80000000)) return 6;
    if(!test_sub(0,1,0,0xffffffff,0x80000000)) return 7;
    if(!test_sub(0x80000000,1,1,0x7fffffff,0x30000000)) return 8;
    if(!test_sbc(0,0,0,0xffffffff,0x80000000)) return 9;
    if(!test_sbc(0,0xffffffff,0,0,0x40000000)) return 10;
    if(!test_sbc(0x80000000,0x7fffffff,0,0,0x70000000)) return 11;
    if(!test_sbc(0xffffffff,0xffffffff,0,0xffffffff,0x80000000)) return 12;
    if(!test_sbc(0xffffffff,0,0,0xfffffffe,0xa0000000)) return 13;
    if(!test_sbc(0,0xffffffff,1,1,0)) return 14;
    return 0;
}

// Fixed expected values for 0x81234567, including register amounts beyond 32.
#define SHIFT_TEST(name, opcode) \
static unsigned name(u32 amount,u32 carry,u32 expected,u32 nzcv) { \
    u32 result,flags; \
    __asm__ volatile("msr cpsr_f,%2\n\tmovs %0,%3," opcode " %4\n\tmrs %1,cpsr" \
        : "=&r"(result),"=&r"(flags) : "r"(0x10000000u|(carry<<29)), \
          "r"(0x81234567u),"r"(amount) : "cc"); \
    return result==expected&&(flags&0xf0000000u)==nzcv; \
}
SHIFT_TEST(test_lsl,"lsl")
SHIFT_TEST(test_lsr,"lsr")
SHIFT_TEST(test_asr,"asr")
SHIFT_TEST(test_ror,"ror")

static unsigned shifter_check(void) {
    static const u8 amounts[]={0,1,4,31,32,33,64,255};
    static const struct {u32 result,flags;} cases[8][4]={
        {{0x81234567u,0x90000000u},{0x81234567u,0x90000000u},{0x81234567u,0x90000000u},{0x81234567u,0x90000000u}}, // shift 0
        {{0x02468aceu,0x30000000u},{0x4091a2b3u,0x30000000u},{0xc091a2b3u,0xb0000000u},{0xc091a2b3u,0xb0000000u}}, // shift 1
        {{0x12345670u,0x10000000u},{0x08123456u,0x10000000u},{0xf8123456u,0x90000000u},{0x78123456u,0x10000000u}}, // shift 4
        {{0x80000000u,0xb0000000u},{0x00000001u,0x10000000u},{0xffffffffu,0x90000000u},{0x02468acfu,0x10000000u}}, // shift 31
        {{0x00000000u,0x70000000u},{0x00000000u,0x70000000u},{0xffffffffu,0xb0000000u},{0x81234567u,0xb0000000u}}, // shift 32
        {{0x00000000u,0x50000000u},{0x00000000u,0x50000000u},{0xffffffffu,0xb0000000u},{0xc091a2b3u,0xb0000000u}}, // shift 33
        {{0x00000000u,0x50000000u},{0x00000000u,0x50000000u},{0xffffffffu,0xb0000000u},{0x81234567u,0xb0000000u}}, // shift 64
        {{0x00000000u,0x50000000u},{0x00000000u,0x50000000u},{0xffffffffu,0xb0000000u},{0x02468acfu,0x10000000u}}, // shift 255
    };
    for(unsigned i=0;i<8;i++) for(unsigned carry=0;carry<2;carry++)
        for(unsigned mode=0;mode<4;mode++) {
            u32 flags=cases[i][mode].flags;
            if(!amounts[i]) flags|=carry<<29;
            unsigned ok;
            switch(mode) {
                case 0: ok=test_lsl(amounts[i],carry,cases[i][mode].result,flags); break;
                case 1: ok=test_lsr(amounts[i],carry,cases[i][mode].result,flags); break;
                case 2: ok=test_asr(amounts[i],carry,cases[i][mode].result,flags); break;
                default: ok=test_ror(amounts[i],carry,cases[i][mode].result,flags); break;
            }
            if(!ok) return 1+i*8+carry*4+mode;
        }
    for(unsigned carry=0;carry<2;carry++) {
        u32 result,flags;
        __asm__ volatile("msr cpsr_f,%2\n\tmovs %0,%3,rrx\n\tmrs %1,cpsr"
            : "=&r"(result),"=&r"(flags) : "r"(0x10000000u|(carry<<29)),
              "r"(0x81234567u) : "cc");
        if(result!=(0x4091a2b3u|(carry<<31))||
           (flags&0xf0000000u)!=(0x30000000u|(carry<<31))) return 65+carry;
    }
    return 0;
}

extern unsigned banked_register_check(void);

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
    unsigned arithmetic_error=arithmetic_check();
    save32(36,arithmetic_error);
    if(!arithmetic_error) passed|=256;
    unsigned shifter_error=shifter_check();
    save32(40,shifter_error);
    if(!shifter_error) passed|=512;
    unsigned banking_error=banked_register_check();
    save32(44,banking_error);
    if(!banking_error) passed|=1024;
    save32(12,passed);
#ifndef CPU_FOCUS_DIAGNOSTIC
    for(unsigned y=0;y<160;y++)
        for(unsigned x=0;x<240;x++) VIDEO[y*240+x]=bars[x/30];
#endif
    save32(16,0x600d600d); // Checks complete; full bar fill except in CPU-focused builds.
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
