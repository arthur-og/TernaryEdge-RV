// SPDX-License-Identifier: GPL-2.0-only
/*
 * npu_driver.c — Ternary Edge-RV NPU v2 Platform Driver
 * 
 * Driver for the NPU Ternária v2 (64 MACs, Wishbone Master DMA, Layer Sequencer).
 * Communicates with the hardware via:
 *   - MMIO registers (ioread32/iowrite32) at the Device Tree resource base
 *   - DMA coherent buffer for zero-copy weight/activation transfer
 *   - Hardware IRQ for sleep-wake synchronization
 *
 * Memory Map (NPU v2):
 *   0x00: STATUS     (RO) — [0]=busy, [1]=irq, [15:8]=zero_counter
 *   0x04: CONTROL    (WO) — [0]=start, [1]=clear_irq
 *   0x08: DMA_SRC    (RW) — Physical address of weights/activations in RAM
 *   0x0C: DMA_DST    (RW) — Physical address for result in RAM
 *   0x10: DMA_SIZE   (RW) — Total MAC operations
 *   0x14: WEIGHT_CFG (RW) — Weight configuration
 *   0x18: ACT_CFG    (RW) — Activation configuration
 *   0x1C: RESULT     (RO) — Final accumulated result
 *   0x20: MAC_CFG    (RW) — Number of MACs (default 64)
 *   0x24: LAYER_CFG  (RW) — Number of layers (default 3)
 *
 * Author: Gustavo Alexandre dos Santos
 * Version: 3.0 (NPU v2)
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/uaccess.h>
#include <linux/io.h>
#include <linux/interrupt.h>
#include <linux/wait.h>
#include <linux/platform_device.h>
#include <linux/dma-mapping.h>
#include <linux/of.h>
#include <linux/of_device.h>

#include "../include/npu_ioctl.h"

/* Driver identification */
#define DEVICE_NAME "npu_ternaria"
#define CLASS_NAME  "npu"

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Gustavo Alexandre dos Santos");
MODULE_DESCRIPTION("Ternary Edge-RV NPU v2 Platform Driver (64 MACs, DMA, IRQ)");
MODULE_VERSION("3.0");

/* =========================================================================
 * NPU v2 Register Offsets
 * ========================================================================= */
#define NPU_REG_STATUS      0x00  /* RO */
#define NPU_REG_CONTROL     0x04  /* WO */
#define NPU_REG_SRC_ADDR    0x08  /* RW */
#define NPU_REG_DST_ADDR    0x0C  /* RW */
#define NPU_REG_DMA_SIZE    0x10  /* RW */
#define NPU_REG_WEIGHT_CFG  0x14  /* RW */
#define NPU_REG_ACT_CFG     0x18  /* RW */
#define NPU_REG_RESULT      0x1C  /* RO */
#define NPU_REG_MAC_CFG     0x20  /* RW */
#define NPU_REG_LAYER_CFG   0x24  /* RW */

/* CONTROL register bit definitions */
#define NPU_CTRL_START      BIT(0)
#define NPU_CTRL_CLEAR_IRQ  BIT(1)

/* =========================================================================
 * Driver Private Data
 * ========================================================================= */
struct npu_dev {
    struct cdev cdev;
    struct device *dev;

    void __iomem *hw_base;      /* MMIO base address */
    int irq;

    /* DMA Coherent Buffer */
    void *dma_vaddr;            /* CPU virtual address */
    dma_addr_t dma_paddr;       /* Physical address for NPU DMA */
    size_t dma_size;

    /* IRQ Synchronization */
    wait_queue_head_t wait_queue;
    int inference_done;
};

static int major_number;
static struct class *npu_class;
static struct npu_dev *npu_instance;

/* =========================================================================
 * Interrupt Handler
 * ========================================================================= */
static irqreturn_t npu_irq_handler(int irq, void *dev_id)
{
    struct npu_dev *npu = (struct npu_dev *)dev_id;

    if (!npu || !npu->hw_base)
        return IRQ_NONE;

    /* Clear IRQ in NPU hardware (write bit 1 to CONTROL) */
    iowrite32(NPU_CTRL_CLEAR_IRQ, npu->hw_base + NPU_REG_CONTROL);

    /* Wake user-space process waiting on ioctl */
    npu->inference_done = 1;
    wake_up_interruptible(&npu->wait_queue);

    return IRQ_HANDLED;
}

/* =========================================================================
 * File Operations
 * ========================================================================= */

/* mmap: map DMA coherent buffer directly to user-space */
static int npu_mmap(struct file *filep, struct vm_area_struct *vma)
{
    struct npu_dev *npu = npu_instance;
    unsigned long size = vma->vm_end - vma->vm_start;

    if (size > npu->dma_size)
        return -EINVAL;

    return dma_mmap_coherent(npu->dev, vma,
                             npu->dma_vaddr, npu->dma_paddr, size);
}

/* ioctl: configure and start NPU inference */
static long npu_ioctl(struct file *filep, unsigned int cmd, unsigned long arg)
{
    struct npu_dev *npu = npu_instance;
    struct npu_ioctl_args args;

    switch (cmd) {
    case NPU_IOCTL_START_INFERENCE:
        if (copy_from_user(&args, (void __user *)arg, sizeof(args)))
            return -EFAULT;

        if (args.dma_size > npu->dma_size) {
            dev_err(npu->dev, "DMA size %u exceeds buffer (%zu)\n",
                    args.dma_size, npu->dma_size);
            return -EINVAL;
        }

        npu->inference_done = 0;

        /* ---- Configure all NPU v2 registers ---- */
        iowrite32((u32)npu->dma_paddr, npu->hw_base + NPU_REG_SRC_ADDR);
        iowrite32((u32)npu->dma_paddr, npu->hw_base + NPU_REG_DST_ADDR);
        iowrite32(args.dma_size,       npu->hw_base + NPU_REG_DMA_SIZE);
        iowrite32(args.weight_cfg,     npu->hw_base + NPU_REG_WEIGHT_CFG);
        iowrite32(args.act_cfg,        npu->hw_base + NPU_REG_ACT_CFG);
        iowrite32(args.mac_cfg,        npu->hw_base + NPU_REG_MAC_CFG);
        iowrite32(args.layer_cfg,      npu->hw_base + NPU_REG_LAYER_CFG);

        wmb();  /* Memory barrier: ensure all writes reach NPU before start */

        /* Start NPU inference */
        iowrite32(NPU_CTRL_START, npu->hw_base + NPU_REG_CONTROL);

        /* Sleep until interrupt (zero CPU usage during NPU compute) */
        wait_event_interruptible(npu->wait_queue, npu->inference_done != 0);

        break;

    default:
        return -ENOTTY;
    }

    return 0;
}

static int npu_open(struct inode *inodep, struct file *filep) { return 0; }
static int npu_release(struct inode *inodep, struct file *filep) { return 0; }

static const struct file_operations npu_fops = {
    .owner          = THIS_MODULE,
    .open           = npu_open,
    .release        = npu_release,
    .mmap           = npu_mmap,
    .unlocked_ioctl = npu_ioctl,
};

/* =========================================================================
 * Platform Driver
 * ========================================================================= */

static int npu_probe(struct platform_device *pdev)
{
    struct device *dev = &pdev->dev;
    struct resource *res;
    int ret;

    dev_info(dev, "Ternary NPU v2 probing...\n");

    npu_instance = devm_kzalloc(dev, sizeof(*npu_instance), GFP_KERNEL);
    if (!npu_instance)
        return -ENOMEM;

    npu_instance->dev = dev;
    init_waitqueue_head(&npu_instance->wait_queue);

    /* 1. Map MMIO region (registers) */
    res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
    npu_instance->hw_base = devm_ioremap_resource(dev, res);
    if (IS_ERR(npu_instance->hw_base))
        return PTR_ERR(npu_instance->hw_base);

    dev_info(dev, "MMIO at 0x%llx (size=%lld)\n",
             (unsigned long long)res->start,
             (unsigned long long)resource_size(res));

    /* 2. Setup IRQ */
    npu_instance->irq = platform_get_irq(pdev, 0);
    if (npu_instance->irq < 0)
        return npu_instance->irq;

    ret = devm_request_irq(dev, npu_instance->irq, npu_irq_handler,
                           IRQF_SHARED, DEVICE_NAME, npu_instance);
    if (ret) {
        dev_err(dev, "Failed to request IRQ %d\n", npu_instance->irq);
        return ret;
    }

    dev_info(dev, "IRQ %d registered\n", npu_instance->irq);

    /* 3. Allocate coherent DMA buffer */
    npu_instance->dma_size = NPU_DMA_BUFFER_SIZE;
    npu_instance->dma_vaddr = dma_alloc_coherent(dev, npu_instance->dma_size,
                                                  &npu_instance->dma_paddr,
                                                  GFP_KERNEL);
    if (!npu_instance->dma_vaddr) {
        dev_err(dev, "DMA coherent allocation failed (%zu bytes)\n",
                npu_instance->dma_size);
        return -ENOMEM;
    }

    dev_info(dev, "DMA buffer: virt=%p phys=0x%pad size=%zu\n",
             npu_instance->dma_vaddr,
             &npu_instance->dma_paddr,
             npu_instance->dma_size);

    /* 4. Register character device */
    major_number = register_chrdev(0, DEVICE_NAME, &npu_fops);
    if (major_number < 0) {
        dev_err(dev, "Failed to register char device\n");
        return major_number;
    }

    npu_class = class_create(THIS_MODULE, CLASS_NAME);
    if (IS_ERR(npu_class)) {
        unregister_chrdev(major_number, DEVICE_NAME);
        return PTR_ERR(npu_class);
    }

    device_create(npu_class, NULL, MKDEV(major_number, 0), NULL, DEVICE_NAME);

    platform_set_drvdata(pdev, npu_instance);
    dev_info(dev, "NPU v2 probe successful. /dev/%s ready.\n", DEVICE_NAME);

    return 0;
}

static void npu_remove(struct platform_device *pdev)
{
    struct npu_dev *npu = platform_get_drvdata(pdev);

    device_destroy(npu_class, MKDEV(major_number, 0));
    class_destroy(npu_class);
    unregister_chrdev(major_number, DEVICE_NAME);

    if (npu && npu->dma_vaddr)
        dma_free_coherent(npu->dev, npu->dma_size,
                          npu->dma_vaddr, npu->dma_paddr);

    dev_info(&pdev->dev, "NPU v2 driver removed.\n");
}

/* Device Tree match table */
static const struct of_device_id npu_of_match[] = {
    { .compatible = "ternaryedge,npu-ternaria", },
    { /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, npu_of_match);

static struct platform_driver npu_platform_driver = {
    .probe  = npu_probe,
    .remove = npu_remove,
    .driver = {
        .name           = DEVICE_NAME,
        .of_match_table = npu_of_match,
    },
};

module_platform_driver(npu_platform_driver);
