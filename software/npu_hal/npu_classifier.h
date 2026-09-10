#ifndef NPU_CLASSIFIER_H
#define NPU_CLASSIFIER_H

#include <stdint.h>

#define NPU_CLASSIFIER_INPUTS 64

void classifier_run(const float weights[10][NPU_CLASSIFIER_INPUTS],
                    const float bias[10],
                    const int32_t npu_output[NPU_CLASSIFIER_INPUTS],
                    float scores[10],
                    float *confidence, int *predicted);

#endif
