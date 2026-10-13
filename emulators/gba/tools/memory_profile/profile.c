/* Headless guest-memory profiler for pinned mGBA; no FPGA instrumentation.
 * Counts logical CPU/DMA requests and replays hypothetical cache policies.
 * Software-renderer reads are categorized separately from CPU/DMA reads.
 * mGBA's internal idle-loop analysis is disabled. */
#include <mgba/core/core.h>
#include <mgba/core/config.h>
#include <mgba/gba/core.h>
#include <mgba/internal/gba/gba.h>
#include <mgba/internal/gba/memory.h>
#include <mgba/internal/gba/savedata.h>
#include <mgba-util/vfs.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define PHASES 3
#define REGIONS 9
#define KINDS 10
#define MAX_MODELS 160
#define MAX_LINES 2048
unsigned gp_depth;
static unsigned active, phase;
static struct ARMCore* cpu_global;
static struct GBA* gba_global;
static const char* regions[REGIONS] = {"BIOS", "EWRAM", "IWRAM", "IO", "palette", "VRAM", "OAM", "ROM", "save"};
static const char* kinds[KINDS] = {"fetch", "cpu_read", "cpu_write", "dma_read", "dma_write", "ppu_tile", "ppu_tilemap", "ppu_bitmap", "ppu_sprite", "ppu_aux"};
static const char* phases[PHASES] = {"boot_0_29", "baseline_30_89", "inputs_90_179"};
static uint64_t counts[PHASES][REGIONS][KINDS], bytes[PHASES][REGIONS][KINDS];
static uint64_t contiguous[PHASES][REGIONS][KINDS];
static uint32_t previous[REGIONS][KINDS], previous_size[REGIONS][KINDS];
static unsigned have_previous[REGIONS][KINDS];
static uint64_t* hot[PHASES][REGIONS];
static const uint32_t region_sizes[REGIONS] = {16384,262144,32768,1024,1024,98304,1024,33554432,65536};
static uint64_t ignored;
static uint64_t vram_map[PHASES][KINDS][1536];
static uint64_t frame_counts[180][KINDS];
static uint64_t lower_frame_counts[180][KINDS];
static unsigned frame_index;
static uint32_t checksum(const void* ptr,size_t size) {
    const uint8_t* p=ptr;uint32_t h=2166136261u;
    for(size_t i=0;i<size;i++)h=(h^p[i])*16777619u;
    return h;
}

typedef struct {
    unsigned region, capacity, line, ways, sets, filter;
    uint32_t tags[MAX_LINES];
    uint64_t age[MAX_LINES], clock;
    uint64_t reads[PHASES], misses[PHASES], writes[PHASES], invalidations[PHASES], fill_bytes[PHASES];
    /* ROM model: every core miss consults a ONE-block 256-byte flash buffer. */
    uint32_t flash_tag;
    uint64_t flash_fills[PHASES];
    uint64_t ppu_reads[PHASES], ppu_misses[PHASES];
} Model;
static Model models[MAX_MODELS];
static unsigned model_count, first_model[REGIONS], end_model[REGIONS];

static int normalize(uint32_t* address) {
    uint32_t a=*address;
    unsigned r=a>>24, n;
    switch(r) {
    case 0: if(a>=16384)return -1; n=0;break;
    case 2:n=1;a&=0x3ffff;break;
    case 3:n=2;a&=0x7fff;break;
    case 4:if((a&0xffffff)>=1024)return -1;n=3;a&=1023;break;
    case 5:n=4;a&=1023;break;
    case 6:n=5;a&=0x1ffff;if(a>=0x18000)a-=0x8000;break;
    case 7:n=6;a&=1023;break;
    case 8:case 9:case 10:case 11:case 12:case 13:n=7;a&=0x1ffffff;break;
    case 14:case 15:n=8;a&=0xffff;break;
    default:return -1;
    }
    *address=a;return n;
}

static void add_model(unsigned r,unsigned capacity,unsigned line,unsigned ways) {
    Model* m=&models[model_count++];
    if(model_count>MAX_MODELS || capacity/line>MAX_LINES)abort();
    m->region=r;m->capacity=capacity;m->line=line;m->ways=ways;m->sets=capacity/(line*ways);
    for(unsigned i=0;i<MAX_LINES;i++)m->tags[i]=UINT32_MAX;
    m->flash_tag=UINT32_MAX;
}
static void init_models(void) {
    unsigned capacities[]={512,2048,4096,8192};
    for(unsigned r=0;r<REGIONS;r++) {
        first_model[r]=model_count;
        if(r==7) {
            for(unsigned c=0;c<4;c++)for(unsigned w=1;w<=2;w++)add_model(r,capacities[c],8,w);
        } else if(r==0 || r==1 || r==2 || r==5) {
            for(unsigned c=0;c<3;c++)for(unsigned l=4;l<=32;l*=4)for(unsigned w=1;w<=2;w++)add_model(r,capacities[c],l,w);
            /* Include 32-byte lines independently of the 4/16 progression. */
            for(unsigned c=0;c<3;c++)for(unsigned w=1;w<=2;w++)add_model(r,capacities[c],32,w);
        }
        end_model[r]=model_count;
        if(r==5) {
            unsigned end=end_model[r];
            for(unsigned filter=1;filter<=2;filter++)for(unsigned i=first_model[r];i<end;i++) {
                Model* m=&models[i];add_model(r,m->capacity,m->line,m->ways);
                models[model_count-1].filter=filter;
            }
            add_model(r,16,4,4);models[model_count-1].filter=1;
            end_model[r]=model_count;
        }
    }
}
static void cache_access(Model* m,uint32_t a,unsigned size,unsigned write,unsigned ppu) {
    /* Only the lower 64 KiB of VRAM uses PSRAM on GreyMecha. Upper sprite
     * VRAM is already on-chip and must not inflate external-cache estimates. */
    if(m->region==5 && a>=65536)return;
    if(!write && ((m->filter==1 && !ppu) || (m->filter==2 && ppu)))return;
    if(write)m->writes[phase]++;else m->reads[phase]++;
    if(ppu)m->ppu_reads[phase]++;
    uint32_t first=a/m->line,last=(a+size-1)/m->line;
    for(uint32_t block=first;block<=last;block++) {
        unsigned start=(block % m->sets)*m->ways,chosen=start;
        unsigned hit=0;
        for(unsigned w=0;w<m->ways;w++) {
            unsigned i=start+w;
            if(m->tags[i]==block) {chosen=i;hit=1;break;}
            if(m->tags[i]==UINT32_MAX || (m->tags[chosen]!=UINT32_MAX && m->age[i]<m->age[chosen]))chosen=i;
        }
        if(write) {
            /* Write-through, no write allocation; invalidate matching line. */
            if(hit){m->tags[chosen]=UINT32_MAX;m->invalidations[phase]++;}
        } else {
            if(!hit) {
                m->misses[phase]++;m->fill_bytes[phase]+=m->line;
                if(ppu)m->ppu_misses[phase]++;
                m->tags[chosen]=block;
                if(m->region==7) {
                    uint32_t flash=a/256;
                    if(m->flash_tag!=flash){m->flash_tag=flash;m->flash_fills[phase]++;}
                }
            }
            m->age[chosen]=++m->clock;
        }
    }
}

void gp_access(uint32_t address,unsigned kind,unsigned size) {
    if(!active)return;
    uint32_t a=address;
    int r=normalize(&a);
    if(r<0){ignored++;return;}
    counts[phase][r][kind]++;bytes[phase][r][kind]+=size;
    if(have_previous[r][kind] && a==previous[r][kind]+previous_size[r][kind])contiguous[phase][r][kind]++;
    previous[r][kind]=a;previous_size[r][kind]=size;have_previous[r][kind]=1;
    hot[phase][r][a/64]++;
    if(r==5){vram_map[phase][kind][a/64]++;frame_counts[frame_index][kind]++;if(a<65536)lower_frame_counts[frame_index][kind]++;}
    unsigned write=kind==2 || kind==4;
    /* ARM halfword/word transactions are aligned; misalignment rotates data,
     * not a second physical transfer. Mirrors are already canonicalized. */
    uint32_t aligned=a & ~(size-1);
    for(unsigned m=first_model[r];m<end_model[r];m++)cache_access(&models[m],aligned,size,write,kind>=5);
}
void gp_ppu(const void* base,uint32_t offset,unsigned size,unsigned kind) {
    if(!active || !gba_global)return;
    uintptr_t p=(uintptr_t)base+offset;
    uintptr_t v=(uintptr_t)gba_global->video.vram;
    uintptr_t pal=(uintptr_t)gba_global->video.palette;
    uintptr_t oam=(uintptr_t)&gba_global->video.oam;
    if(p>=v && p+size<=v+98304)gp_access(0x06000000+(uint32_t)(p-v),kind,size);
    else if(p>=pal && p+size<=pal+1024)gp_access(0x05000000+(uint32_t)(p-pal),9,size);
    else if(p>=oam && p+size<=oam+1024)gp_access(0x07000000+(uint32_t)(p-oam),9,size);
}
uint8_t gp_ppu_read8(const void* base,uint32_t offset,unsigned kind) {
    gp_ppu(base,offset,1,kind);
    return ((const uint8_t*)base)[offset];
}
void gp_memory(struct ARMCore* cpu,uint32_t address,unsigned size,unsigned write) {
    struct GBA* gba=(struct GBA*)cpu->master;
    gp_access(address,gba->performingDMA ? (write?4:3) : (write?2:1),size);
}

static void emit(FILE* f,unsigned frames,uint32_t final_pc,const uint8_t* save,const color_t* pixels) {
    fprintf(f,"{\n\"frames\":%u,\"final_pc\":%u,\"ignored_accesses\":%"PRIu64",\n",frames,final_pc,ignored);
    fprintf(f,"\"vram_cache_scope\":\"lower_64k_only\",\n");
    fprintf(f,"\"state_checksums\":{\"video\":%u,\"vram\":%u,\"iwram\":%u,\"ewram\":%u},\n",checksum(pixels,240*160*sizeof(color_t)),checksum(gba_global->video.vram,98304),checksum(gba_global->memory.iwram,32768),checksum(gba_global->memory.wram,262144));
    fprintf(f,"\"diagnostic_save_first_48\":\"");
    for(unsigned i=0;i<48;i++)fprintf(f,"%02x",save?save[i]:0);
    fprintf(f,"\",\n\"regions\":[\n");
    unsigned comma=0;
    for(unsigned p=0;p<PHASES;p++)for(unsigned r=0;r<REGIONS;r++)for(unsigned k=0;k<KINDS;k++) {
        if(!counts[p][r][k])continue;
        fprintf(f,"%s{\"phase\":\"%s\",\"region\":\"%s\",\"kind\":\"%s\",\"accesses\":%"PRIu64",\"bytes\":%"PRIu64",\"adjacent_accesses\":%"PRIu64"}",comma++?",\n":"",phases[p],regions[r],kinds[k],counts[p][r][k],bytes[p][r][k],contiguous[p][r][k]);
    }
    fprintf(f,"\n],\"hot_blocks\":[\n");comma=0;
    for(unsigned p=0;p<PHASES;p++)for(unsigned r=0;r<REGIONS;r++) {
        uint64_t best[8]={0};unsigned where[8]={0},unique=0;
        for(unsigned b=0;b<region_sizes[r]/64;b++) {
            uint64_t n=hot[p][r][b];if(!n)continue;unique++;
            for(unsigned i=0;i<8;i++)if(n>best[i]){for(unsigned j=7;j>i;j--){best[j]=best[j-1];where[j]=where[j-1];}best[i]=n;where[i]=b;break;}
        }
        if(!unique)continue;
        fprintf(f,"%s{\"phase\":\"%s\",\"region\":\"%s\",\"unique_64b_blocks\":%u,\"top\":[",comma++?",\n":"",phases[p],regions[r],unique);
        for(unsigned i=0;i<8 && best[i];i++)fprintf(f,"%s{\"offset\":%u,\"accesses\":%"PRIu64"}",i?",":"",where[i]*64,best[i]);
        fprintf(f,"]}");
    }
    fprintf(f,"\n],\"cache_models\":[\n");comma=0;
    for(unsigned m=0;m<model_count;m++)for(unsigned p=0;p<PHASES;p++) {
        Model* c=&models[m];if(!c->reads[p]&&!c->writes[p])continue;
        fprintf(f,"%s{\"phase\":\"%s\",\"region\":\"%s\",\"capacity\":%u,\"line_bytes\":%u,\"ways\":%u,\"filter\":%u,\"read_requests\":%"PRIu64",\"line_misses\":%"PRIu64",\"ppu_reads\":%"PRIu64",\"ppu_misses\":%"PRIu64",\"fill_bytes\":%"PRIu64",\"writes\":%"PRIu64",\"invalidations\":%"PRIu64",\"flash_256b_fills\":%"PRIu64"}",comma++?",\n":"",phases[p],regions[c->region],c->capacity,c->line,c->ways,c->filter,c->reads[p],c->misses[p],c->ppu_reads[p],c->ppu_misses[p],c->fill_bytes[p],c->writes[p],c->invalidations[p],c->flash_fills[p]);
    }
    fprintf(f,"\n],\"vram_64b_maps\":[\n");comma=0;
    for(unsigned p=0;p<PHASES;p++)for(unsigned k=0;k<KINDS;k++) {
        fprintf(f,"%s{\"phase\":\"%s\",\"kind\":\"%s\",\"counts\":[",comma++?",\n":"",phases[p],kinds[k]);
        for(unsigned b=0;b<1536;b++)fprintf(f,"%s%"PRIu64,b?",":"",vram_map[p][k][b]);
        fprintf(f,"]}");
    }
    fprintf(f,"\n],\"vram_per_frame\":[\n");
    for(unsigned n=0;n<180;n++) {
        fprintf(f,"%s{\"frame\":%u",n?",\n":"",n);
        for(unsigned k=0;k<KINDS;k++)fprintf(f,",\"%s\":%"PRIu64,kinds[k],frame_counts[n][k]);
        for(unsigned k=0;k<KINDS;k++)fprintf(f,",\"lower_%s\":%"PRIu64,kinds[k],lower_frame_counts[n][k]);
        fprintf(f,"}");
    }
    fprintf(f,"\n]}\n");
}

int main(int argc,char** argv) {
    if(argc==2 && !strcmp(argv[1],"--self-test")) {
        phase=0;add_model(5,16,4,2);Model* m=&models[0];
        cache_access(m,0,4,0,1);cache_access(m,8,4,0,1);cache_access(m,0,4,0,1);
        cache_access(m,16,4,0,1);cache_access(m,0,4,0,1);
        if(m->misses[0]!=3)return 20;
        cache_access(m,0,4,1,0);cache_access(m,24,4,0,1);cache_access(m,16,4,0,1);
        if(m->misses[0]!=4 || m->invalidations[0]!=1)return 21;
        uint32_t a=0x06018000;if(normalize(&a)!=5 || a!=0x10000)return 22;
        a=0x03008010;if(normalize(&a)!=2 || a!=0x10)return 23;
        m->filter=1;uint64_t reads=m->reads[0];cache_access(m,0,4,0,0);
        if(m->reads[0]!=reads)return 24;
        fprintf(stderr,"PASS: cache hits, LRU, write invalidation, mirrors and PPU-only filtering\n");return 0;
    }
    if(argc!=5){fprintf(stderr,"usage: %s ROM BIOS OUTPUT_JSON FRAMES\n",argv[0]);return 2;}
    unsigned frames=(unsigned)strtoul(argv[4],NULL,10);
    if(frames!=180){fprintf(stderr,"Fixed reproducible profile uses 180 frames\n");return 2;}
    struct mCore* core=GBACoreCreate();
    if(!core || !core->init(core))return 3;
    mCoreConfigInit(&core->config,"gba-memory-profile");
    unsigned hle=!strcmp(argv[2],"hle");
    struct mCoreOptions opts={0};opts.useBios=!hle;opts.skipBios=hle;
    opts.audioSync=false;opts.videoSync=false;
    mCoreConfigLoadDefaults(&core->config,&opts);
    mCoreConfigSetOverrideValue(&core->config,"idleOptimization","ignore");
    mCoreLoadConfig(core);
    color_t* pixels=calloc(240*160,sizeof(color_t));core->setVideoBuffer(core,pixels,240);
    struct VFile* rom=VFileOpen(argv[1],O_RDONLY);
    /* This FPGA always executes a cartridge. Avoid mGBA's heuristic which
     * loads minimal-header diagnostics into EWRAM as multiboot binaries. */
    if(!rom || !GBALoadROM(core->board,rom)){fprintf(stderr,"ROM load failed\n");return 4;}
    if(!hle) {
        struct VFile* bios=VFileOpen(argv[2],O_RDONLY);
        if(!bios || !core->loadBIOS(core,bios,0)){fprintf(stderr,"BIOS load failed\n");return 5;}
    }
    core->reset(core);
    struct GBA* gba=(struct GBA*)core->board;cpu_global=core->cpu;gba_global=gba;
    gba->idleOptimization=IDLE_LOOP_IGNORE;
    init_models();
    for(unsigned p=0;p<PHASES;p++)for(unsigned r=0;r<REGIONS;r++)hot[p][r]=calloc(region_sizes[r]/64,sizeof(uint64_t));
    active=1;
    for(unsigned frame=0;frame<frames;frame++) {
        frame_index=frame;
        phase=frame<30?0:frame<90?1:2;
        /* Baseline released; then R, Left, Up, A to exercise demo controls. */
        unsigned keys=frame<90?0:frame<110?(1<<8):frame<130?0:frame<150?(1<<5):frame<170?(1<<6):(1<<0);
        core->setKeys(core,keys);core->runFrame(core);
        if(frame%30==29)fprintf(stderr,"PROFILE_FRAME %u PC=%08x\n",frame+1,(unsigned)cpu_global->gprs[ARM_PC]);
    }
    active=0;
    FILE* output=fopen(argv[3],"wb");if(!output)return 6;
    emit(output,core->frameCounter(core),(uint32_t)cpu_global->gprs[ARM_PC],gba->memory.savedata.data,pixels);
    fclose(output);
    char image_path[1024];snprintf(image_path,sizeof(image_path),"%s.ppm",argv[3]);
    FILE* image=fopen(image_path,"wb");
    if(image) {
        fprintf(image,"P6\n240 160\n255\n");
        for(unsigned i=0;i<240*160;i++) {
            uint8_t rgb[3]={(uint8_t)pixels[i],(uint8_t)(pixels[i]>>8),(uint8_t)(pixels[i]>>16)};
            fwrite(rgb,1,3,image);
        }
        fclose(image);
    }
    mCoreConfigDeinit(&core->config);core->deinit(core);free(pixels);
    for(unsigned p=0;p<PHASES;p++)for(unsigned r=0;r<REGIONS;r++)free(hot[p][r]);
    return 0;
}
