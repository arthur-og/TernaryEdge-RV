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

`ioctl-abi` currently passes while proving the current 204-byte IOCTL layout,
including eight 24-byte layer descriptors.

`weights-header` checks the current header's packed contract and expected FP32
symbols. The current header has the FP32 symbols, but its fallback values,
including `0.01` and `0.1`, are not validated trained parameters. The packed
contract currently present is:

- `QUANT_DENSE_PACKED_WORDS` and `quant_dense_weights`
- `QUANT_DENSE_1_PACKED_WORDS` and `quant_dense_1_weights`
- `QUANT_DENSE_2_PACKED_WORDS` and `quant_dense_2_weights`

The FP32 symbols required by `software/npu_hal/npu_weights.c` are:

- `OUTPUT_WEIGHTS_COUNT`
- `OUTPUT_BIAS_COUNT`
- `output_weights`
- `output_bias`

The checker validates the contractual counts: `50176`,
`32768`, `8192`, `2560`, and `10`.

The target checks declarations and counts only. It does not claim that fallback
values are trained model values, and it does not fabricate model data.

The RISC-V cross-compiler `riscv32-buildroot-linux-gnu-gcc` is not available
on the current native PATH; these targets therefore intentionally use the
native compiler only.

The canonical RTL regression is available through the repository hardware
flake:

```bash
nix develop .#hardware --command make -C hardware/npu_rtl test
nix develop .#hardware --command make -C hardware/npu_rtl lint
nix develop .#hardware --command make -C hardware/npu_rtl synth
```

These checks do not establish FPGA end-to-end inference or a CPU-versus-NPU
benchmark. The RISC-V cross-compiler and physical device remain separate
validation steps.
