#!/usr/bin/env bash
# Run longer with verbose tracing to see post-banner behavior
cd /root
timeout 8 /root/qemu-p4-build/qemu-system-riscv32 \
  -M esp32p4 \
  -bios /root/p4rom.elf \
  -drive file=/root/blink.merged.bin,if=mtd,format=raw \
  -nographic \
  -d unimp,guest_errors -D /root/qrun_2a4.log 2>&1 | head -80 || true

echo
echo "=== Last 50 lines of qrun_2a4.log ==="
tail -50 /root/qrun_2a4.log 2>/dev/null

echo
echo "=== Total log lines ==="
wc -l /root/qrun_2a4.log 2>/dev/null
