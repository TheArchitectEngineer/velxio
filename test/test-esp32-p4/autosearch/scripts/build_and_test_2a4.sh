#!/usr/bin/env bash
set -e
cd /root/qemu-lcgamboa

# Sync source from NTFS-mounted Windows path
rsync -a --no-perms --no-times \
  /mnt/c/Desarrollo/velxio/third-party/qemu-lcgamboa/hw/riscv/esp32p4.c \
  hw/riscv/esp32p4.c

dos2unix hw/riscv/esp32p4.c 2>/dev/null

# Build
cd /root/qemu-p4-build
make -j$(nproc) qemu-system-riscv32 2>&1 | tail -10

echo "=== Build done. Running test ==="

cd /root
timeout 5 /root/qemu-p4-build/qemu-system-riscv32 \
  -M esp32p4 \
  -bios /root/p4rom.elf \
  -drive file=/root/blink.merged.bin,if=mtd,format=raw \
  -nographic 2>&1 | head -60 || true

echo "=== End of run ==="
