# Software Contract Diagnostics

These are native C diagnostics for the first staged software repair. They are
not end-to-end inference tests and do not require the NPU device, kernel
driver, cross-toolchain, or generated model data to run the IOCTL ABI check.

Gustavo owns the current AI export, `weights.h` contract, Golden Model
regression, RV32 cross-compilation and physical validation coordination. Gildo
owns the OS, Buildroot, HAL, classifier, MicroSD and Linux boot path.

## Targets

```text
make -C software/tests ioctl-abi
make -C software/tests weights-header
make -C software/tests clean
```

`ioctl-abi` proves the current 20-byte IOCTL layout and the 60,416-byte ternary
weight footprint passed through `dma_size`.

`weights-header` checks the current trained header's packed contract and
expected FP32 symbols. The packed contract currently present is:

- `QUANT_DENSE_PACKED_WORDS` and `quant_dense_weights`
- `QUANT_DENSE_1_PACKED_WORDS` and `quant_dense_1_weights`
- `QUANT_DENSE_2_PACKED_WORDS` and `quant_dense_2_weights`

The FP32 symbols required by `software/npu_hal/npu_weights.c` are:

- `OUTPUT_WEIGHTS_COUNT`
- `OUTPUT_BIAS_COUNT`
- `output_weights`
- `output_bias`

The checker validates the contractual counts: `12544`, `2048`, `512`, `640`,
and `10`.

The target checks declarations and counts only. Model accuracy and parameter
provenance are validated by the AI pipeline, not by this native C diagnostic.

The RISC-V cross-compiler `riscv32-buildroot-linux-gnu-gcc` is not available
on the current native PATH; these targets therefore intentionally use the
native compiler only.

The Verilog v2 testbench passes in the repository Nix shell. No FPGA end-to-end
inference or CPU-versus-NPU benchmark is established by these host checks.
