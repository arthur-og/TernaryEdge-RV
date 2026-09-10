#include "../include/npu_ioctl.h"

#include <stddef.h>
#include <stdio.h>

static int check_size(const char *name, size_t actual, size_t expected) {
  if (actual == expected) {
    printf("PASS: %-32s %zu\n", name, actual);
    return 0;
  }

  fprintf(stderr, "FAIL: %-32s got %zu, expected %zu\n", name, actual,
          expected);
  return 1;
}

int main(void) {
  int failures = 0;

  failures |= check_size("sizeof(struct npu_ioctl_args)",
                         sizeof(struct npu_ioctl_args), 204u);
  failures |= check_size("_IOC_SIZE(NPU_IOCTL_START_INFERENCE)",
                         (size_t)_IOC_SIZE(NPU_IOCTL_START_INFERENCE), 204u);
  failures |= check_size("offsetof(input_offset)",
                         offsetof(struct npu_ioctl_args, input_offset), 0u);
  failures |= check_size("offsetof(output_offset)",
                         offsetof(struct npu_ioctl_args, output_offset), 4u);
  failures |= check_size("offsetof(layer_count)",
                         offsetof(struct npu_ioctl_args, layer_count), 8u);
  failures |= check_size("offsetof(layers)",
                         offsetof(struct npu_ioctl_args, layers), 12u);
  failures |= check_size("sizeof(struct npu_layer_desc)",
                         sizeof(struct npu_layer_desc), 24u);
  failures |= check_size("NPU_DMA_BUFFER_SIZE", NPU_DMA_BUFFER_SIZE,
                         4u * 1024u * 1024u);
  if (failures != 0) {
    fputs("IOCTL ABI diagnostic failed.\n", stderr);
    return 1;
  }

  puts("IOCTL ABI diagnostic passed: descriptor layout is 204 bytes.");
  return 0;
}
