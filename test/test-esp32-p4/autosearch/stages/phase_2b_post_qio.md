# Phase 2.B.post_qio — Performance: MMU eager-copy refactor

**Estado**: ✅ done · commit `947fba8b80`

## Goal

Después de Phase 2.B.boot_comm el bootloader pasaba el chip ID check pero "stalleaba" después del qio_mode warning. El profiling mostró que el bootloader **no estaba en un polling loop muerto** — estaba ejecutando código real (SHA256 software, XOR loops, function call overhead). El problema era **rendimiento**: cada lectura del cache window iba via MMIO interpreter (~100x slower que RAM).

## Análisis

Tracing de hot PCs después de qio_mode:
- `0x4ff2de64-0x4ff2de6e`: XOR loop — software SHA256 round.
- `0x4fc1880c, 0x4fc187e8`: __riscv_save/restore — function prologue/epilogue.
- `0x4ff2d51c, 0x4ff2e1a2`: bootloader code en L2MEM.

El bootloader está ejecutando `bootloader_load_image` que lee TODOS los segments del app image desde flash y computa SHA256 sobre ellos. Cada byte leído del cache window pasa por el MMU.

Con el MMIO overlay anterior:
- Cada read MMIO = call al handler → translate → memcpy 1 byte.
- Sin TCG JIT (TCG no puede cachear MMIO ops).
- ~100x slower que RAM access.

## Fix — Eager-copy translation

En vez de overlay MMIO al read time, **eager copy al write time**:

```c
// On every MSPI MMU write (entries[idx] = value with VALID set):
memcpy(extflash_RAM + (idx << 16), flash_blob + (phys_page << 16), 64KB);
```

Después de la copia, el cache window region tiene el contenido correcto del flash. Reads subsiguientes van por RAM directo. TCG cachea el código que lee, runs at full speed.

**Generalización**: el original era específico para block 63. Ahora cualquier entry (0..1023) funciona, así app code que XIPea desde múltiples cache pages también funciona.

## Resultado

- Antes (MMIO overlay): ~10 sec fake time / 60 sec wall = **6x slowdown**.
- Después (eager copy): ~47 sec fake time / 60 sec wall = **1.3x slowdown**.
- **~5x improvement**. Bootloader avanza dramatically más por wall-second.

## Próximo blocker

Aún hay slowdown porque la **SHA256 software** del bootloader es CPU-intensive (cycle-bound). Para terminar el flow de boot completo:

**Phase 2.I.sha** — implementar el SHA hardware accelerator del ESP32-P4. Per TRM, vive en HP_PERIPH alrededor de `0x500D6000`. El bootloader usaría HW SHA (mucho más rápido que SW), salteando el bottleneck.

O alternativamente: **paciencia** + correr 5-10 minutos wall time hasta que el bootloader termine SHA y print más mensajes.

## Archivos tocados

- `hw/riscv/esp32p4.c`: refactor mayor del MMU emulator (~73 LOC modificados, ~63 LOC eliminados).

## Notas

- La fix es un trade-off: eager-copy gasta tiempo en el write (memcpy 64 KB), pero recupera cien veces eso en los reads subsiguientes.
- El código JIT TCG no puede cachear MMIO callbacks. Convertir a RAM hace que ese 64 KB region sea JIT-eligible.
- Esta arquitectura es válida también para el app XIP code path en el futuro.
