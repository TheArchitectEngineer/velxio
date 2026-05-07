#!/usr/bin/env bash
# Look for sections in 0x4FC1C154..0x4FC1CA80 (data unpack source range)
echo "=== PROGBITS sections in 0x4FC1C154..0x4FC1CA80 ==="
riscv64-unknown-elf-readelf -W -S /root/p4rom.elf 2>/dev/null | \
  awk '$3=="PROGBITS" { addr=strtonum("0x"$5); if (addr >= 0x4FC1C154 && addr < 0x4FC1CA80) print }'

echo
echo "=== ALL section names+addrs in 0x4FF3FFC0..0x4FF40000 (dests) ==="
riscv64-unknown-elf-readelf -W -S /root/p4rom.elf 2>/dev/null | \
  awk '/PROGBITS|NOBITS/ { addr=strtonum("0x"$5); if (addr >= 0x4FF3FFC0 && addr < 0x4FF40000) print }'

echo
echo "=== Find ets_ops_default_table symbol ==="
nm /root/p4rom.elf 2>/dev/null | grep -i "ets_ops_default\|ets_ops_table"

echo
echo "=== Dump bytes at 0x4FC1D0F0 (ets_ops_default_table) ==="
xxd -s 0x270F0 -l 64 /root/p4rom.elf 2>/dev/null  # 0xa000 + (0x4FC1D0F0 - 0x4FC00000) = 0x270F0
