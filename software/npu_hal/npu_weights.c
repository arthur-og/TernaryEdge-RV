#include "npu_weights.h"
#include "weights.h"
#include <stdint.h>
#include <string.h>

#define DMA_WEIGHT_OFFSET NPU_MODEL_WEIGHTS_OFFSET
#define DMA_BIAS_OFFSET NPU_MODEL_BIAS_OFFSET
#define DMA_SCALE_OFFSET NPU_MODEL_SCALE_OFFSET

int weights_load_to_dma(uint32_t *dma_buffer) {
  uint8_t *base = (uint8_t *)dma_buffer;

  memcpy(base + DMA_WEIGHT_OFFSET, quant_dense_weights,
         QUANT_DENSE_PACKED_WORDS * 4);

  memcpy(base + DMA_WEIGHT_OFFSET + QUANT_DENSE_PACKED_WORDS * 4,
         quant_dense_1_weights, QUANT_DENSE_1_PACKED_WORDS * 4);

  memcpy(base + DMA_WEIGHT_OFFSET +
             (QUANT_DENSE_PACKED_WORDS + QUANT_DENSE_1_PACKED_WORDS) * 4,
         quant_dense_2_weights, QUANT_DENSE_2_PACKED_WORDS * 4);

#ifdef NPU_MODEL_HAS_QUANT_PARAMS
  memcpy(base + DMA_BIAS_OFFSET, quant_dense_bias, QUANT_DENSE_OUT * 4);
  memcpy(base + DMA_BIAS_OFFSET + QUANT_DENSE_OUT * 4,
         quant_dense_1_bias, QUANT_DENSE_1_OUT * 4);
  memcpy(base + DMA_BIAS_OFFSET +
             (QUANT_DENSE_OUT + QUANT_DENSE_1_OUT) * 4,
         quant_dense_2_bias, QUANT_DENSE_2_OUT * 4);

  memcpy(base + DMA_SCALE_OFFSET, quant_dense_scale, QUANT_DENSE_OUT * 4);
  memcpy(base + DMA_SCALE_OFFSET + QUANT_DENSE_OUT * 4,
         quant_dense_1_scale, QUANT_DENSE_1_OUT * 4);
  memcpy(base + DMA_SCALE_OFFSET +
             (QUANT_DENSE_OUT + QUANT_DENSE_1_OUT) * 4,
         quant_dense_2_scale, QUANT_DENSE_2_OUT * 4);
#endif

  return 0;
}

const float *weights_get_output(void) { return output_weights; }

const float *weights_get_bias(void) { return output_bias; }
