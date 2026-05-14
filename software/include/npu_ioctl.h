#ifndef _NPU_IOCTL_H
#define _NPU_IOCTL_H

#include <linux/ioctl.h>

#define NPU_MAGIC 'N'

/* 
 * IOCTL Command to start the NPU inference.
 * Takes the size of the payload (in bytes) as argument.
 * The driver will block (sleep) until the hardware IRQ fires.
 */
#define NPU_IOCTL_START_INFERENCE _IOW(NPU_MAGIC, 1, unsigned int)

/* Size of the DMA Coherent Buffer allocated by the driver (e.g., 4MB) */
#define NPU_DMA_BUFFER_SIZE (4 * 1024 * 1024)

#endif /* _NPU_IOCTL_H */
