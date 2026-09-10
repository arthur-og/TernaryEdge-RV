# Scientific Thesis & Motivation: Ternary Edge-RV

## 1. The Problem: The Extreme Edge Question
As Artificial Intelligence moves toward the extreme edge, systems may need local inference while also providing networking, storage, and control services. A general-purpose processor can provide those abstractions, but its energy and latency cost for neural workloads must be measured rather than assumed. A dedicated accelerator can reduce the processor workload, but its system-level benefit depends on integration overhead, memory traffic, interrupt behavior, and the physical implementation.

This project therefore treats the edge trade-off as a falsifiable research question. It does not assume that CPU execution exhausts an energy budget, that a bare-metal accelerator is commercially impossible, or that either approach has a fixed power advantage before measurement.

## 2. The Proposed Co-Design
**Ternary Edge-RV** studies a co-design that combines a LiteX-generated RV32IMA system with Linux software and a source-level ternary NPU. The canonical RTL integrates 64 ternary PEs, a registered 64-to-1 tree, a scalar INT32 accumulator, banked activations, a three-stage postprocessor, up to eight software-programmed descriptors, and bounded single-beat Wishbone Classic DMA with downstream `ERR` propagation and a 256-cycle timeout.

The ternary PE datapath is multiplierless because weights select addition, zero, or subtraction. Signed requantization intentionally contains a general multiplier, however, so the physical DSP count is unknown until Vivado synthesis and resource reports are available. The host ABI exposes 17 MMIO offsets from `0x00` through `0x40`. The current host evidence establishes RTL behavior, not FPGA resource use, timing, power, area, or energy.

That host evidence consists of focused Icarus tests and the 16/32/64-PE matrix, including a production-sized `784->1024->512->256` regression with nonuniform high-row weights: outputs 0..254 equal `65024`, while output 255 equals `-65024`. Verilator lint, generic Yosys synthesis and `synth_matrix` pass, as do the 12/12 report-gate unit tests. The historical C++ v2 result of 21/21 is secondary evidence, not canonical RTL proof.

## 3. Host Contracts and Interrupt Path
The software contracts describe an IRQ-driven kernel path. The driver source includes an IRQ handler and a wait queue, and the HAL exposes the sequence `npu_init()` to `npu_predict()` to `npu_deinit()`. These source and host contracts allow a measurable comparison between polling and interrupt-driven execution, but they do not guarantee CPU sleep duration, scheduling behavior, interrupt delivery, or energy savings on a physical Linux system.

The physical Linux and board behavior remain unverified. In particular, boot, MMIO integration, IRQ delivery, DMA completion and error handling, inference output, latency, throughput, power, and energy require a deployed FPGA and measured runtime evidence.

## 4. Formal Hypothesis
> *A Linux-capable RISC-V system paired with a ternary NPU can reduce measured CPU work and system energy for a defined inference workload relative to CPU-only execution, without unacceptable integration overhead. The hypothesis will be evaluated using the canonical RTL host regressions first, then Vivado resource and timing reports, and finally physical board measurements of boot, IRQ, DMA, inference, latency, throughput, power, and energy. The hypothesis is not considered demonstrated until those measurements are available.*
