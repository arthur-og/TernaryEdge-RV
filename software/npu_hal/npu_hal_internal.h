#ifndef NPU_HAL_INTERNAL_H
#define NPU_HAL_INTERNAL_H

#include <stdint.h>

typedef struct {
  int fd;
  uint32_t *dma_buffer;
} npu_ctx_t;

typedef struct {
  int predicted_class;
  float confidence;
  float scores[10];
  float logits[10];
  long time_copy_us;
  long time_npu_us;
  long time_output_us;
  long time_total_us;
} npu_result_t;

#endif
