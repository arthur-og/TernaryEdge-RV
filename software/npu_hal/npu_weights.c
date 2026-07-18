#include "npu_weights.h"
#include "weights.h"
#include <stdint.h>
#include <string.h>

#define DMA_WEIGHT_OFFSET 0x1000
#define DMA_OUTPUT_OFFSET 0x5C400
#define DMA_BIAS_OFFSET 0x5E800

int weights_load_to_dma(uint32_t *dma_buffer) {
  uint8_t *base = (uint8_t *)dma_buffer;

  memcpy(base + DMA_WEIGHT_OFFSET, quant_dense_weights,
         QUANT_DENSE_PACKED_WORDS * 4);

  memcpy(base + DMA_WEIGHT_OFFSET + QUANT_DENSE_PACKED_WORDS * 4,
         quant_dense_1_weights, QUANT_DENSE_1_PACKED_WORDS * 4);

  memcpy(base + DMA_WEIGHT_OFFSET +
             (QUANT_DENSE_PACKED_WORDS + QUANT_DENSE_1_PACKED_WORDS) * 4,
         quant_dense_2_weights, QUANT_DENSE_2_PACKED_WORDS * 4);

  memcpy(base + DMA_OUTPUT_OFFSET, output_weights, OUTPUT_WEIGHTS_COUNT * 4);

  memcpy(base + DMA_BIAS_OFFSET, output_bias, OUTPUT_BIAS_COUNT * 4);

  return 0;
}

const float *weights_get_output(void) { return output_weights; }

const float *weights_get_bias(void) { return output_bias; }
