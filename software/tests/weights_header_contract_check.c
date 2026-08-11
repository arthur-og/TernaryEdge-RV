#include "../user_app/weights.h"

#include <stddef.h>
#include <stdio.h>

#define EXPECTED_LAYER0_WORDS 50176u
#define EXPECTED_LAYER1_WORDS 32768u
#define EXPECTED_LAYER2_WORDS 8192u
#define EXPECTED_OUTPUT_WEIGHTS 2560u
#define EXPECTED_OUTPUT_BIAS 10u

static int check_count(const char *name, size_t actual, size_t expected) {
  if (actual == expected) {
    printf("PASS: %-48s %zu\n", name, actual);
    return 0;
  }

  fprintf(stderr, "FAIL: %-48s got %zu, expected %zu\n", name, actual,
          expected);
  return 1;
}

int main(void) {
  int failures = 0;
  int contract_missing = 0;

  failures |= check_count(
      "quant_dense_weights / QUANT_DENSE_PACKED_WORDS",
      sizeof(quant_dense_weights) / sizeof(quant_dense_weights[0]),
      EXPECTED_LAYER0_WORDS);
  failures |= check_count("QUANT_DENSE_PACKED_WORDS",
                         QUANT_DENSE_PACKED_WORDS, EXPECTED_LAYER0_WORDS);
  failures |= check_count(
      "quant_dense_1_weights / QUANT_DENSE_1_PACKED_WORDS",
      sizeof(quant_dense_1_weights) / sizeof(quant_dense_1_weights[0]),
      EXPECTED_LAYER1_WORDS);
  failures |= check_count("QUANT_DENSE_1_PACKED_WORDS",
                         QUANT_DENSE_1_PACKED_WORDS, EXPECTED_LAYER1_WORDS);
  failures |= check_count(
      "quant_dense_2_weights / QUANT_DENSE_2_PACKED_WORDS",
      sizeof(quant_dense_2_weights) / sizeof(quant_dense_2_weights[0]),
      EXPECTED_LAYER2_WORDS);
  failures |= check_count("QUANT_DENSE_2_PACKED_WORDS",
                         QUANT_DENSE_2_PACKED_WORDS, EXPECTED_LAYER2_WORDS);
#if defined(OUTPUT_WEIGHTS_COUNT)
  failures |= check_count(
      "output_weights array", sizeof(output_weights) / sizeof(output_weights[0]),
      EXPECTED_OUTPUT_WEIGHTS);
  failures |= check_count("OUTPUT_WEIGHTS_COUNT", OUTPUT_WEIGHTS_COUNT,
                         EXPECTED_OUTPUT_WEIGHTS);
#else
  fputs("MISSING: OUTPUT_WEIGHTS_COUNT and output_weights\n", stderr);
  contract_missing = 1;
#endif

#if defined(OUTPUT_BIAS_COUNT)
  failures |= check_count("output_bias array",
                         sizeof(output_bias) / sizeof(output_bias[0]),
                         EXPECTED_OUTPUT_BIAS);
  failures |= check_count("OUTPUT_BIAS_COUNT", OUTPUT_BIAS_COUNT,
                         EXPECTED_OUTPUT_BIAS);
#else
  fputs("MISSING: OUTPUT_BIAS_COUNT and output_bias\n", stderr);
  contract_missing = 1;
#endif

  if (contract_missing != 0) {
    fputs("EXPECTED FAILURE: generated-header contract is incomplete.\n",
          stderr);
    return 2;
  }

  if (failures != 0) {
    fputs("Generated-header contract diagnostic failed.\n", stderr);
    return 1;
  }

  puts("Generated-header contract diagnostic passed.");
  return 0;
}
