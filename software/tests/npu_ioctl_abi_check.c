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
  const size_t packed_word_total = 91136u;
  const size_t packed_byte_footprint = packed_word_total * 4u;
  int failures = 0;

  failures |= check_size("sizeof(struct npu_ioctl_args)",
                         sizeof(struct npu_ioctl_args), 20u);
  failures |= check_size("_IOC_SIZE(NPU_IOCTL_START_INFERENCE)",
                         (size_t)_IOC_SIZE(NPU_IOCTL_START_INFERENCE), 20u);
  failures |= check_size("offsetof(dma_size)",
                         offsetof(struct npu_ioctl_args, dma_size), 0u);
  failures |= check_size("offsetof(weight_cfg)",
                         offsetof(struct npu_ioctl_args, weight_cfg), 4u);
  failures |= check_size("offsetof(act_cfg)",
                         offsetof(struct npu_ioctl_args, act_cfg), 8u);
  failures |= check_size("offsetof(mac_cfg)",
                         offsetof(struct npu_ioctl_args, mac_cfg), 12u);
  failures |= check_size("offsetof(layer_cfg)",
                         offsetof(struct npu_ioctl_args, layer_cfg), 16u);
  failures |= check_size("NPU_DMA_BUFFER_SIZE", NPU_DMA_BUFFER_SIZE,
                         4u * 1024u * 1024u);
  failures |= check_size("packed weight total (words)", packed_word_total,
                         91136u);
  failures |= check_size("packed weight footprint (bytes)",
                         packed_byte_footprint, 364544u);

  puts("Word/byte count: 91136 packed words x 4 bytes = 364544 bytes.");
  puts("dma_size contract: documented as bytes; current HAL passes packed "
       "words (91136), not bytes (364544).");

  if (failures != 0) {
    fputs("IOCTL ABI diagnostic failed.\n", stderr);
    return 1;
  }

  puts("IOCTL ABI diagnostic passed: current layout is 20 bytes.");
  return 0;
}
