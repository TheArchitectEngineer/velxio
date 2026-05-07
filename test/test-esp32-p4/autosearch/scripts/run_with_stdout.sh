#!/usr/bin/env bash
# Run capturing stdout to see bootloader prints
cd /root
( /root/qemu-p4-build/qemu-system-riscv32 \
    -M esp32p4 \
    -bios /root/p4rom.elf \
    -drive file=/root/blink.merged.bin,if=mtd,format=raw \
    -nographic 2>&1 ) > /root/qrun_stdout.log &
QEMU_PID=$!
sleep 5
kill -15 $QEMU_PID 2>/dev/null || true
wait 2>/dev/null

echo "=== Full stdout ==="
cat /root/qrun_stdout.log
