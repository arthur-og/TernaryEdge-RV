#ifndef NPU_HAL_H
#define NPU_HAL_H

#include <stdint.h>
#include "npu_hal_internal.h"

npu_ctx_t *npu_init(void);

int npu_load_weights(npu_ctx_t *ctx);

npu_result_t npu_predict(npu_ctx_t *ctx, const uint8_t *image);

void npu_predict_batch(npu_ctx_t *ctx, const uint8_t *images,
                       int n, npu_result_t *results);

void npu_deinit(npu_ctx_t *ctx);

void npu_print_result(const npu_result_t *result, int label);

#endif
