#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/uaccess.h>
#include <linux/io.h>
#include <linux/interrupt.h>
#include <linux/of.h>
#include <linux/of_device.h>
#include <linux/of_address.h>
#include <linux/of_irq.h>
#include <linux/wait.h>

/* Defines and configuration */
#define DEVICE_NAME "npu_ternaria"
#define CLASS_NAME "npu"

/* NPU Register Offsets (Example) */
#define NPU_REG_CTRL    0x00
#define NPU_REG_STATUS  0x04
#define NPU_REG_INPUT   0x08
#define NPU_REG_OUTPUT  0x0C

MODULE_LICENSE("MIT");
MODULE_AUTHOR("Gustavo Alexandre");
MODULE_DESCRIPTION("TernaryEdge-RV NPU LKM (MMIO/IRQ)");
MODULE_VERSION("1.0");

static int major_number;
static struct class* npu_class = NULL;
static struct device* npu_device = NULL;

static void __iomem *npu_base_addr;
static int npu_irq;

/* Wait queue for IRQ synchronization (removing CPU polling) */
static DECLARE_WAIT_QUEUE_HEAD(npu_wait_queue);
static int inference_done = 0;

/* Interrupt Handler */
static irqreturn_t npu_irq_handler(int irq, void *dev_id)
{
    u32 status;
    
    if (!npu_base_addr)
        return IRQ_NONE;

    /* Read status to clear interrupt (example logic) */
    status = ioread32(npu_base_addr + NPU_REG_STATUS);
    
    /* Mark as done and wake up waiting processes */
    inference_done = 1;
    wake_up_interruptible(&npu_wait_queue);

    return IRQ_HANDLED;
}

/* File Operations */
static int npu_open(struct inode *inodep, struct file *filep)
{
    printk(KERN_INFO "[TERNARY NPU] Device opened\n");
    return 0;
}

static ssize_t npu_read(struct file *filep, char *buffer, size_t len, loff_t *offset)
{
    int ret;
    u32 result;

    /* Wait for the hardware to finish via IRQ (no polling!) */
    wait_event_interruptible(npu_wait_queue, inference_done != 0);
    inference_done = 0; /* Reset flag */

    /* Read result from NPU hardware */
    result = ioread32(npu_base_addr + NPU_REG_OUTPUT);

    /* Send data to user space */
    ret = copy_to_user(buffer, &result, sizeof(result));
    if (ret != 0) {
        printk(KERN_ERR "[TERNARY NPU] Failed to send %d bytes to user\n", ret);
        return -EFAULT;
    }

    printk(KERN_INFO "[TERNARY NPU] Result sent to user space\n");
    return sizeof(result);
}

static ssize_t npu_write(struct file *filep, const char *buffer, size_t len, loff_t *offset)
{
    u32 input_data;

    if (len < sizeof(u32))
        return -EINVAL;

    /* Get data from user space */
    if (copy_from_user(&input_data, buffer, sizeof(input_data))) {
        return -EFAULT;
    }

    /* Reset inference flag */
    inference_done = 0;

    /* Write data to hardware and trigger (example logic) */
    iowrite32(input_data, npu_base_addr + NPU_REG_INPUT);
    iowrite32(0x01, npu_base_addr + NPU_REG_CTRL); /* Start signal */

    printk(KERN_INFO "[TERNARY NPU] Data written to NPU, inference started\n");
    return sizeof(input_data);
}

static int npu_release(struct inode *inodep, struct file *filep)
{
    printk(KERN_INFO "[TERNARY NPU] Device closed\n");
    return 0;
}

static struct file_operations npu_fops = {
    .open = npu_open,
    .read = npu_read,
    .write = npu_write,
    .release = npu_release,
};

static int __init npu_driver_init(void)
{
    int ret;

    printk(KERN_INFO "[TERNARY NPU] Initializing driver...\n");

    /* 1. Register Character Device */
    major_number = register_chrdev(0, DEVICE_NAME, &npu_fops);
    if (major_number < 0) {
        printk(KERN_ERR "[TERNARY NPU] Failed to register a major number\n");
        return major_number;
    }

    /* 2. Register Device Class */
    npu_class = class_create(CLASS_NAME);
    if (IS_ERR(npu_class)) {
        unregister_chrdev(major_number, DEVICE_NAME);
        printk(KERN_ERR "[TERNARY NPU] Failed to register device class\n");
        return PTR_ERR(npu_class);
    }

    /* 3. Register Device Driver (/dev/npu_ternaria) */
    npu_device = device_create(npu_class, NULL, MKDEV(major_number, 0), NULL, DEVICE_NAME);
    if (IS_ERR(npu_device)) {
        class_destroy(npu_class);
        unregister_chrdev(major_number, DEVICE_NAME);
        printk(KERN_ERR "[TERNARY NPU] Failed to create the device\n");
        return PTR_ERR(npu_device);
    }

    /* Note: In a real system, these would be populated from the Device Tree (.dts).
     * For now, this is a placeholder skeleton waiting for actual hardware specs. */
    // npu_base_addr = ioremap(PHYSICAL_ADDR, SIZE);
    // npu_irq = irq_of_parse_and_map(...);
    // request_irq(npu_irq, npu_irq_handler, IRQF_SHARED, DEVICE_NAME, (void *)(npu_irq_handler));

    printk(KERN_INFO "[TERNARY NPU] Driver loaded. /dev/%s created successfully.\n", DEVICE_NAME);
    return 0;
}

static void __exit npu_driver_exit(void)
{
    /* Clean up hardware mappings (if they existed) */
    // iounmap(npu_base_addr);
    // free_irq(npu_irq, (void *)(npu_irq_handler));

    device_destroy(npu_class, MKDEV(major_number, 0));
    class_unregister(npu_class);
    class_destroy(npu_class);
    unregister_chrdev(major_number, DEVICE_NAME);
    
    printk(KERN_INFO "[TERNARY NPU] Driver unloaded successfully.\n");
}

module_init(npu_driver_init);
module_exit(npu_driver_exit);
