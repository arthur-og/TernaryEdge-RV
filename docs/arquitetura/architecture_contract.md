# Architecture Contract: Ternary Edge-RV
**Última atualização:** 24/08/2026
**Versão:** 2.6 (Current integration contract)

This document formalizes the architectural decisions and "Design by Contract" parameters that all team members must follow to ensure the successful integration of the Hardware (RTL), OS (Linux), Kernel Driver (LKM), HAL (NPU Abstraction), and User Space (AI) components.

---

## 1. System Architecture Standard (32-Bit) & Team Roles
**Decision:** The entire stack will strictly use **RV32IMA** (32-bit RISC-V).
**Justification:** The project aims to demonstrate extreme energy efficiency and area reduction on FPGA. A 64-bit architecture consumes significantly more logic (LUTs/FFs) and memory bandwidth without offering tangible benefits for ternary quantized operations.

### Team Roles & Operational Responsibilities (post-Gilvan transition)
*   **Arthur Oliveira Gomes (Hardware Architecture & RTL):** Hardware RTL, LiteX SoC VexRiscv generation, Verilog regression testbench, openXC7 synthesis (with flags `-nolutram -nowidelut`), Vivado synthesis, bitstream generation and FPGA resource report.
*   **Gildo Alves de Lima Junior (OS Infrastructure & HAL):** Buildroot OS configuration (`BR2_RISCV_32=y`), Device Tree (`urrbana.dts`), NPU HAL (`libnpu_hal.a`), Output Classifier (FP32 CPU), MicroSD card image preparation and physical Linux boot on Urbana.
*   **Gustavo Alexandre dos Santos (AI Pipeline, Weights, Golden Model, Kernel Driver & Validation):** Current AI pipeline maintenance, weight export and `weights.h` contract, C++ Golden Model regression and maintenance, kernel driver (`npu_driver.ko`), RV32 cross-compilation (`-march=rv32ima -mabi=ilp32`), physical validation coordination, CPU-versus-NPU benchmarks, and results and discussion for Paper 1.
*   **Gilvan Alves Pastor Junior (Historical AI & Golden Model):** Historical QAT pipeline (Larq/STE), ternary packing, and C++ Golden Model v2 retained and credited as the 4th author on Paper 1. Gilvan has no current operational ownership.

---

## 2. NPU Memory Map and Integration Contract

**NPU MMIO base:** `0x80000000`
**DDR base:** `0x40000000`
**IRQ Number:** `10` (connected to the VexRiscv PLIC)
**Endianness:** Little endian (native RISC-V)
**Bus Interface:** Wishbone B4, 32-bit data and 32-bit address, with a CPU
slave for MMIO and a master for DMA

The NPU MMIO and DDR regions are distinct.

### Register Layout

| Offset | Register | Width | R/W | Description |
|:-------|:--------|:------|:----|:------------|
| `0x00` | `STATUS` | 32 | RO | bit 0 busy, bit 1 IRQ, bit 2 done, bit 3 error, layer in bits 15:8 |
| `0x04` | `CONTROL` | 32 | WO | bit 0 START, bit 1 CLEAR_IRQ |
| `0x08` | `INPUT_ADDR` | 32 | RW | External RAM address for the first input |
| `0x0C` | `OUTPUT_ADDR` | 32 | RW | External RAM address for final INT32 output |
| `0x10` | `WEIGHT_ADDR` | 32 | RW | Selected descriptor packed weight address |
| `0x14` | `BIAS_ADDR` | 32 | RW | Selected descriptor INT32 bias address, zero means bias 0 |
| `0x18` | `SCALE_ADDR` | 32 | RW | Selected descriptor INT32 multiplier address, zero means 1 |
| `0x1C` | `LAYER_COUNT` | 32 | RW | Number of descriptors, 1 through 8 |
| `0x20` | `LAYER_INDEX` | 32 | RW | Descriptor selected by the following layer registers |
| `0x24` | `LAYER_INPUTS` | 32 | RW | Selected layer input count |
| `0x28` | `LAYER_OUTPUTS` | 32 | RW | Selected layer output count |
| `0x2C` | `LAYER_QUANT` | 32 | RW | Shift in bits 5:0, ReLU in bit 8 |
| `0x30` | `RESULT` | 32 | RO | First final output for quick status inspection |
| `0x34` | `RESULT_WINDOW` | 32 | RO | Selected descriptor-index accumulator window |
| `0x38` | `ERROR_INFO` | 32 | RO | Sticky error code |
| `0x3C` | `CAPABILITIES` | 32 | RO | `0x00080440`: 8 layers, 1024 activations, 64 PEs |
| `0x40` | `MAC_CFG` | 32 | RW | Must be 64, reserved for future narrower modes |

### DMA Transaction Flow
1. Driver writes the input and output addresses and the descriptor table through the MMIO ABI.
2. Driver writes `NPU_CONTROL.START = 1`.
3. The NPU issues bounded, single-beat Wishbone Classic DMA requests. Each request uses `CTI=000` and `BTE=00`, and remains stable until `ACK` or downstream `ERR`.
4. A downstream `ERR` reaches the NPU error path. No response within 256 cycles becomes a DMA timeout error.
5. The NPU computes with its 64 integrated ternary PEs, registered 64-to-1 tree, scalar accumulator, banked activation storage, and postprocessor.
6. The NPU writes final INT32 results to `OUTPUT_ADDR` and asserts `irq_out`.
7. The CPU wakes, reads status or results, and clears IRQ.

---

## 3. Parallelism and Datapath

The integrated NPU has **64 physical ternary PEs** operating in parallel and a
registered 64-to-1 adder tree. The host test matrix also checks parameterized
16, 32 and 64 PE variants, but the SoC integration contract is 64 PEs.

Activation storage consists of two ping-pong buffers banked by `NUM_PES`. Each
neuron uses one scalar signed INT32 accumulator. The three-stage registered
postprocessor adds signed INT32 bias, forms a signed 65-bit product with the
intentional signed integer scale multiplier, then rounds ties away from zero,
shifts, clamps to INT32 and saturates hidden activations to INT8. The PE
datapath is multiplierless; this does not imply zero total DSP use in a
physical implementation.

*   **Arthur:** Owns the RTL array, registered tree, accumulator, banked activation storage, postprocessor, and integration. Physical resource use is pending synthesis.
*   **Memory:** Packed weights and activation data are transferred as bounded single-beat DMA requests; there is no burst contract.
*   **Descriptor capacity:** The controller accepts up to eight layer descriptors. It does not hard-code a three-layer network.

---

## 4. Synchronization Mechanism (IRQ vs. Polling)
**Decision:** The NPU will notify the CPU of completion via **Hardware Interrupts (IRQ)**.
**Justification:** Polling wastes CPU cycles and significantly increases power consumption, defeating the purpose of an energy-efficient edge accelerator.

*   **Arthur:** The RTL design exposes an `irq_out` pin intended to go high when inference finishes; this behavior remains subject to RTL and physical validation.
*   **Gildo:** The Device Tree (`.dts`) must map IRQ line `10` to the NPU node. The HAL must wait for the driver's IRQ-based ioctl.
*   **Gustavo:** The kernel driver is intended to use `devm_request_irq()` + `wait_event_interruptible()`, with CPU usage and interrupt behavior pending physical validation.

---

## 5. Benchmarking Timing Segregation
**Decision:** Time profiling must be broken down into three distinct phases.
**Justification:** Need to isolate pure NPU compute from DMA setup and driver overhead.

*   **Gildo (HAL):** `npu_result_t` must capture:
  1. `time_copy_us`: Time to copy image → DMA buffer
  2. `time_npu_us`: Time waiting for the NPU IRQ (pure hardware compute)
  3. `time_output_us`: Time for CPU output layer (256→10)
  4. `time_total_us`: Wall clock from start to finish

---

## 6. Endianness & Data Packing
**Decision:** Little-Endian ordering, matching standard VexRiscv behavior.
**Justification:** 2-bit ternary weights ($\in \{-1, 0, 1\}$) are packed into 32-bit integers.

*   **Historical contribution by Gilvan, retained in the hardware record:** `weights[0]` occupies the LSBs of the 32-bit word. Encoding: `+1 = 0b01`, `0 = 0b00`, `-1 = 0b11`.
*   **Gildo (HAL):** The HAL reads weights from `weights.h` (pipeline output) and copies them verbatim to the DMA buffer: no byte-swapping needed.
*   **Gustavo:** Maintains the current export and `weights.h` contract against the HAL and driver.

---

## 7. Architecture Overview (v2: Full Stack)

```text
User Space
  ┌─────────────────────────────────┐
  │  user_app (Gildo)               │
  │   ┌───────────────────────┐     │
  │   │  NPU HAL (Gildo)      │     │  ← NOVA CAMADA
  │   │  npu_init()           │     │
  │   │  npu_load_weights()   │     │
  │   │  npu_predict()        │     │
  │   │  npu_deinit()         │     │
  │   └──────────┬────────────┘     │
  │              │                   │
  │              │ ioctl / mmap     │
  └──────────────┼───────────────────┘
                 │
Kernel Space     │
  ┌──────────────┼───────────────────┐
  │  npu_driver (Gustavo)           │
  │  /dev/npu_ternaria              │
  │  - iowrite32 to NPU regs       │
  │  - dma_alloc_coherent          │
  │  - wait_event_interruptible    │
  │  - IRQ handler → wake_up       │
  └──────────────┬───────────────────┘
                 │
                 │ Wishbone Bus
                 ▼
Hardware
  ┌─────────────────────────────────┐
  │  LiteX SoC (Arthur)             │
  │  VexRiscv RV32IMA               │
  │    │                            │
  │    ├── NPU v2 (Arthur)          │
  │    │   64 integrated ternary PEs│
  │    │   registered 64-to-1 tree  │
  │    │   banked INT8 activation   │
  │    │   bounded Classic DMA      │
  │    │   IRQ → PLIC               │
  │    │                            │
  │    ├── DDR3 (128 MB)           │
  │    │   @ 0x40000000             │
  │    │                            │
  │    └── Peripherals (UART, SD,   │
  │        SPI flash, LEDs, etc.)   │
  └─────────────────────────────────┘
```

---

## 8. Data Flow per Layer

```
Weights in RAM:     [word0][word1]...[wordN]  ← packed 16 weights/word
Activations in RAM: [act0][act1]...[actM]     ← INT8 values

Layer and tile flow:
  1. The NPU uses bounded single-beat DMA to load external data and write final results.
  2. Packed ternary weights and INT8 activations are placed in the local banked buffers.
  3. The 64 integrated PEs compute multiplierless signed products in parallel.
  4. The registered 64-to-1 tree combines the partial sums into the scalar INT32 accumulator.
  5. The three-stage postprocessor applies bias, signed integer scale, rounding, shift and saturation.
  6. The descriptor controller advances through up to eight configured layers without CPU intervention.
```

---

## 9. NPU HAL (Hardware Abstraction Layer)

**Rationale:** The NPU v2 PE path is purely ternary and multiplierless. Its
fixed-point postprocessor intentionally includes a signed integer multiplier,
but the documented software flow keeps the final `256->10` FP32 layer and
softmax on the CPU. The HAL encapsulates:

1. **Device initialization** (`npu_init`): opens `/dev/npu_ternaria`, mmaps DMA buffer
2. **Weight loading** (`npu_load_weights`): copies ternary weights from `weights.h` to DMA
3. **Inference** (`npu_predict`): copies input image, triggers ioctl, reads NPU output
4. **Output layer** (internal): runs 256->10 FP32 classification on CPU via `classifier_run()`
5. **Batch inference** (`npu_predict_batch`): repeats predict for N images

### DMA Buffer Layout

| Offset | Size | Content |
|--------|------|---------|
| `0x000000` | Current software result area | Final INT32 features |
| `0x001000` | Current software reservation | Packed ternary weights |
| `0x05C000` | Current software reservation | Input activation bytes |
| `0x05F000` | Current software reservation | Quantized INT32 biases |
| `0x061000` | Current software reservation | Quantized INT32 scale multipliers |

* **Gildo (HAL):** Owns the HAL design, implementation, and test.
* **Gustavo (Driver):** The HAL depends on the driver's ioctl interface: must remain stable.
* **Gustavo (AI and weights):** Maintains the `weights.h` format expected by the HAL, including per-layer arrays and output weights.

---

## 10. NPU Classifier (CPU Fallback)

**Decision:** The output layer (256→10) runs on the CPU, not the NPU.

**Justification:** The NPU v2 has no FP32 multiplier. A historical host-side comparison of a ternary output layer (Opção A) reported accuracy below 90%. The adopted design (Opção B) targets 3 ternary layers in the NPU and CPU execution for the final FP32 classification.

```
NPU output: 256 × int32 (accumulated ternary products)
    │
    ▼
Classifier (CPU):
  for each class c (0..9):
    score[c] = bias[c] + Σ(i=0..255) npu_output[i] × output_weights[c][i]
  predicted = argmax(score)
  confidence = softmax(score)
```

* **Gildo (HAL):** Implements `classifier_run()` inside the HAL.
* **Gustavo:** Maintains the output-weight export and regression contract. Gilvan's historical QAT and packing contribution remains credited. Current FP32 symbols use fallback values and are not validated trained parameters.

---

## 11. Verification and Handoff

The canonical host-side RTL commands are:

```sh
make -C hardware/npu_rtl test
make -C hardware/npu_rtl test_matrix
make -C hardware/npu_rtl lint_matrix
python3 -m unittest hardware.litex_soc.test_check_vivado_reports
```

The Python golden model and `sim_cpp` are auxiliary or legacy checks. They are
not canonical proof of the current RTL. The Vivado report gate is run from the
repository root after Vivado completes:

```sh
python3 hardware/litex_soc/check_vivado_reports.py
```

Vivado is the final production flow. openXC7 is optional host-side
corroboration. The synthesis, place and route, bitstream, physical resource,
timing, IRQ/DMA, and performance procedures remain pending handoff work. The
heavy commands above are documented procedures, not claimed executions.

Historical Vivado artifacts are explicitly stale and rejected by the report
gate. They omitted `postprocess_unit.v` and recorded WNS `-7.392 ns` and TNS
`-35888.277 ns`. Those values are rejected historical evidence, not current
results.

**Current host contract:** The canonical RTL regression and lint matrix are
the current passing host evidence. No FPGA end-to-end inference or
CPU-versus-NPU benchmark is proven.

| Task / Gap | Impact | Active Owner | Priority | Status / Resolution Path |
|:-----------|:-------|:-------------|:---------|:-------------------------|
| **FPGA Synthesis & Bitstream** | Physical bitstream loading | Arthur | **Critical** | Vivado is the final production flow. Handoff: `nix develop .#vivado`, then `cd hardware/litex_soc` and `python3 base_soc.py --build --toolchain vivado`; physical resources, timing and bitstream remain pending |
| **Linux Boot on FPGA** | Physical OS execution | Gildo | **High** | Buildroot image -> SD card (FAT32+ext4) -> boot via OpenSBI -> U-Boot -> kernel on Urbana |
| **Driver `insmod` on Physical Hardware** | `/dev/npu_ternaria` device node | Gustavo | **High** | Cross-compile `.ko` for RV32IMA, `insmod`, validate IRQ/DMA via `dmesg` |
| **Real Benchmark (CPU vs NPU latency)** | Paper 1 Section IV metrics | Gustavo | **High** | Gustavo coordinates physical validation with Arthur and Gildo; `user_app --cpu` versus default remains pending |
| **Paper 1 Sections & Submission** | SBCCI/LASCAS paper draft | Team (4 Authors) | **High** | Target completion date: 31/08/2026; template at `paper/paper1_template.tex` |
