#ifndef NPU_WEIGHTS_H
#define NPU_WEIGHTS_H

#include <stdint.h>

int weights_load_to_dma(uint32_t *dma_buffer);

const float *weights_get_output(void);

const float *weights_get_bias(void);

#endif
