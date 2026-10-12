#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#endif
#ifdef __MINGW32__
#define __USE_MINGW_ANSI_STDIO 1
#endif
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "neural_net.h"
#include "model_data.h"
#include "test_data.h"

#ifdef NN_PICO
#include "pico/stdlib.h"
#include "hardware/clocks.h"
#elif defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <time.h>
#endif

static int16_t weights_ram[NN_CONSTANTS];
static uint8_t image_ram[NN_INPUTS];
static volatile uint64_t checksum;
typedef void (*inference_fn)(const uint8_t *, const int16_t *, nn_result *);

static uint64_t ticks(void)
{
#ifdef NN_PICO
    return time_us_64();
#elif defined(_WIN32)
    LARGE_INTEGER t;
    QueryPerformanceCounter(&t);
    return (uint64_t)t.QuadPart;
#else
    struct timespec t;
    if (clock_gettime(CLOCK_MONOTONIC, &t) != 0) {
        perror("clock_gettime");
        exit(1);
    }
    return (uint64_t)t.tv_sec * UINT64_C(1000000000) + (uint64_t)t.tv_nsec;
#endif
}

static double tick_us(void)
{
#ifdef NN_PICO
    return 1.0;
#elif defined(_WIN32)
    LARGE_INTEGER f;
    QueryPerformanceFrequency(&f);
    return 1000000.0 / (double)f.QuadPart;
#else
    return 0.001;
#endif
}

static int verify(inference_fn infer, const char *name)
{
    nn_result out;
    for (unsigned c = 0; c < NN_TEST_CASES; ++c) {
        memcpy(image_ram, test_images[c], sizeof image_ram);
        infer(image_ram, weights_ram, &out);
        for (unsigned i = 0; i < NN_HIDDEN + NN_OUTPUTS; ++i) {
            int64_t got = i < NN_HIDDEN ? out.hidden[i] : out.scores[i - NN_HIDDEN];
            if (got != test_expected[c][i]) {
                printf("FAIL %s %s value=%u got=%" PRId64 " expected=%" PRId64 "\n",
                       name, test_names[c], i, got, test_expected[c][i]);
                return 0;
            }
        }
        if (out.digit != test_digits[c]) {
            printf("FAIL %s %s digit=%u expected=%u\n",
                   name, test_names[c], out.digit, test_digits[c]);
            return 0;
        }
        printf("# PASS %s %s digit=%u values=74\n", name, test_names[c], out.digit);
    }
    return 1;
}

static void benchmark(inference_fn infer, const char *name, unsigned iterations)
{
    enum { SAMPLES = 9 };
    nn_result out;
    for (unsigned c = 0; c < NN_TEST_CASES; ++c) {
        double samples[SAMPLES];
        unsigned active = 0;
        memcpy(image_ram, test_images[c], sizeof image_ram);
        for (unsigned i = 0; i < NN_INPUTS; ++i)
            active += image_ram[i];
        for (unsigned i = 0; i < 5; ++i)
            infer(image_ram, weights_ram, &out);
        for (unsigned s = 0; s < SAMPLES; ++s) {
            uint64_t begin = ticks();
            for (unsigned i = 0; i < iterations; ++i) {
                infer(image_ram, weights_ram, &out);
                checksum += (uint64_t)out.scores[out.digit] + out.digit;
            }
            samples[s] = (double)(ticks() - begin) * tick_us() / iterations;
        }
        for (unsigned i = 1; i < SAMPLES; ++i) {
            double v = samples[i];
            unsigned j = i;
            while (j && samples[j - 1] > v) {
                samples[j] = samples[j - 1];
                --j;
            }
            samples[j] = v;
        }
        printf("%s,%s,%u,%u,%.3f,%.3f,%.3f,%u\n", name, test_names[c], active,
               iterations, samples[SAMPLES / 2], samples[0], samples[SAMPLES - 1], out.digit);
    }
}

int main(int argc, char **argv)
{
    unsigned iterations = 200;
#ifdef NN_PICO
    (void)argc;
    (void)argv;
    stdio_init_all();
    sleep_ms(2000);
    iterations = 100;
    printf("# target=RP2350/native-C core=0 clock_hz=%" PRIu32 "\n", clock_get_hz(clk_sys));
#else
    if (argc > 2) {
        fprintf(stderr, "Usage: %s [iterations-per-batch]\n", argv[0]);
        return 2;
    }
    if (argc == 2) {
        char *end;
        unsigned long n = strtoul(argv[1], &end, 10);
        if (!argv[1][0] || *end || n == 0 || n > 1000000) {
            fprintf(stderr, "Iterations must be 1..1000000\n");
            return 2;
        }
        iterations = (unsigned)n;
    }
    printf("# target=host/native-C (not MCU timing)\n");
#endif
    printf("# compiler=%s model_sha256=%s\n", __VERSION__, NN_MODEL_SHA256);
    printf("# weights_bytes=%zu image_bytes=%zu result_bytes=%zu\n",
           sizeof weights_ram, sizeof image_ram, sizeof(nn_result));
    memcpy(weights_ram, model_weights, sizeof weights_ram);
    if (!verify(nn_reference, "reference64") || !verify(nn_binary32, "binary32") ||
        !verify(nn_sparse32, "sparse32"))
        return 1;
    printf("variant,image,active_pixels,iterations,median_us,min_us,max_us,digit\n");
    benchmark(nn_reference, "reference64", iterations);
    benchmark(nn_binary32, "binary32", iterations);
    benchmark(nn_sparse32, "sparse32", iterations);
    printf("# checksum=%" PRIu64 "\n", checksum);
#ifdef NN_PICO
    fflush(stdout);
    for (;;)
        tight_loop_contents();
#endif
    return 0;
}
