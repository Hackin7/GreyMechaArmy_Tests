#include "neural_net.h"

static void select_digit(nn_result *out)
{
    out->digit = 0;
    for (unsigned i = 1; i < NN_OUTPUTS; ++i) {
        if (out->scores[i] > out->scores[out->digit])
            out->digit = i;
    }
}

void nn_reference(const uint8_t *image, const int16_t *weights, nn_result *out)
{
    for (unsigned i = 0; i < NN_HIDDEN; ++i) {
        int64_t sum = 0;
        const int16_t *row = weights + i * NN_INPUTS;
        for (unsigned j = 0; j < NN_INPUTS; ++j)
            sum += (int64_t)image[j] * row[j];
        sum += (int64_t)weights[NN_L1_BIASES + i] * 4;
        out->hidden[i] = sum > 0 ? sum : 0;
    }
    for (unsigned i = 0; i < NN_OUTPUTS; ++i) {
        int64_t sum = 0;
        const int16_t *row = weights + NN_L2_WEIGHTS + i * NN_HIDDEN;
        for (unsigned j = 0; j < NN_HIDDEN; ++j)
            sum += out->hidden[j] * row[j];
        out->scores[i] = sum + weights[NN_L2_BIASES + i];
    }
    select_digit(out);
}

void nn_binary32(const uint8_t *image, const int16_t *weights, nn_result *out)
{
    int32_t hidden[NN_HIDDEN];
    for (unsigned i = 0; i < NN_HIDDEN; ++i) {
        /* |sum| <= (784 + 4) * 32768 = 25,821,184: int32_t is exact. */
        int32_t sum = (int32_t)weights[NN_L1_BIASES + i] * 4;
        const int16_t *row = weights + i * NN_INPUTS;
        for (unsigned j = 0; j < NN_INPUTS; ++j) {
            if (image[j])
                sum += row[j];
        }
        hidden[i] = sum > 0 ? sum : 0;
        out->hidden[i] = hidden[i];
    }
    for (unsigned i = 0; i < NN_OUTPUTS; ++i) {
        int64_t sum = weights[NN_L2_BIASES + i];
        const int16_t *row = weights + NN_L2_WEIGHTS + i * NN_HIDDEN;
        for (unsigned j = 0; j < NN_HIDDEN; ++j)
            sum += (int64_t)hidden[j] * row[j];
        out->scores[i] = sum;
    }
    select_digit(out);
}

void nn_sparse32(const uint8_t *image, const int16_t *weights, nn_result *out)
{
    uint16_t active[NN_INPUTS];
    unsigned count = 0;
    int32_t hidden[NN_HIDDEN];
    /* This preprocessing is part of the timed inference call. */
    for (unsigned j = 0; j < NN_INPUTS; ++j) {
        if (image[j])
            active[count++] = (uint16_t)j;
    }
    for (unsigned i = 0; i < NN_HIDDEN; ++i) {
        int32_t sum = (int32_t)weights[NN_L1_BIASES + i] * 4;
        const int16_t *row = weights + i * NN_INPUTS;
        for (unsigned j = 0; j < count; ++j)
            sum += row[active[j]];
        hidden[i] = sum > 0 ? sum : 0;
        out->hidden[i] = hidden[i];
    }
    for (unsigned i = 0; i < NN_OUTPUTS; ++i) {
        int64_t sum = weights[NN_L2_BIASES + i];
        const int16_t *row = weights + NN_L2_WEIGHTS + i * NN_HIDDEN;
        for (unsigned j = 0; j < NN_HIDDEN; ++j)
            sum += (int64_t)hidden[j] * row[j];
        out->scores[i] = sum;
    }
    select_digit(out);
}
