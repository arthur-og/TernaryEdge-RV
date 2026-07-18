#include "npu_hal.h"
#include "../include/npu_ioctl.h"
#include "npu_classifier.h"
#include "npu_weights.h"
#include "weights.h"
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/time.h>
#include <unistd.h>

#define DEVICE_PATH "/dev/npu_ternaria"

npu_ctx_t *npu_init(void) {
  npu_ctx_t *ctx = malloc(sizeof(npu_ctx_t));
  if (!ctx)
    return NULL;

  ctx->fd = open(DEVICE_PATH, O_RDWR);
  if (ctx->fd < 0) {
    free(ctx);
    return NULL;
  }

  ctx->dma_buffer = mmap(NULL, NPU_DMA_BUFFER_SIZE, PROT_READ | PROT_WRITE,
                         MAP_SHARED, ctx->fd, 0);
  if (ctx->dma_buffer == MAP_FAILED) {
    close(ctx->fd);
    free(ctx);
    return NULL;
  }

  return ctx;
}

int npu_load_weights(npu_ctx_t *ctx) {
  return weights_load_to_dma(ctx->dma_buffer);
}

npu_result_t npu_predict(npu_ctx_t *ctx, const uint8_t *image) {
  npu_result_t result = {0};
  struct npu_ioctl_args ioctl_args;
  struct timeval t0, t1, t2, t3;
  int32_t npu_output[256];
  float scores[10];

  gettimeofday(&t0, NULL);

  uint8_t *act_base = (uint8_t *)ctx->dma_buffer + 0x5C000;
  for (int i = 0; i < 784; i++)
    act_base[i] = image[i];

  gettimeofday(&t1, NULL);
  result.time_copy_us =
      (t1.tv_sec - t0.tv_sec) * 1000000L + (t1.tv_usec - t0.tv_usec);

  ioctl_args.dma_size = QUANT_DENSE_PACKED_WORDS + QUANT_DENSE_1_PACKED_WORDS +
                        QUANT_DENSE_2_PACKED_WORDS;
  ioctl_args.weight_cfg = QUANT_DENSE_PACKED_WORDS;
  ioctl_args.act_cfg = 784;
  ioctl_args.mac_cfg = 64;
  ioctl_args.layer_cfg = 3;

  if (ioctl(ctx->fd, NPU_IOCTL_START_INFERENCE, &ioctl_args) < 0) {
    result.predicted_class = -1;
    return result;
  }

  gettimeofday(&t2, NULL);
  result.time_npu_us =
      (t2.tv_sec - t1.tv_sec) * 1000000L + (t2.tv_usec - t1.tv_usec);

  for (int i = 0; i < 256; i++)
    npu_output[i] = (int32_t)ctx->dma_buffer[i];

  classifier_run((const float (*)[256])weights_get_output(), weights_get_bias(),
                 npu_output, scores, &result.confidence,
                 &result.predicted_class);

  gettimeofday(&t3, NULL);
  result.time_output_us =
      (t3.tv_sec - t2.tv_sec) * 1000000L + (t3.tv_usec - t2.tv_usec);
  result.time_total_us =
      result.time_copy_us + result.time_npu_us + result.time_output_us;

  for (int i = 0; i < 10; i++)
    result.scores[i] = scores[i];

  return result;
}

void npu_predict_batch(npu_ctx_t *ctx, const uint8_t *images, int n,
                       npu_result_t *results) {
  for (int i = 0; i < n; i++)
    results[i] = npu_predict(ctx, images + i * 784);
}

void npu_deinit(npu_ctx_t *ctx) {
  if (ctx) {
    munmap(ctx->dma_buffer, NPU_DMA_BUFFER_SIZE);
    close(ctx->fd);
    free(ctx);
  }
}

void npu_print_result(const npu_result_t *result, int label) {
  printf("Image %d:\n", label);
  printf("  Predicted class: %d\n", result->predicted_class);
  printf("  Confidence: %.2f%%\n", result->confidence * 100.0f);
  printf("  Times: %ldus copy | %ldus NPU | %ldus output | %ldus total\n",
         result->time_copy_us, result->time_npu_us, result->time_output_us,
         result->time_total_us);
}
