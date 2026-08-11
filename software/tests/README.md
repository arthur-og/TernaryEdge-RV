# Software Contract Diagnostics

These are native C diagnostics for the first staged software repair. They are
not end-to-end inference tests and do not require the NPU device, kernel
driver, cross-toolchain, or generated model data to run the IOCTL ABI check.

## Targets

```text
make -C software/tests ioctl-abi
make -C software/tests weights-header
make -C software/tests clean
```

`ioctl-abi` should exit zero while proving the current 20-byte IOCTL layout.
It also reports that `dma_size` is documented in bytes even though the
current HAL passes the packed-word total.

`weights-header` is an expected-failure diagnostic with the current checked-in
header. The packed contract currently present is:

- `QUANT_DENSE_PACKED_WORDS` and `quant_dense_weights`
- `QUANT_DENSE_1_PACKED_WORDS` and `quant_dense_1_weights`
- `QUANT_DENSE_2_PACKED_WORDS` and `quant_dense_2_weights`

The symbols currently missing for `software/npu_hal/npu_weights.c` are:

- `OUTPUT_WEIGHTS_COUNT`
- `OUTPUT_BIAS_COUNT`
- `output_weights`
- `output_bias`

When present, the checker also validates the contractual counts: `50176`,
`32768`, `8192`, `2560`, and `10`.

The target returns nonzero for that known missing-symbol contract failure. It
does not add declarations or fabricate model values. Once the real generated
header supplies the missing symbols, the same target compiles and checks the
declared array counts.

The RISC-V cross-compiler `riscv32-buildroot-linux-gnu-gcc` is not available
on the current native PATH; these targets therefore intentionally use the
native compiler only.
