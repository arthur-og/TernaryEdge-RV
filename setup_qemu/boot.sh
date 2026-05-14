#!/bin/bash
# Script de boot para QEMU RISC-V com Debian

QEMU_DIR="/home/gustavo/projects/TernaryEdge-RV/setup_qemu/dqib_riscv64-virt"

qemu-system-riscv64 \
  -machine 'virt' \
  -cpu 'rv64' \
  -m 4G \
  -dtb "$QEMU_DIR/../qemu_npu.dtb" \
  -device virtio-blk-device,drive=hd \
  -drive file="$QEMU_DIR/image.qcow2",if=none,id=hd \
  -device virtio-net-device,netdev=net \
  -netdev user,id=net,hostfwd=tcp:127.0.0.1:2222-:22 \
  -kernel "$QEMU_DIR/kernel" \
  -initrd "$QEMU_DIR/initrd" \
  -append "root=LABEL=rootfs rw console=ttyS0" \
  -nographic