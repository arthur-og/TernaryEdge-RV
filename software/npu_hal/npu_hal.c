#include "npu_hal.h"
#include "../include/npu_ioctl.h"
#include "npu_classifier.h"
#include "npu_weights.h"
#include "weights.h"
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/time.h>
#include <unistd.h>

#define DEVICE_PATH "/dev/npu_ternaria"
#define LAYER_RELU (1u << 8)

static void configure_default_model(struct npu_ioctl_args *args) {
  uint32_t weight_offset = NPU_MODEL_WEIGHTS_OFFSET;
#ifdef NPU_MODEL_HAS_QUANT_PARAMS
  uint32_t bias_offset = NPU_MODEL_BIAS_OFFSET;
  uint32_t scale_offset = NPU_MODEL_SCALE_OFFSET;
#endif

  memset(args, 0, sizeof(*args));
  args->input_offset = NPU_MODEL_INPUT_OFFSET;
  args->output_offset = NPU_MODEL_OUTPUT_OFFSET;
  args->layer_count = NPU_MODEL_LAYER_COUNT;

  args->layers[0].input_count = QUANT_DENSE_IN;
  args->layers[0].output_count = QUANT_DENSE_OUT;
  args->layers[0].weight_offset = weight_offset;
#ifdef NPU_MODEL_HAS_QUANT_PARAMS
  args->layers[0].bias_offset = bias_offset;
  args->layers[0].scale_offset = scale_offset;
#endif
  args->layers[0].quant = LAYER_RELU;
  weight_offset += QUANT_DENSE_PACKED_WORDS * 4u;
#ifdef NPU_MODEL_HAS_QUANT_PARAMS
  bias_offset += QUANT_DENSE_OUT * 4u;
  scale_offset += QUANT_DENSE_OUT * 4u;
#endif

  args->layers[1].input_count = QUANT_DENSE_1_IN;
  args->layers[1].output_count = QUANT_DENSE_1_OUT;
  args->layers[1].weight_offset = weight_offset;
#ifdef NPU_MODEL_HAS_QUANT_PARAMS
  args->layers[1].bias_offset = bias_offset;
  args->layers[1].scale_offset = scale_offset;
#endif
  args->layers[1].quant = LAYER_RELU;
  weight_offset += QUANT_DENSE_1_PACKED_WORDS * 4u;
#ifdef NPU_MODEL_HAS_QUANT_PARAMS
  bias_offset += QUANT_DENSE_1_OUT * 4u;
  scale_offset += QUANT_DENSE_1_OUT * 4u;
#endif

  args->layers[2].input_count = QUANT_DENSE_2_IN;
  args->layers[2].output_count = QUANT_DENSE_2_OUT;
  args->layers[2].weight_offset = weight_offset;
#ifdef NPU_MODEL_HAS_QUANT_PARAMS
  args->layers[2].bias_offset = bias_offset;
  args->layers[2].scale_offset = scale_offset;
#endif
  args->layers[2].quant = 0;
}

static long elapsed_us(const struct timeval *begin, const struct timeval *end) {
  return (end->tv_sec - begin->tv_sec) * 1000000L +
         (end->tv_usec - begin->tv_usec);
}

npu_ctx_t *npu_init(void) {
  npu_ctx_t *ctx = malloc(sizeof(*ctx));
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
  return ctx ? weights_load_to_dma(ctx->dma_buffer) : -1;
}

npu_result_t npu_predict(npu_ctx_t *ctx, const uint8_t *image) {
  npu_result_t result = {0};
  struct npu_ioctl_args ioctl_args;
  struct timeval t0, t1, t2, t3;
  const uint8_t *image_bytes = image;
  int32_t *output;

  result.predicted_class = -1;
  gettimeofday(&t0, NULL);
  memcpy((uint8_t *)ctx->dma_buffer + NPU_MODEL_INPUT_OFFSET, image_bytes,
         QUANT_DENSE_IN);
  gettimeofday(&t1, NULL);
  result.time_copy_us = elapsed_us(&t0, &t1);

  configure_default_model(&ioctl_args);
  if (ioctl(ctx->fd, NPU_IOCTL_START_INFERENCE, &ioctl_args) < 0)
    return result;

  gettimeofday(&t2, NULL);
  result.time_npu_us = elapsed_us(&t1, &t2);
  output = (int32_t *)((uint8_t *)ctx->dma_buffer + ioctl_args.output_offset);
  classifier_run((const float (*)[256])weights_get_output(), weights_get_bias(), output,
                result.logits, result.scores, &result.confidence,
                &result.predicted_class);
  gettimeofday(&t3, NULL);
  result.time_output_us = elapsed_us(&t2, &t3);
  result.time_total_us = elapsed_us(&t0, &t3);
  return result;
}

void npu_predict_batch(npu_ctx_t *ctx, const uint8_t *images, int n,
                       npu_result_t *results) {
  for (int i = 0; i < n; i++)
    results[i] = npu_predict(ctx, images + i * QUANT_DENSE_IN);
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
  printf("  Logits: %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f\n",
         result->logits[0], result->logits[1], result->logits[2],
         result->logits[3], result->logits[4], result->logits[5],
         result->logits[6], result->logits[7], result->logits[8],
         result->logits[9]);
  printf("  Times: %ldus copy | %ldus NPU | %ldus output | %ldus total\n",
         result->time_copy_us, result->time_npu_us, result->time_output_us,
         result->time_total_us);
}
