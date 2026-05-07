# Phase 2.B.boot_comm — Bootloader chip ID verify

**Estado**: ⏭️ next

## Goal

Bootloader Espressif corre 6.4 segundos de inicialización (regi2c writes) y luego falla:

```
E (6414) boot_comm: mismatch chip ID, expected 18, found 0
```

`expected 18` = `CONFIG_IDF_FIRMWARE_CHIP_ID` para ESP32-P4 (compile-time).
`found 0` = `image_header->chip_id` del image que estaba leyendo.

## Análisis

El flash blob TIENE chip_id correcto en sus headers:
- `flash[0x2000+12]` = `0x12 0x00` (= 18 LE) — bootloader image header
- `flash[0x10000+12]` = `0x12 0x00` (= 18 LE) — app image header
- `flash[0x8000]` = partition table (magic 0xAA50)

Pero el bootloader reporta `found 0`. Posibles causas:

### H1 — Bootloader lee desde un offset mal calculado

Si el bootloader busca un image header en flash[0] (que está erased = 0xFF), `chip_id` (16-bit) leería como 0xFFFF = 65535, no 0. No coincide con "found 0".

Si el bootloader busca en flash[X] donde X tiene un image-like sequence de 0xE9 0x?? 0x?? 0x?? entonces... pero el `0xE9 magic` solo está en 0x2000 y 0x10000.

Si lee de `0x40000000` (cache window virtual) sin que el MMU traduzca, podría leer cero (RAM uninitialized despues del flash blob copy).

### H2 — App image pre-OTA load fallback

ESP-IDF bootloader, después de cargar a sí mismo, busca la app image. Lee partition table → encuentra app partition → lee app image header. Si el bootloader interpreta mal la partition table o lee desde el offset incorrecto, puede leer chip_id=0.

### H3 — Cache MMU re-mapping after bootloader load

El bootloader puede haber re-programado el cache MMU para mapear flash de manera distinta a la lineal. Si re-mapeo el cache, la lectura desde virtual address X devuelve flash[Y] con Y != X. Podría caer en una región que tiene 0s.

## Plan

1. Trace el flujo del bootloader desde `entry 0x4ff29ed0` hasta el punto donde se imprime el error. Identificar la función `bootloader_common_check_chip_id_in_image_header` (per IDF source).
2. Ver de qué dirección está leyendo (qué virtual address arg pasa a memcpy).
3. Determinar si es un offset incorrecto (fix: arreglar partition lookup) o un cache MMU mal mapeado (fix: implementar MMU real).

## Acceptance criteria

- [ ] Bootloader ya no imprime `mismatch chip ID`.
- [ ] Bootloader continúa con load de app segments y eventualmente saltea al app entry.

## Notas

- Si la causa es H3, esto se entrelaza con Phase 2.A.6 (real cache MMU). Implementar el MMU resolverá ambas.
- Si es H1/H2, fix más quirúrgico: parchear bootloader code o ajustar partition lookup.
