#!/usr/bin/env bash
# Dump all PROGBITS sections in 0x4FC1C154..0x4FC1FDCC (region after first ROM LOAD)
echo "=== PROGBITS sections in 0x4FC1Cxxx region ==="
riscv64-unknown-elf-readelf -W -S /root/p4rom.elf 2>/dev/null | \
  awk '$3=="PROGBITS" { addr=strtonum("0x"$5); if (addr >= 0x4FC1C154 && addr < 0x4FC20000) print }'

echo
echo "=== Full memory map of L2MEM-area sections ==="
riscv64-unknown-elf-readelf -W -S /root/p4rom.elf 2>/dev/null | \
  awk '$3=="PROGBITS" { addr=strtonum("0x"$5); if (addr >= 0x4FF20000 && addr < 0x50000000) print }'

echo
echo "=== Verify byte at file offset 0x42184 ==="
xxd -s 0x42184 -l 16 /root/p4rom.elf 2>/dev/null

echo
echo "=== Disasm at 0x4FC02954 (the panic site) ==="
riscv64-unknown-elf-objdump -d --start-address=0x4FC02940 --stop-address=0x4FC02970 /root/p4rom.elf 2>/dev/null
