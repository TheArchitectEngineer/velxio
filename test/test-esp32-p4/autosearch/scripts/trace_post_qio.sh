#!/usr/bin/env bash
# Trace bootloader execution looking for what it polls after qio_mode
cd /root
/root/qemu-p4-build/qemu-system-riscv32 \
  -M esp32p4 \
  -bios /root/p4rom.elf \
  -drive file=/root/blink.merged.bin,if=mtd,format=raw \
  -nographic \
  -d in_asm -D /root/qpost_qio.log > /root/qpost_qio_stdout.log 2>&1 &
QPID=$!
sleep 60
kill -15 $QPID 2>/dev/null
wait 2>/dev/null

echo "=== Last stdout ==="
tail -10 /root/qpost_qio_stdout.log
echo
echo "=== Trace log size ==="
wc -l /root/qpost_qio.log
echo
echo "=== Top 10 hot PCs (looking for polling loop) ==="
grep -oE '0x4(ff|fc)[0-9a-f]{5}' /root/qpost_qio.log | sort | uniq -c | sort -rn | head -10
echo
echo "=== Last 30 lines of trace ==="
tail -30 /root/qpost_qio.log
