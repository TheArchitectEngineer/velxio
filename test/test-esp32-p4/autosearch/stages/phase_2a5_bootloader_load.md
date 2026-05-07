# Phase 2.A.5 — Flash bootloader load

**Estado**: ✅ done · commit pendiente

## Resolución (resumen ejecutivo)

**Causa raíz dual**:
1. El ROM ELF tiene un PT_LOAD a virtual `0x40000000` (~35 KB de constantes ROM) que **sobrescribe el flash blob** previamente cargado en el cache window. Resultado: ROM lee bytes de constantes ROM (`0xC1 0x0E 0x00 0x0B`) en vez del bootloader magic (`0xE9`).
2. `ets_loader_map_range` en el ROM espera que el cache MMU esté programado. Sin un MMU real, devuelve garbage. Aunque arregláramos #1, el ROM seguiría leyendo de un VA equivocado.

**Fixes aplicados**:

### Fix 1 — Flash blob reload over cache window

Después de `load_elf_ram_sym` del BIOS ELF y la section-data pass, el flash blob se **reescribe** sobre el cache window via `blk_pread`. El orden ahora es:
1. extflash region creada.
2. Flash blob load inicial (línea ~582).
3. BIOS ELF load (overwrites cache window con ROM constants).
4. Section-data pass (escribe `.data.interface.*` en `0x4FF3FFxx`).
5. ROM patches.
6. **Flash blob reload** (recover cache window con flash content).

```c
DriveInfo *reload_dinfo = drive_get(IF_MTD, 0, 0);
if (reload_dinfo) {
    BlockBackend *reload_blk = blk_by_legacy_dinfo(reload_dinfo);
    /* ... look up flash MR by base address ... */
    blk_pread(reload_blk, 0, copy_size, host_ptr, 0);
}
```

### Fix 2 — `ets_loader_map_range` linear identity patch

ROM patch (3 entries, 12 bytes total) en `0x4FC044CC`:
```asm
lui  a0, 0x40000   ; 0x40000537
add  a0, a0, a1    ; 0x00B50533
ret                ; 0x00008067
```

Bypassea param validation + MMU programming. Devuelve `0x40000000 + flash_offset` directly. Funciona para todos los call sites en `ets_run_flash_bootloader` (offsets 0x2000, 0x10000, etc.).

## Resultado

```
ESP-ROM:esp32p4-20230811
Build:Aug 11 2023
rst:0x1 (POWERON),boot:0x8 (SPI_FAST_FLASH_BOOT)
SPI mode:DIO, clock div:1
load:0x4ff33ce0,len:0x1174
load:0x4ff29ed0,len:0xccc
load:0x4ff2cbd0,len:0x34fc
SHA-256 comparison failed:
Calculated: 0000000000000000000000000000000000000000000000000000000000000000
Expected: 55df7066fffde52c0ac426d1ca50a882ae5cd6f1cf2cb5d6dfccb1bf40ad58be
Attempting to boot anyway...
entry 0x4ff29ed0
Assert failed in regi2c_enable_block, esp_rom_regi2c_esp32p4.c:90
```

ROM imprimió todo el flujo de boot:
- ✓ Boot banner
- ✓ SPI mode/clock info
- ✓ 3 bootloader segments cargados a L2MEM
- ✓ SHA-256 hash check (falló pero ROM continuó porque no hay secure boot)
- ✓ Jump al bootloader entry point (`0x4ff29ed0`)
- ✓ **Bootloader Espressif comenzó a ejecutarse**
- ✗ Bootloader assert en `regi2c_enable_block` → Phase 2.B.regi2c

## Acceptance criteria — pasaron

- [x] `invalid header` ya no aparece.
- [x] ROM carga los 3 segments del bootloader.
- [x] ROM jumpea al bootloader entry.
- [x] Bootloader code (en L2MEM `0x4FF29ED0`) ejecuta y llama ets_printf via ROM trampolines.

## Notas

- La fix #1 (flash blob reload) puede simplificarse cuando Phase 2.A.6 (real cache MMU) lande — el cache window será MMIO, no RAM, así el BIOS ELF no podrá sobrescribir flash.
- La fix #2 (`ets_loader_map_range` patch) también desaparecerá con Phase 2.A.6 — el MMU real hará la translación que la función espera.
- Por ahora ambas son safety nets que mantienen el bootloader avanzando.

## Archivos tocados

- `hw/riscv/esp32p4.c` — añade flash reload pass (~30 LOC) + 3 ROM patches.
