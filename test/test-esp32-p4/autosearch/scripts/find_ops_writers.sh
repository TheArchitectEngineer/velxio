#!/usr/bin/env bash
# Find who writes to 0x4FF3FFF4 (ets_ops_table_ptr) in the ROM
echo "=== Symbol at 0x4FF3FFF4 ==="
nm /root/p4rom.elf 2>/dev/null | grep -i ets_ops_table_ptr

echo
echo "=== References to 0x4ff3fff4 in disassembly (any ld/sw) ==="
riscv64-unknown-elf-objdump -d /root/p4rom.elf 2>/dev/null | grep -B1 "4ff3fff4\|ets_ops_table_ptr" | head -30

echo
echo "=== Disasm of main from 0x4FC02716 ==="
riscv64-unknown-elf-objdump -d --start-address=0x4FC02716 --stop-address=0x4FC02960 /root/p4rom.elf 2>/dev/null | head -100

echo
echo "=== What is at 0x500E0038? (STRAP register) ==="
echo "Already known: GPIO_STRAP_REG"

echo
echo "=== Dump 0x4FC1D0F0 area (what ets_ops_table[0] should be) ==="
xxd -s 0x2A0F0 -l 32 /root/p4rom.elf 2>/dev/null  # file offset = 0xa000 + 0x1d0f0 = 0x2710...
echo "Trying different file offsets:"
xxd -s 0x270F0 -l 32 /root/p4rom.elf 2>/dev/null  # 0xa000 + 0x1d0f0 = 0x270F0
