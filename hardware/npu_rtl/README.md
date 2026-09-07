# NPU v2 RTL

`npu_ternaria_top_v2` is the canonical implementation.  `npu_ternaria_top`
is retained as a small v1 compatibility target only; it is not used by the
SoC integration.

## Architecture

The CPU writes the input/output addresses and a table of up to eight layer
descriptors, then writes `CONTROL.START` once.  The NPU performs the complete
network without CPU intervention:

```text
external RAM --DMA--> activation A
                         |
                 64 ternary PEs
                         |
                 balanced 64->1 tree
                         |
                 INT32 neuron accumulator
                         |
                 bias + fixed-point scale + ReLU/saturation
                         |
                 activation B <-> activation A
                         |
                 final INT32 logits --DMA--> external RAM
```

The integrated configuration has 64 physical ternary PEs and a six-stage
registered 64-to-1 tree.  Its two ping-pong activation buffers store 1024
signed INT8 values each in banks indexed by `NUM_PES`.  A layer may use any
positive input/output dimension up to 1024, including a final tile shorter
than 64 values.  A scalar signed INT32 accumulator collects each neuron's
batch sums.  The final layer writes one signed INT32 word per output neuron;
hidden layers write signed INT8 values into the opposite banked buffer.

## Arithmetic Contract

The PE encoding is `00=0`, `01=+1`, `11=-1`; `10` is reserved and causes a
sticky error if it occurs in a valid lane.  An INT8 activation is sign
extended to 9 bits before negation, so `-128` maps to `+128` for weight `-1`.
The tree has six registered stages and produces a 15-bit signed batch sum.
The accumulator is signed INT32 and wraps in two's complement, which is safe
for the supported INT8 dimensions when the model stays within the INT32
contract.

Each layer's `SCALE_ADDR` points to signed INT32 multipliers, one per output
neuron.  Address zero means identity multiplier.  `LAYER_QUANT[5:0]` is the
arithmetic right-shift amount and `LAYER_QUANT[8]` enables hidden-layer ReLU.
The postprocessor is a three-stage registered pipeline.  It adds signed INT32
bias, performs an intentional signed integer multiplication in a signed
65-bit product stage, then rounds ties away from zero, shifts arithmetically,
clamps to INT32, and saturates hidden activations to INT8.  The effective
scale is `multiplier / 2**shift`.  The ternary PE datapath itself is
multiplierless.

## SoC Integration Contract

The NPU MMIO aperture starts at `0x80000000` and reserves 64 KiB. Only the 17
register offsets through `0x40` are valid; every other offset in the aperture
returns a Wishbone error instead of stalling or aliasing a register.

External DDR starts at `0x40000000`; these are distinct regions.

The NPU interrupt is IRQ `10`, and all MMIO words use little-endian byte order.

The DMA interface is a bounded, single-beat Wishbone Classic master.  Each
request holds one 32-bit transfer stable until `ACK` or downstream `ERR`, with
`CTI=000` and `BTE=00`.  Downstream `ERR` is propagated to the NPU error path.
If neither response arrives within 256 cycles, the request is cancelled and
reported as a DMA error.

## MMIO Map

All registers are 32-bit, byte addressed and little endian.  Invalid offsets
return a Wishbone error.  `CONTROL.START` while running is ignored and sets
`ERROR_INFO=ERR_BUSY`; `CONTROL.CLEAR_IRQ` clears a sticky DONE/ERROR/IRQ
condition and returns the controller to IDLE.

| Offset | Register | Access | Meaning |
|---:|---|:---:|---|
| `0x00` | STATUS | R | bit 0 busy, bit 1 IRQ, bit 2 done, bit 3 error; layer in bits 15:8 |
| `0x04` | CONTROL | W | bit 0 START, bit 1 CLEAR_IRQ |
| `0x08` | INPUT_ADDR | RW | external RAM address for the first input |
| `0x0c` | OUTPUT_ADDR | RW | external RAM address for final INT32 output |
| `0x10` | WEIGHT_ADDR | RW | selected descriptor's packed weight address |
| `0x14` | BIAS_ADDR | RW | selected descriptor's INT32 bias address; zero means bias 0 |
| `0x18` | SCALE_ADDR | RW | selected descriptor's INT32 multiplier address; zero means 1 |
| `0x1c` | LAYER_COUNT | RW | number of descriptors, 1..8 |
| `0x20` | LAYER_INDEX | RW | descriptor selected by the following layer registers |
| `0x24` | LAYER_INPUTS | RW | selected layer input count |
| `0x28` | LAYER_OUTPUTS | RW | selected layer output count |
| `0x2c` | LAYER_QUANT | RW | shift in bits 5:0, ReLU in bit 8 |
| `0x30` | RESULT | R | first final output, for quick status inspection |
| `0x34` | RESULT_WINDOW | R | selected descriptor-index accumulator window |
| `0x38` | ERROR_INFO | R | sticky error code |
| `0x3c` | CAPABILITIES | R | `0x00080440`: 8 layers, 1024 activations, 64 PEs |
| `0x40` | MAC_CFG | RW | must be 64; reserved for future narrower modes |

STATUS remains non-busy in DONE and ERROR states.  IRQ remains asserted until
the CPU explicitly writes `CONTROL.CLEAR_IRQ`.

## Weight and Model Format

Weights are output-major.  For a layer with `input_count` inputs, one output
row occupies `ceil(input_count/16)` 32-bit words.  Weight `i` occupies bits
`[2*i+1:2*i]` of the word, and the first word is at the lowest address:

```text
weight[0]  -> word[1:0]
weight[15] -> word[31:30]
```

The exporter writes `NPU_MODEL_FORMAT_VERSION=2` and emits INT32 bias and
multiplier arrays beside every quantized layer.  It transposes Keras matrices
from `(input, output)` to the output-major layout expected by the RTL.  The
versioned fallback `weights.h` fixture does not define
`NPU_MODEL_HAS_QUANT_PARAMS`, so the HAL deliberately programs zero bias and
identity scale for that fixture.  A header generated from a model defines the
macro and supplies those arrays.  The
current software default reserves:

```text
0x001000  packed weights
0x05c000  input activation bytes
0x05f000  quantized INT32 biases
0x061000  quantized INT32 scale multipliers
0x000000  final INT32 features
```

The kernel ioctl carries byte offsets into its coherent DMA buffer and eight
complete layer descriptors.  The driver validates dimensions, alignment,
weight footprints and layer-to-layer shape agreement before programming MMIO.

## Verification

From the repository root, the canonical RTL checks are:

```sh
make -C hardware/npu_rtl test
make -C hardware/npu_rtl test_matrix
make -C hardware/npu_rtl lint_matrix
python3 -m unittest hardware.litex_soc.test_check_vivado_reports
```

The RTL tests include PE extreme values, reserved encoding, balanced-tree
boundary values, delayed DMA responses, a complete `8->5->3` network, bias,
ReLU, partial layer tiles, ping-pong propagation, final output writes and
sticky IRQ.  The Python golden model and the C++ simulator in `sim_cpp/` are
auxiliary and legacy checks, respectively.  Neither is canonical proof of the
RTL.  In particular, `make -C hardware/npu_rtl test` runs only the current
Icarus Verilog tests.

The canonical host regression and lint matrix are the current passing host
evidence.  They do not establish physical FPGA resources, timing, bitstream,
IRQ/DMA behavior or performance.

The C++ v2 simulator predates this descriptor ABI and is kept as
`legacy_demo_v2`; it is not a proof of the canonical RTL.

## Synthesis Notes

The generic Yosys target checks elaboration and synthesis.  The ternary path
has 64 source-level PE instances and a 63-adder registered tree.  Scale
requantization is the only intentional integer multiplication; ternary weights
use PE mux/negation logic.  Vivado is the final production flow.  openXC7 is
optional host-side corroboration.  Vivado/openXC7 physical resources, timing,
bitstream generation, the physical IRQ/DMA path, and performance remain
pending.

The following root-level command is the handoff gate after Vivado completes;
it is a procedure, not a claim that the heavy Vivado flow has run:

```sh
python3 hardware/litex_soc/check_vivado_reports.py
```

Historical Vivado artifacts are stale and are rejected by this gate.  They
omitted `postprocess_unit.v` and recorded WNS `-7.392 ns` and TNS
`-35888.277 ns`; those values are non-current failure evidence, not production
results.
