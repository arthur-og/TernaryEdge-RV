#include "npu_classifier.h"
#include <math.h>

void classifier_run(const float weights[10][256], const float bias[10],
                    const int32_t npu_output[256], float scores[10],
                    float *confidence, int *predicted) {
  for (int c = 0; c < 10; c++) {
    scores[c] = bias[c];
    for (int i = 0; i < 256; i++) {
      scores[c] += npu_output[i] * weights[c][i];
    }
  }

  int max_idx = 0;
  for (int c = 1; c < 10; c++) {
    if (scores[c] > scores[max_idx])
      max_idx = c;
  }
  *predicted = max_idx;

  float max_score = scores[max_idx];
  float sum = 0.0f;
  for (int c = 0; c < 10; c++) {
    scores[c] = expf(scores[c] - max_score);
    sum += scores[c];
  }
  *confidence = scores[max_idx] / sum;
}
