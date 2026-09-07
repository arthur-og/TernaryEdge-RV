// SPDX-License-Identifier: GPL-2.0-only
#include <linux/cdev.h>
#include <linux/dma-mapping.h>
#include <linux/fs.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/uaccess.h>
#include <linux/wait.h>

#include "../include/npu_ioctl.h"

#define DEVICE_NAME "npu_ternaria"
#define CLASS_NAME "npu"

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Ternary Edge-RV");
MODULE_DESCRIPTION("Autonomous ternary NPU v2 driver");
MODULE_VERSION("4.0");

struct npu_dev {
    struct device *dev;
    void __iomem *hw_base;
    int irq;
    void *dma_vaddr;
    dma_addr_t dma_paddr;
    size_t dma_size;
    wait_queue_head_t wait_queue;
    int inference_done;
};

static int major_number;
static struct class *npu_class;
static struct npu_dev *npu_instance;

static bool npu_offset_valid(u32 offset, u32 bytes, size_t limit)
{
    return offset <= limit && bytes <= limit - offset;
}

static bool npu_layer_valid(const struct npu_layer_desc *layer,
                            size_t dma_size)
{
    u32 words_per_output;
    u32 weight_bytes;
    u32 bias_bytes;

    if (!layer->input_count || !layer->output_count ||
        layer->input_count > NPU_MAX_ACTIVATIONS ||
        layer->output_count > NPU_MAX_ACTIVATIONS)
        return false;
    if ((layer->weight_offset & 3u) || (layer->bias_offset & 3u) ||
        (layer->scale_offset & 3u))
        return false;

    words_per_output = (layer->input_count + 15u) / 16u;
    weight_bytes = words_per_output * layer->output_count * 4u;
    bias_bytes = layer->output_count * 4u;
    if (!npu_offset_valid(layer->weight_offset, weight_bytes, dma_size))
        return false;
    if (layer->bias_offset &&
        !npu_offset_valid(layer->bias_offset, bias_bytes, dma_size))
        return false;
    if (layer->scale_offset &&
        !npu_offset_valid(layer->scale_offset, bias_bytes, dma_size))
        return false;
    return true;
}

static irqreturn_t npu_irq_handler(int irq, void *dev_id)
{
    struct npu_dev *npu = dev_id;
    u32 status;

    if (!npu || !npu->hw_base)
        return IRQ_NONE;
    status = ioread32(npu->hw_base + NPU_REG_STATUS);
    if (!(status & NPU_STATUS_IRQ))
        return IRQ_NONE;

    npu->inference_done = 1;
    wake_up_interruptible(&npu->wait_queue);
    return IRQ_HANDLED;
}

static int npu_mmap(struct file *filep, struct vm_area_struct *vma)
{
    struct npu_dev *npu = npu_instance;
    unsigned long size = vma->vm_end - vma->vm_start;

    if (vma->vm_pgoff || size > npu->dma_size)
        return -EINVAL;
    return dma_mmap_coherent(npu->dev, vma, npu->dma_vaddr,
                             npu->dma_paddr, size);
}

static long npu_ioctl(struct file *filep, unsigned int cmd, unsigned long arg)
{
    struct npu_dev *npu = npu_instance;
    struct npu_ioctl_args args;
    u32 status;
    u32 i;
    int wait_result;

    if (cmd != NPU_IOCTL_START_INFERENCE)
        return -ENOTTY;
    if (copy_from_user(&args, (void __user *)arg, sizeof(args)))
        return -EFAULT;
    if (!args.layer_count || args.layer_count > NPU_MAX_LAYERS ||
        (args.input_offset & 3u) || (args.output_offset & 3u))
        return -EINVAL;
    if (!npu_offset_valid(args.input_offset, args.layers[0].input_count,
                          npu->dma_size))
        return -EINVAL;
    if (!npu_offset_valid(args.output_offset,
                          args.layers[args.layer_count - 1].output_count * 4u,
                          npu->dma_size))
        return -EINVAL;

    for (i = 0; i < args.layer_count; i++) {
        if ((i && args.layers[i].input_count != args.layers[i - 1].output_count) ||
            !npu_layer_valid(&args.layers[i], npu->dma_size))
            return -EINVAL;
    }

    status = ioread32(npu->hw_base + NPU_REG_STATUS);
    if (status & NPU_STATUS_BUSY)
        return -EBUSY;

    npu->inference_done = 0;
    iowrite32((u32)(npu->dma_paddr + args.input_offset),
              npu->hw_base + NPU_REG_INPUT_ADDR);
    iowrite32((u32)(npu->dma_paddr + args.output_offset),
              npu->hw_base + NPU_REG_OUTPUT_ADDR);
    iowrite32(args.layer_count, npu->hw_base + NPU_REG_LAYER_COUNT);
    iowrite32(64u, npu->hw_base + NPU_REG_MAC_CFG);

    for (i = 0; i < args.layer_count; i++) {
        const struct npu_layer_desc *layer = &args.layers[i];
        iowrite32(i, npu->hw_base + NPU_REG_LAYER_INDEX);
        iowrite32(layer->input_count, npu->hw_base + NPU_REG_LAYER_INPUTS);
        iowrite32(layer->output_count, npu->hw_base + NPU_REG_LAYER_OUTPUTS);
        iowrite32((u32)(npu->dma_paddr + layer->weight_offset),
                  npu->hw_base + NPU_REG_WEIGHT_ADDR);
        iowrite32(layer->bias_offset ?
                  (u32)(npu->dma_paddr + layer->bias_offset) : 0u,
                  npu->hw_base + NPU_REG_BIAS_ADDR);
        iowrite32(layer->scale_offset ?
                  (u32)(npu->dma_paddr + layer->scale_offset) : 0u,
                  npu->hw_base + NPU_REG_SCALE_ADDR);
        iowrite32(layer->quant, npu->hw_base + NPU_REG_LAYER_QUANT);
    }

    wmb();
    iowrite32(NPU_CTRL_START, npu->hw_base + NPU_REG_CONTROL);
    wait_result = wait_event_interruptible(npu->wait_queue,
                                            npu->inference_done != 0);
    if (wait_result)
        return wait_result;

    status = ioread32(npu->hw_base + NPU_REG_STATUS);
    iowrite32(NPU_CTRL_CLEAR_IRQ, npu->hw_base + NPU_REG_CONTROL);
    if (status & NPU_STATUS_ERROR)
        return -EIO;
    return 0;
}

static int npu_open(struct inode *inodep, struct file *filep) { return 0; }
static int npu_release(struct inode *inodep, struct file *filep) { return 0; }

static const struct file_operations npu_fops = {
    .owner = THIS_MODULE,
    .open = npu_open,
    .release = npu_release,
    .mmap = npu_mmap,
    .unlocked_ioctl = npu_ioctl,
};

static int npu_probe(struct platform_device *pdev)
{
    struct device *dev = &pdev->dev;
    struct resource *res;
    int ret;

    npu_instance = devm_kzalloc(dev, sizeof(*npu_instance), GFP_KERNEL);
    if (!npu_instance)
        return -ENOMEM;
    npu_instance->dev = dev;
    init_waitqueue_head(&npu_instance->wait_queue);

    res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
    npu_instance->hw_base = devm_ioremap_resource(dev, res);
    if (IS_ERR(npu_instance->hw_base))
        return PTR_ERR(npu_instance->hw_base);

    npu_instance->irq = platform_get_irq(pdev, 0);
    if (npu_instance->irq < 0)
        return npu_instance->irq;
    ret = devm_request_irq(dev, npu_instance->irq, npu_irq_handler,
                           IRQF_SHARED, DEVICE_NAME, npu_instance);
    if (ret)
        return ret;

    npu_instance->dma_size = NPU_DMA_BUFFER_SIZE;
    npu_instance->dma_vaddr = dma_alloc_coherent(dev, npu_instance->dma_size,
                                                  &npu_instance->dma_paddr,
                                                  GFP_KERNEL);
    if (!npu_instance->dma_vaddr)
        return -ENOMEM;

    major_number = register_chrdev(0, DEVICE_NAME, &npu_fops);
    if (major_number < 0)
        return major_number;
    npu_class = class_create(THIS_MODULE, CLASS_NAME);
    if (IS_ERR(npu_class)) {
        unregister_chrdev(major_number, DEVICE_NAME);
        return PTR_ERR(npu_class);
    }
    device_create(npu_class, NULL, MKDEV(major_number, 0), NULL, DEVICE_NAME);
    platform_set_drvdata(pdev, npu_instance);
    dev_info(dev, "NPU v2 ready: IRQ %d, DMA %zu bytes\n",
             npu_instance->irq, npu_instance->dma_size);
    return 0;
}

static void npu_remove(struct platform_device *pdev)
{
    struct npu_dev *npu = platform_get_drvdata(pdev);
    device_destroy(npu_class, MKDEV(major_number, 0));
    class_destroy(npu_class);
    unregister_chrdev(major_number, DEVICE_NAME);
    if (npu && npu->dma_vaddr)
        dma_free_coherent(npu->dev, npu->dma_size, npu->dma_vaddr,
                          npu->dma_paddr);
}

static const struct of_device_id npu_of_match[] = {
    { .compatible = "ternaryedge,npu-ternaria" },
    { }
};
MODULE_DEVICE_TABLE(of, npu_of_match);

static struct platform_driver npu_platform_driver = {
    .probe = npu_probe,
    .remove = npu_remove,
    .driver = {
        .name = DEVICE_NAME,
        .of_match_table = npu_of_match,
    },
};

module_platform_driver(npu_platform_driver);
