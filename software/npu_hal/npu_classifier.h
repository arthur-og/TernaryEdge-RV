#ifndef NPU_CLASSIFIER_H
#define NPU_CLASSIFIER_H

#include <stdint.h>

void classifier_run(const float weights[10][256], const float bias[10],
                    const int32_t npu_output[256], float logits[10],
                    float scores[10], float *confidence, int *predicted);

void classifier_argmax_logits(const int32_t logits[10], float scores[10],
                              float *confidence, int *predicted);

#endif
