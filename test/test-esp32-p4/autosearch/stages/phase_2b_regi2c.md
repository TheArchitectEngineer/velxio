# Phase 2.B.regi2c — Master clock enable check

**Estado**: ✅ done · commit pendiente

## Goal

ROM cargó el bootloader Espressif y le transfirió el control. El bootloader llama `regi2c_enable_block` (de `esp_rom_regi2c_esp32p4.c`), que primero llama `regi2c_ctrl_ll_master_is_clock_enabled()`. Esa función verifica un bit en algún registro de clock control. Como no lo modelamos, devuelve 0 → el assert falla.

```
Assert failed in regi2c_enable_block, esp_rom_regi2c_esp32p4.c:90
(regi2c_ctrl_ll_master_is_clock_enabled())
```

## Análisis

`regi2c` es el **internal-register I2C bus** que ESP32-P4 usa para hablar con bloques análogos (PLL, BBPLL, RTC, ADC). El clock para este bus se enabled vía un bit en `LP_CLKRST` o `HP_SYSCLKRST` (clock gate enable).

Por la naming (`regi2c_ctrl_ll_master_is_clock_enabled`), el master es el clock-gate del módulo regi2c. Per IDF source code (esp32p4 hal):
- `regi2c_ctrl.h` o `regi2c_ctrl_ll.h` define la function.
- Probablemente es un bit en `LPPERI_CLK_EN_REG` (LP) o similar HP register.

## Plan

1. Buscar en IDF source el código de `regi2c_ctrl_ll_master_is_clock_enabled` para ESP32-P4.
2. Identificar el registro y bit.
3. Agregar `SMART_OR_MASK` override que set ese bit always.

## Acceptance criteria

- [ ] Bootloader pasa `regi2c_enable_block` sin assert.
- [ ] Bootloader continúa ejecutando (probablemente toca más perifericos — ADC, BBPLL, etc).

## Pasos

1. Clone IDF y buscar:
   ```bash
   grep -rn "regi2c_ctrl_ll_master_is_clock_enabled" \
     /mnt/c/Desarrollo/velxio/third-party/esp-idf/components/hal/
   ```
2. Identificar register/bit.
3. Agregar override.
4. Run + check next blocker.

## Resolución

### Fix 1 — LPPERI smart stub at 0x50120000

Agregué `esp32p4_install_smart_stub` para `0x50120000` (LPPERI) tamaño `0x1000`. Esta es una nueva región que antes no estaba mapeada.

### Fix 2 — LPPERI_CLK_EN_REG offset 0 override

```c
{ 0x50120000, 0x000, 0x7FFF0000, SMART_OR_MASK,
  "LPPERI: LP peri clock-enables (bits 16-30 = 1)" },
```

Los bits 16-30 (todas las clock-enables LP excepto LP_CORE) defaultean a 1 en silicon real per `esp_efuse_table.csv`/IDF source. OR_MASK preserva escrituras del ROM y siempre setea esos 15 bits. Bit 27 = LP_I2CMST (regi2c master clock).

### Fix 3 — 0x500E60BC regi2c done bit

Después del fix 1+2, el bootloader avanzó y se atascó en `lw 0x500E60BC; andi 4; beqz retry`. Patrón clásico write-then-poll-done. Override OR_MASK con bit 2 set:

```c
{ 0x500E6000, 0x0BC, 0x4, SMART_OR_MASK, "Reset/Clock: regi2c done (bit 2)" },
```

## Resultado

Bootloader corre **6.4 segundos** de inicialización (regi2c writes a PMU/PLL/RTC), y termina con:

```
E (6414) boot_comm: mismatch chip ID, expected 18, found 0
```

Es un assert del **bootloader Espressif** que verifica el chip_id del image header (offset 12 del image) contra `CONFIG_IDF_FIRMWARE_CHIP_ID = 18` (compile-time const para ESP32-P4). El bootloader está leyendo de algún offset y obteniendo `chip_id = 0`.

Próximo blocker: **Phase 2.B.boot_comm** — investigar de qué offset lee el bootloader para tener `chip_id = 0` (probablemente lee desde flash erased = 0xFFFF, o desde cache window mal mapeado).

## Notas

- Este es uno de muchos asserts que el bootloader y luego el app pueden disparar.
- Los blockers van a ser, en orden esperado, periféricos analógicos (regi2c ✓), boot_comm chip ID, partition table read, app load, multi-core, y eventualmente el app code (Arduino blink).
- Bug bounty: cada assert te dice exactamente qué función falló y dónde. Mucho más fácil que Phase 1 donde había que disasm everything.
