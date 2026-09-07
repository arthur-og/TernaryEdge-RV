#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include "../npu_hal/npu_hal.h"
#include "../npu_hal/npu_classifier.h"
#include "../npu_hal/npu_weights.h"
#include "weights.h"

static int8_t quantize_activation(int32_t value, int relu)
{
    if (relu && value < 0)
        return 0;
    if (value > 127)
        return 127;
    if (value < -128)
        return -128;
    return (int8_t)value;
}

static void forward_ternary_layer(int8_t *output,
                                   const int8_t *input,
                                   const uint32_t *packed_weights,
                                   const int32_t *bias,
                                   int num_inputs, int num_outputs,
                                   int relu)
{
    int words_per_output = (num_inputs + 15) / 16;
    for (int j = 0; j < num_outputs; j++) {
        int32_t acc = 0;
        for (int i = 0; i < num_inputs; i++) {
            int word_idx = j * words_per_output + i / 16;
            int bit_pos = (i % 16) * 2;
            uint8_t weight = (packed_weights[word_idx] >> bit_pos) & 0x03;
            int8_t act = input[i];
            if (weight == 1)
                acc += act;
            else if (weight == 3)
                acc -= act;
        }
        output[j] = quantize_activation(acc + (bias ? bias[j] : 0), relu);
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
    int8_t layer0_out[1024];
    int8_t layer1_out[512];
    int8_t layer2_out[256];
    int32_t classifier_input[256];
    int8_t signed_image[784];
    float logits[10];
    float scores[10];
    float confidence;
    int predicted;
#ifdef NPU_MODEL_HAS_QUANT_PARAMS
    const int32_t *layer0_bias = quant_dense_bias;
    const int32_t *layer1_bias = quant_dense_1_bias;
    const int32_t *layer2_bias = quant_dense_2_bias;
#else
    const int32_t *layer0_bias = NULL;
    const int32_t *layer1_bias = NULL;
    const int32_t *layer2_bias = NULL;
#endif

    printf("CPU mode: running ternary baseline + classifier...\n");

    for (int i = 0; i < 784; i++)
        signed_image[i] = (int8_t)image[i];

    forward_ternary_layer(layer0_out, signed_image,
                          quant_dense_weights, layer0_bias, 784, 1024, 1);

    forward_ternary_layer(layer1_out, layer0_out,
                          quant_dense_1_weights, layer1_bias, 1024, 512, 1);

    forward_ternary_layer(layer2_out, layer1_out,
                          quant_dense_2_weights, layer2_bias, 512, 256, 1);

    for (int i = 0; i < 256; i++)
        classifier_input[i] = layer2_out[i];

    classifier_run(
        (const float (*)[256])weights_get_output(),
        weights_get_bias(),
        classifier_input,
        logits, scores, &confidence, &predicted
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
