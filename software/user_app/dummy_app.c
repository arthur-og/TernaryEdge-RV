#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mmap.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <string.h>

#include "../include/npu_ioctl.h"

#define DEVICE_PATH "/dev/npu_ternaria"

int main() {
    int fd;
    uint32_t *dma_buffer;
    unsigned int payload_size = 1024; /* Let's simulate a 1KB ternary payload */
    struct timeval start, end;
    long latency_us;

    printf("=== TernaryEdge-RV Zero-Copy DMA Inference App ===\n");

    /* 1. Open the Device */
    fd = open(DEVICE_PATH, O_RDWR);
    if (fd < 0) {
        perror("Failed to open NPU device (is the driver loaded?)");
        return EXIT_FAILURE;
    }

    /* 2. Map the DMA memory directly to user space (Zero-Copy) */
    dma_buffer = mmap(NULL, NPU_DMA_BUFFER_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (dma_buffer == MAP_FAILED) {
        perror("Failed to mmap DMA buffer");
        close(fd);
        return EXIT_FAILURE;
    }
    printf("[+] DMA Buffer mapped successfully at %p\n", dma_buffer);

    /* 3. Prepare the Payload (The AI team will fill this with their uint32_t packed weights) */
    printf("[+] Packing ternary weights into DMA buffer...\n");
    memset(dma_buffer, 0xAA, payload_size); /* Dummy packing */

    /* 4. Trigger Hardware Inference and Benchmark */
    printf("[+] Triggering inference via IOCTL. CPU will now sleep...\n");
    
    gettimeofday(&start, NULL);
    
    /* This IOCTL blocks until the hardware DMA and NPU finish (IRQ fires) */
    if (ioctl(fd, NPU_IOCTL_START_INFERENCE, &payload_size) < 0) {
        perror("IOCTL Start Inference failed");
    }

    gettimeofday(&end, NULL);

    /* 5. Calculate Latency */
    latency_us = (end.tv_sec - start.tv_sec) * 1000000 + (end.tv_usec - start.tv_usec);
    printf("[+] Inference completed! Hardware woke up the CPU.\n");
    printf("[+] Hardware Latency: %ld microseconds\n", latency_us);

    /* 6. Read Results (Assuming hardware writes back to the same buffer or another offset) */
    printf("[+] Reading result from buffer: 0x%08X\n", dma_buffer[0]);

    /* Cleanup */
    munmap(dma_buffer, NPU_DMA_BUFFER_SIZE);
    close(fd);

    return EXIT_SUCCESS;
}
