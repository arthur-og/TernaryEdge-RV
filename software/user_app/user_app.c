#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include "../npu_hal/npu_hal.h"
#include "../npu_hal/npu_classifier.h"
#include "../npu_hal/npu_weights.h"
#include "weights.h"

static void forward_ternary_layer(int32_t *output,
                                   const uint8_t *input,
                                   const uint32_t *packed_weights,
                                   const int32_t *bias,
                                   int num_inputs, int num_outputs)
{
    for (int j = 0; j < num_outputs; j++) {
        int32_t acc = 0;
        for (int i = 0; i < num_inputs; i++) {
            int word_idx = j * (num_inputs / 16) + i / 16;
            int bit_pos = (i % 16) * 2;
            uint8_t weight = (packed_weights[word_idx] >> bit_pos) & 0x03;
            int8_t act = (int8_t)input[i];
            if (weight == 0b01)
                acc += act;
            else if (weight == 0b11)
                acc -= act;
        }
        output[j] = acc + (bias ? bias[j] : 0);
    }
}

static int load_mnist_image(const char *path, uint8_t *image)
{
    FILE *f = fopen(path, "rb");
    if (!f) return -1;
    size_t r = fread(image, 1, 784, f);
    fclose(f);
    return r == 784 ? 0 : -1;
}

static void run_cpu_baseline(const uint8_t *image)
{
    int32_t layer0_out[1024];
    int32_t layer1_out[512];
    int32_t layer2_out[256];
    float scores[10];
    float confidence;
    int predicted;

    printf("CPU mode: running ternary baseline + classifier...\n");

    forward_ternary_layer(layer0_out, image,
                          quant_dense_weights, NULL, 784, 1024);

    forward_ternary_layer(layer1_out, (uint8_t *)layer0_out,
                          quant_dense_1_weights, NULL, 1024, 512);

    forward_ternary_layer(layer2_out, (uint8_t *)layer1_out,
                          quant_dense_2_weights, NULL, 512, 256);

    classifier_run(
        (const float (*)[256])weights_get_output(),
        weights_get_bias(),
        layer2_out,
        scores, &confidence, &predicted
    );

    printf("  Predicted class: %d\n", predicted);
    printf("  Confidence: %.2f%%\n", confidence * 100.0f);
}

int main(int argc, char **argv)
{
    int cpu_mode = 0;
    int batch_size = 1;
    const char *file_path = NULL;
    uint8_t image[784];

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--cpu") == 0)
            cpu_mode = 1;
        else if (strcmp(argv[i], "--file") == 0 && i + 1 < argc)
            file_path = argv[++i];
        else if (strcmp(argv[i], "--batch") == 0 && i + 1 < argc)
            batch_size = atoi(argv[++i]);
    }

    if (file_path) {
        if (load_mnist_image(file_path, image) < 0) {
            fprintf(stderr, "Error opening file: %s\n", file_path);
            return EXIT_FAILURE;
        }
    } else {
        for (int i = 0; i < 784; i++)
            image[i] = (uint8_t)((i * 13 + 7) % 128);
    }

    if (cpu_mode) {
        run_cpu_baseline(image);
        return EXIT_SUCCESS;
    }

    npu_ctx_t *ctx = npu_init();
    if (!ctx) {
        fprintf(stderr, "Error initializing NPU\n");
        return EXIT_FAILURE;
    }

    if (npu_load_weights(ctx) < 0) {
        fprintf(stderr, "Error loading weights\n");
        npu_deinit(ctx);
        return EXIT_FAILURE;
    }

    if (batch_size > 1) {
        npu_result_t results[batch_size];
        for (int i = 0; i < batch_size; i++)
            results[i] = npu_predict(ctx, image);
        long total_time = 0;
        for (int i = 0; i < batch_size; i++) {
            npu_print_result(&results[i], i);
            total_time += results[i].time_total_us;
        }
        printf("\nAverage: %ld us (%d inferences)\n",
               total_time / batch_size, batch_size);
    } else {
        npu_result_t result = npu_predict(ctx, image);
        npu_print_result(&result, 0);
    }

    npu_deinit(ctx);
    return EXIT_SUCCESS;
}
