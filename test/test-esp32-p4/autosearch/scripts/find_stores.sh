#!/usr/bin/env bash
# Find stores to 0x4FF3FFF4 (ets_ops_table_ptr)
echo "=== Stores (sw/sb/sh) targeting 0x4ff3fff4 ==="
riscv64-unknown-elf-objdump -d /root/p4rom.elf 2>/dev/null | \
  grep -B2 "ets_ops_table_ptr" | \
  grep -E "(sw|sh|sb)" | head -20

echo
echo "=== Check what 0x500E0038 STRAP read returns - which path do we want? ==="
echo "main+0x70 (0x4fc02786): if STRAP & 0x8 → goto +0x120 (0x4fc02836)"
echo "main+0x86 (0x4fc02942): if STRAP & 0x8 → load ets_ops_table_ptr → call"
echo
echo "=== Disasm 0x4FC02836 (FAST_FLASH_BOOT branch) ==="
riscv64-unknown-elf-objdump -d --start-address=0x4FC02836 --stop-address=0x4FC02950 /root/p4rom.elf 2>/dev/null
