#ifndef MNIST_NEURAL_NET_H
#define MNIST_NEURAL_NET_H

#include <stdint.h>

enum {
    NN_INPUTS = 784,
    NN_HIDDEN = 64,
    NN_OUTPUTS = 10,
    NN_CONSTANTS = 50890,
    NN_L2_WEIGHTS = 50176,
    NN_L1_BIASES = 50816,
    NN_L2_BIASES = 50880
};

typedef struct {
    int64_t hidden[NN_HIDDEN];
    int64_t scores[NN_OUTPUTS];
    unsigned digit;
} nn_result;

/* Inputs must be binary (0 or 1). Constants use neural_net.v address order. */
void nn_reference(const uint8_t *image, const int16_t *weights, nn_result *out);
void nn_binary32(const uint8_t *image, const int16_t *weights, nn_result *out);
void nn_sparse32(const uint8_t *image, const int16_t *weights, nn_result *out);

#endif
