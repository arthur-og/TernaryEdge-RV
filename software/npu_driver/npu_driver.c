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

/* Defines and configuration */
#define DEVICE_NAME "npu_ternaria"
#define CLASS_NAME "npu"

/* 
 * NPU/DMA Register Offsets 
 * (To be confirmed with LiteX Hardware Team) 
 */
#define DMA_REG_SRC_ADDR    0x00
#define DMA_REG_DEST_ADDR   0x04 /* If applicable, otherwise NPU receives stream */
#define DMA_REG_SIZE        0x08
#define DMA_REG_CTRL        0x0C /* Bit 0: Start, Bit 1: Done/IRQ Clear */

MODULE_LICENSE("MIT");
MODULE_AUTHOR("Gustavo Alexandre");
MODULE_DESCRIPTION("TernaryEdge-RV NPU Platform Driver (Zero-Copy/DMA/IRQ)");
MODULE_VERSION("2.0");

/* Driver private data structure */
struct npu_dev {
    struct cdev cdev;
    struct device *dev;
    
    void __iomem *hw_base_addr; /* MMIO Base for DMA/NPU Config */
    int irq;

    /* DMA Coherent Memory fields */
    void *dma_vaddr;        /* Virtual address for CPU (used internally) */
    dma_addr_t dma_paddr;   /* Physical address for Hardware DMA */
    size_t dma_size;

    /* Sync primitives */
    wait_queue_head_t wait_queue;
    int inference_done;
};

static int major_number;
static struct class* npu_class = NULL;
static struct npu_dev *npu_instance = NULL;

/* Interrupt Handler */
static irqreturn_t npu_irq_handler(int irq, void *dev_id)
{
    struct npu_dev *npu = (struct npu_dev *)dev_id;
    u32 status;

    if (!npu || !npu->hw_base_addr)
        return IRQ_NONE;

    /* Read status and clear hardware interrupt flag */
    status = ioread32(npu->hw_base_addr + DMA_REG_CTRL);
    iowrite32(status | 0x02, npu->hw_base_addr + DMA_REG_CTRL); /* Assuming Bit 1 clears IRQ */

    /* Mark as done and wake up waiting User-Space process */
    npu->inference_done = 1;
    wake_up_interruptible(&npu->wait_queue);

    return IRQ_HANDLED;
}

/* File Operations: mmap (Zero-Copy User-Space to DMA) */
static int npu_mmap(struct file *filep, struct vm_area_struct *vma)
{
    struct npu_dev *npu = npu_instance;
    unsigned long size = vma->vm_end - vma->vm_start;

    if (size > npu->dma_size)
        return -EINVAL;

    /* Map the coherent DMA buffer directly to User-Space */
    return dma_mmap_coherent(npu->dev, vma, npu->dma_vaddr, npu->dma_paddr, size);
}

/* File Operations: ioctl (Trigger Hardware) */
static long npu_ioctl(struct file *filep, unsigned int cmd, unsigned long arg)
{
    struct npu_dev *npu = npu_instance;
    unsigned int payload_size;

    switch (cmd) {
        case NPU_IOCTL_START_INFERENCE:
            if (copy_from_user(&payload_size, (unsigned int __user *)arg, sizeof(payload_size)))
                return -EFAULT;

            if (payload_size > npu->dma_size) {
                printk(KERN_ERR "[TERNARY NPU] Payload size exceeds DMA buffer\n");
                return -EINVAL;
            }

            npu->inference_done = 0;

            /* Configure standard DMA Controller */
            iowrite32((u32)npu->dma_paddr, npu->hw_base_addr + DMA_REG_SRC_ADDR);
            iowrite32(payload_size, npu->hw_base_addr + DMA_REG_SIZE);
            
            /* Start DMA/NPU */
            iowrite32(0x01, npu->hw_base_addr + DMA_REG_CTRL); /* Assuming Bit 0 is Start */

            /* Put the process to SLEEP (Zero CPU Polling) */
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

/* Platform Driver Probe */
static int npu_probe(struct platform_device *pdev)
{
    struct device *dev = &pdev->dev;
    struct resource *res;
    int ret;

    printk(KERN_INFO "[TERNARY NPU] Probing Device from Device Tree...\n");

    npu_instance = devm_kzalloc(dev, sizeof(*npu_instance), GFP_KERNEL);
    if (!npu_instance) return -ENOMEM;
    npu_instance->dev = dev;
    init_waitqueue_head(&npu_instance->wait_queue);

    /* 1. Map Hardware Registers (MMIO) */
    res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
    npu_instance->hw_base_addr = devm_ioremap_resource(dev, res);
    if (IS_ERR(npu_instance->hw_base_addr)) {
        printk(KERN_ERR "[TERNARY NPU] Failed to map MMIO\n");
        return PTR_ERR(npu_instance->hw_base_addr);
    }

    /* 2. Setup Hardware IRQ */
    npu_instance->irq = platform_get_irq(pdev, 0);
    if (npu_instance->irq < 0) return npu_instance->irq;

    ret = devm_request_irq(dev, npu_instance->irq, npu_irq_handler, IRQF_SHARED, DEVICE_NAME, npu_instance);
    if (ret) {
        printk(KERN_ERR "[TERNARY NPU] Failed to request IRQ %d\n", npu_instance->irq);
        return ret;
    }

    /* 3. Allocate Coherent DMA Memory */
    npu_instance->dma_size = NPU_DMA_BUFFER_SIZE;
    npu_instance->dma_vaddr = dma_alloc_coherent(dev, npu_instance->dma_size, &npu_instance->dma_paddr, GFP_KERNEL);
    if (!npu_instance->dma_vaddr) {
        printk(KERN_ERR "[TERNARY NPU] Failed to allocate DMA memory\n");
        return -ENOMEM;
    }
    printk(KERN_INFO "[TERNARY NPU] DMA buffer allocated at phys 0x%pad\n", &npu_instance->dma_paddr);

    /* 4. Register Character Device (/dev/npu_ternaria) */
    major_number = register_chrdev(0, DEVICE_NAME, &npu_fops);
    npu_class = class_create(CLASS_NAME);
    device_create(npu_class, NULL, MKDEV(major_number, 0), NULL, DEVICE_NAME);

    platform_set_drvdata(pdev, npu_instance);
    printk(KERN_INFO "[TERNARY NPU] Probe successful. Ready for Zero-Copy inference.\n");
    return 0;
}

/* Platform Driver Remove */
static int npu_remove(struct platform_device *pdev)
{
    struct npu_dev *npu = platform_get_drvdata(pdev);

    device_destroy(npu_class, MKDEV(major_number, 0));
    class_destroy(npu_class);
    unregister_chrdev(major_number, DEVICE_NAME);

    if (npu->dma_vaddr)
        dma_free_coherent(npu->dev, npu->dma_size, npu->dma_vaddr, npu->dma_paddr);

    printk(KERN_INFO "[TERNARY NPU] Driver removed.\n");
    return 0;
}

/* Device Tree Match Table */
static const struct of_device_id npu_of_match[] = {
    { .compatible = "ternary,npu-dma", },
    { /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, npu_of_match);

static struct platform_driver npu_driver = {
    .probe = npu_probe,
    .remove = npu_remove,
    .driver = {
        .name = DEVICE_NAME,
        .of_match_table = npu_of_match,
    },
};

module_platform_driver(npu_driver);
