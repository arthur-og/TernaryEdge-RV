#ifndef NPU_IOCTL_H
#define NPU_IOCTL_H

#ifdef __KERNEL__
#include <linux/ioctl.h>
#include <linux/types.h>
#else
#include <stdint.h>
#include <sys/ioctl.h>
#endif

#define NPU_MAGIC 'N'
#define NPU_MAX_LAYERS 8u
#define NPU_MAX_ACTIVATIONS 1024u
#define NPU_DMA_BUFFER_SIZE (4u * 1024u * 1024u)

#define NPU_REG_STATUS 0x00u
#define NPU_REG_CONTROL 0x04u
#define NPU_REG_INPUT_ADDR 0x08u
#define NPU_REG_OUTPUT_ADDR 0x0cu
#define NPU_REG_WEIGHT_ADDR 0x10u
#define NPU_REG_BIAS_ADDR 0x14u
#define NPU_REG_SCALE_ADDR 0x18u
#define NPU_REG_LAYER_COUNT 0x1cu
#define NPU_REG_LAYER_INDEX 0x20u
#define NPU_REG_LAYER_INPUTS 0x24u
#define NPU_REG_LAYER_OUTPUTS 0x28u
#define NPU_REG_LAYER_QUANT 0x2cu
#define NPU_REG_RESULT 0x30u
#define NPU_REG_RESULT_WINDOW 0x34u
#define NPU_REG_ERROR_INFO 0x38u
#define NPU_REG_CAPABILITIES 0x3cu
#define NPU_REG_MAC_CFG 0x40u

#define NPU_CTRL_START (1u << 0)
#define NPU_CTRL_CLEAR_IRQ (1u << 1)
#define NPU_STATUS_BUSY (1u << 0)
#define NPU_STATUS_IRQ (1u << 1)
#define NPU_STATUS_DONE (1u << 2)
#define NPU_STATUS_ERROR (1u << 3)

#ifndef NPU_MODEL_WEIGHTS_OFFSET
#define NPU_MODEL_WEIGHTS_OFFSET 0x00001000u
#endif
#ifndef NPU_MODEL_INPUT_OFFSET
#define NPU_MODEL_INPUT_OFFSET 0x0005c000u
#endif
#ifndef NPU_MODEL_OUTPUT_OFFSET
#define NPU_MODEL_OUTPUT_OFFSET 0x00000000u
#endif
#ifndef NPU_MODEL_BIAS_OFFSET
#define NPU_MODEL_BIAS_OFFSET 0x0005f000u
#endif
#ifndef NPU_MODEL_SCALE_OFFSET
#define NPU_MODEL_SCALE_OFFSET 0x00061000u
#endif

struct npu_layer_desc {
    uint32_t input_count;
    uint32_t output_count;
    uint32_t weight_offset;
    uint32_t bias_offset;
    uint32_t scale_offset;
    uint32_t quant;
};

struct npu_ioctl_args {
    uint32_t input_offset;
    uint32_t output_offset;
    uint32_t layer_count;
    struct npu_layer_desc layers[NPU_MAX_LAYERS];
};

#define NPU_IOCTL_START_INFERENCE _IOW(NPU_MAGIC, 1, struct npu_ioctl_args)

#endif
