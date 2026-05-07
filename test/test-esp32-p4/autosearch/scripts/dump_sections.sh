#!/usr/bin/env bash
# Dump all PROGBITS sections that overlap 0x4FF3FF00..0x4FF40000
echo "=== All PROGBITS sections in 0x4FF3FFxx range ==="
riscv64-unknown-elf-readelf -W -S /root/p4rom.elf 2>/dev/null | \
  awk '/PROGBITS/ { if (strtonum("0x"$5) >= 0x4FF3FF00 && strtonum("0x"$5) < 0x4FF40000) print $0 }'

echo
echo "=== Data table @ 0x4FC1BEC8 (33 entries x 12 bytes) ==="
riscv64-unknown-elf-objdump -s --start-address=0x4FC1BEC8 --stop-address=0x4FC1C054 /root/p4rom.elf 2>/dev/null | head -40

echo
echo "=== BSS table @ 0x4FC1C054 (32 entries x 8 bytes) ==="
riscv64-unknown-elf-objdump -s --start-address=0x4FC1C054 --stop-address=0x4FC1C154 /root/p4rom.elf 2>/dev/null | head -40
