# Phase 2.A.3 — Section-data pass + reset cause + GPIO strap → full ROM banner

**Estado**: ✅ done · commit `780ad0c50c` (fork) · `4b0fa2d` (Velxio docs)

## Goal

Pasar de "EGGGGGG..." (basura por que el ROM panicó instantáneamente) a:

```
ESP-ROM:esp32p4-20230811
Build:Aug 11 2023
rst:0x1 (POWERON),boot:0x8 (SPI_FAST_FLASH_BOOT)
```

Es decir: el banner real Espressif idéntico al que verías por UART en silicon.

## Discoveries (documentación de la investigación)

### Discovery 1 — `load_elf` se salta secciones de la ROM

La ROM ELF (`esp32p4_rev0_rom.elf`) tiene **dos clases de bytes inicializados**:

1. **PT_LOAD segments** — los carga `load_elf()` de QEMU.
2. **Section header table sections** que NO están dentro de ningún PT_LOAD segment.

¿Cómo es posible? El ELF de la ROM Espressif fue construido con un linker script donde algunos `.data.*` y `.rodata.*` aparecen sólo en el SHT, fuera del `phdr` table. En silicon real, la fab grava el contenido literal en el ROM físico, así que el SHT es la fuente autoritativa, no los segments.

**Cómo lo descubrí**:
```bash
$ riscv64-unknown-elf-readelf -l /root/p4rom.elf | grep LOAD
LOAD 0x000020 0x4FC00000 0x4FC00000 0x40000 0x40000 R E
LOAD 0x040020 0x4FC1A000 0x4FC1A000 0x05dcc 0x05dcc RW

$ riscv64-unknown-elf-readelf -S /root/p4rom.elf | head -30
[ 8] .data.rom_cache_internal_table_ptr   PROGBITS 4ff3ffd8 029c18 000004 00 WA
[10] .data.cache_lock                     PROGBITS 4ff3ffe8 029c1c 000008 00 WA
[11] .data.ets_ops_table_ptr              PROGBITS 4ff3fff4 029c24 000004 00 WA
```

`0x4FF3FFxx` no cae dentro de ninguno de los dos LOAD segments. **15 secciones quedaron sin cargar**.

`load_elf()` de QEMU sólo procesa PT_LOAD, así que esas secciones quedaron a 0 en L2MEM. La ROM al runtime hacía `lw a5, ets_ops_table_ptr` y obtenía 0 (o cualquier valor que llegara después por el reset RAM clear), terminando en panic al hacer `jalr a5`.

### Fix 1 — Section-data pass post-load_elf

En `esp32p4.c::esp32p4_load_bios_elf()` añadí un walker que después de `load_elf()` parsea la SHT manualmente y escribe las secciones PROGBITS+WRITE no cubiertas:

```c
for (int si = 0; si < beh.e_shnum; si++) {
    Elf32_Shdr sh;
    fseek(bf, beh.e_shoff + si * beh.e_shentsize, SEEK_SET);
    if (fread(&sh, 1, sizeof(sh), bf) != sizeof(sh)) break;
    if (sh.sh_type != SHT_PROGBITS) continue;
    if (sh.sh_size == 0) continue;
    if (!(sh.sh_flags & SHF_WRITE)) continue;       /* solo .data, no .rodata */
    if (sh.sh_addr >= 0x4FC00000 && sh.sh_addr < 0x4FC20000) continue;  /* skip ROM, ya cargado */
    if (sh.sh_addr >= 0x40000000 && sh.sh_addr < 0x40010000) continue;  /* skip cache window */

    /* read y write */
    uint8_t *buf = g_malloc(sh.sh_size);
    fseek(bf, sh.sh_offset, SEEK_SET);
    fread(buf, 1, sh.sh_size, bf);
    address_space_write(&address_space_memory, sh.sh_addr,
                        MEMTXATTRS_UNSPECIFIED, buf, sh.sh_size);
    g_free(buf);
}
```

**15 secciones cargadas** verificable con un dump:
- `0x4FF3FFD8` (rom_cache_internal_table_ptr) = `0x4FC1F984` ✓
- `0x4FF3FFF4` (ets_ops_table_ptr) = `0x4FC1D0F0` ✓
- 13 más (locks, internal pointers, etc.)

### Discovery 2 — `LP_CLKRST_RESET_CAUSE_REG` (0x50111010)

La ROM tiene una rutina temprana que lee este registro para imprimir `rst:0xN (NOMBRE)`. El bit-layout (per `lp_clkrst_reg.h` de IDF):

- **Bits [12:7]**: `HPCORE0_RESET_CAUSE` — **0x01 = POWERON_RESET**.

Si el campo está a 0 → `(N/A)` y un poco después una rutina de validación dispara un panic con mensaje "invalid reset cause" porque esperaba un valor non-zero.

### Fix 2 — Smart stub override

En `lp_clkrst` smart stub:
```c
{ 0x50111000, 0x010, 0x80,  "LP_CLKRST: HPCORE0 reset cause = POWERON" },
```
(0x80 = 0b10000000 = bits[12:7]=0x01 cuando el offset relevante es +7)

### Discovery 3 — `GPIO_STRAP_REG` (offset 0x38 dentro de GPIO base)

La ROM hace `LD GPIO_STRAP_REG`, decodifica los bits, e imprime `boot:0xN (NOMBRE)`. Con valor 0 imprime `boot:0x0 (USB_BOOT)` y intenta arrancar de USB Serial/JTAG (que NO modelamos).

Per `soc/boot_mode.h` de IDF, el patrón `1XXX` (bit 3 set) significa `ETS_IS_FAST_FLASH_BOOT`.

### Fix 3 — GPIO read handler returns 0x08

En `esp32p4_gpio.c`:
```c
case 0x38:
    return 0x08;  /* 1XXX = ETS_IS_FAST_FLASH_BOOT */
```

### Discovery 4 — USB Serial/JTAG panic recursivo

La ROM tiene un panic handler que a falta de UART config (que sí tiene), también intenta enviar al USB Serial/JTAG controller. La función ROM `usb_serial_device_tx_one_char @ 0x4FC09554` deref-NULL el descriptor de USB.

### Fix 4 — ROM patch ret 0

```c
{ "ROM usb_serial_device_tx_one_char: ret 0", 0x4FC09554, 0x80824501u, 4 },
```
(`0x80824501` = `addi a0,zero,0; ret` empaquetado little-endian)

## Acceptance criteria — pasaron

- [x] Banner imprime las 3 líneas completas y limpias.
- [x] `rst:0x1 (POWERON)` correcto.
- [x] `boot:0x8 (SPI_FAST_FLASH_BOOT)` correcto.
- [x] No hay output garbled antes ni durante el banner.
- [x] No hay aborts QEMU ni "invalid reset" panics.

## Archivos tocados

- `hw/riscv/esp32p4.c` — section-data pass; lp_clkrst smart stub override; usb_serial ROM patch
- `hw/gpio/esp32p4_gpio.c` — GPIO_STRAP_REG returns 0x08

## Notas

- El section-data pass es la "fix correcta" para load_elf no bouquering todo el ELF de un ROM real fab. Esto va a quedar también para futuros chips Espressif.
- La ROM patch de `usb_serial_device_tx_one_char` se podrá quitar cuando Phase 2.I (USB Serial/JTAG) modele el peripheral en serio. Es safety net.
- La GPIO strap value debería venir de `-strap` cmdline en el futuro (para emular UART download mode, etc.). Hardcodeo 0x08 por ahora.
- Cache_Invalidate_All ROM patch heredado de 2.A.2 sigue vigente. Phase 2.A.4 podría hacerlo innecesario.

## Bloqueante post-2.A.3 → siguiente fase (2.A.4)

ROM aún panica en PC `0x4FC02954` (Load access fault) con A5=`0x8067`. La verificación post-`machine_init` confirma que `0x4FF3FFF4` tiene `0x4FC1D0F0` correcto. Algo entre el reset y `main+0x23E` overwrites esos bytes. Ver `phase_2a4_runtime_overwrite.md`.
