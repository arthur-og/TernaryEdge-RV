#ifndef _NPU_IOCTL_H
#define _NPU_IOCTL_H

#ifdef __KERNEL__
#include <linux/ioctl.h>
#include <linux/types.h>
#else
#include <sys/ioctl.h>
#include <stdint.h>
#endif

#define NPU_MAGIC 'N'

/*
 * IOCTL argument structure for NPU v2 inference start.
 * The user fills in the DMA parameters and the driver programs
 * the NPU v2 registers (SRC_ADDR, DST_ADDR, DMA_SIZE, etc.)
 * before triggering the hardware.
 */
struct npu_ioctl_args {
    uint32_t dma_size;       /* Total bytes to process */
    uint32_t weight_cfg;     /* Weight configuration (layout-dependent) */
    uint32_t act_cfg;        /* Activation configuration (number of activations) */
    uint32_t mac_cfg;        /* Number of MACs (default: 64) */
    uint32_t layer_cfg;      /* Number of layers (default: 3) */
};

/*
 * IOCTL command:
 *   Starts NPU inference with the given configuration.
 *   The driver blocks (sleep) until the hardware IRQ fires.
 */
#define NPU_IOCTL_START_INFERENCE _IOW(NPU_MAGIC, 1, struct npu_ioctl_args)

/*
 * Size of the DMA coherent buffer allocated by the driver.
 * Must hold all weights + activations for 3 layers:
 *   Weights: 91,136 words × 4 bytes = 364,544 bytes  (~356 KB)
 *   Activations: up to 1024 bytes
 *   Total: ~365 KB → 4 MB buffer is more than sufficient.
 */
#define NPU_DMA_BUFFER_SIZE (4 * 1024 * 1024)

#endif /* _NPU_IOCTL_H */
