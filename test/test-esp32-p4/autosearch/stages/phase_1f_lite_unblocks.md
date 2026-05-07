# Phase 1.F-lite — RVA + RVF + CLIC MMIO + flash bypass + smart stubs

**Status:** ✅ done — commit `fe94ceaa04`

## Goal

Después de cargar la ROM oficial (Phase 1.E.bis) el runtime IDF se trababa en `bootloader_flash_execute_command_common`. Resolver los 5 bloqueantes secuenciales que aparecieron iterando.

## Acceptance criteria

CPU ejecuta past flash detection, FreeRTOS port init, atomics, llega a `system_early_init` que polea un byte esperando un interrupt.

## Los 5 unblocks

### 1. RVA + RVF enabled en CPU misa
- **Síntoma**: illegal_instruction `lr.w a5, (a0)` (RV32A atomic) en `cas` (FreeRTOS spinlock).
- **Fix**: `set_misa(env, MXL_RV32, RVI | RVM | RVA | RVF | RVC)`. ESP32-P4 HP cores son RV32IMAFC + Zb + Zc.

### 2. Custom CSRs extendidos a `0xBC0-0xBFF`
- **Síntoma**: illegal `csrrwi x0, 0xBC0, 0`.
- **Fix**: agregar segundo bloque scratch RW para 0xBC0-0xBFF junto al existente 0x7C0-0x7FF.

### 3. HP CPU CLIC MMIO stub @ `0x20800000`
- **Síntoma**: `lw a0, 8(a5)` con `a5 = 0x20800000` faulta porque la región no está mapeada.
- **Causa**: FreeRTOS port usa CLIC MMIO en `0x20800000` para set/clear-mask. No está en TRM §7.3.5 (es CPU-internal).
- **Fix**: `create_unimplemented_device("esp32p4.hp_clic_mmio", 0x20800000, 0x10000)` (64 KB).

### 4. Targeted flash-bypass patches
- **Síntoma**: `lbu a5, 25(a5)` con `a5 = 0` en `bootloader_flash_execute_command_common+0x10C` — `esp_flash_default_chip` (BSS @ `0x4FF149F4`) está NULL.
- **Causa**: ESP32-P4 NO tiene SPI flash controller separado (cache MMU drives flash via MSPI internally). Sin la cache MMU + MSPI emulada, el flash subsystem nunca se inicializa.
- **Fix temporal**: patchear las 3 funciones flash con `c.li a0,0; c.jr ra` (return ESP_OK):
  - `bootloader_flash_execute_command_common` @ `0x4FF00334`
  - `bootloader_flash_reset_chip` @ `0x4FF0059C`
  - `bootloader_flash_update_id` @ `0x4FF01E8E`
- **Crítico**: aplicar patches DESPUÉS del PF_X overlay (sino el overlay los pisa).

### 5. Smart sysreg/clock stubs
- **Síntoma**: `system_early_init` polea bit 8 de `0x500E60C0` esperando "PLL locked".
- **Causa**: nuestros catch-all stubs devolvían 0; el bit nunca se setaba.
- **Fix**: stub custom con scratch RW backing + tabla de overrides por offset:
  - `0x500E60C0 → 0x100` (bit 8 set, "PLL locked")
- Tabla extensible — agregar entradas cuando aparezcan nuevos polls.

## Archivos tocados

- `hw/riscv/esp32p4.c` (~+150 LOC): `Esp32P4SmartStub` struct + ops + install helper, CLIC MMIO stub, flash patches.
- `target/riscv/esp_cpu.c` (~+30 LOC): RVA+RVF, custom2 CSR range, install loop.
- `target/riscv/esp_cpu.h` (+6 LOC): `custom_csr[0x88]`.

## Notes

- "P4 no tiene SPI flash controller separado" es un descubrimiento clave. El plan original de Phase 1.F (clonar el C3) NO aplica al P4 — el flash se accede via cache MMU + MSPI internos. Phase 1.F propiamente dicho se redirige al smart stub + cache MMU emulada en Phase 1.G.
- El smart stub override table es el patrón que reemplaza la implementación "real" de muchos peripherals. Crece orgánicamente.
- El runtime está ahora en un poll que requiere interrupts → Phase 1.K es el próximo bloqueante REAL.
