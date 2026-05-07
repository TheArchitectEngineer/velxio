# Phase 2.A.4 — `ets_ops_table_ptr` runtime overwrite

**Estado**: ✅ done · commit pendiente

## Resolución (resumen ejecutivo)

**Causa raíz**: la ROM ELF (`esp32p4_rev0_rom.elf` de Espressif) tiene una estructura de inicialización inusual:
- Las secciones `.data.interface.*` (en `0x4FF3FFxx`) tienen contenido en el SHT pero NO en ningún PT_LOAD.
- El `_init` del ROM tiene un `unpackloop` que copia desde `0x4FC1Cxxx` (en un "agujero" entre PT_LOADs, también ausente del ELF) a `0x4FF3FFxx`.
- Y un `clearloop` que zerea esas mismas direcciones inmediatamente después.
- En silicon real, la mask layer pre-graba los bytes a `0x4FC1Cxxx` antes del cold-reset, así el unpack copia los pointers válidos.
- En QEMU, esos bytes son 0, entonces el unpack copia 0s y el clearloop confirma 0s — borrando lo que pre-escribió nuestro section-data pass.

**Fix**: ROM patch en `0x4FC00BE0` que reemplaza el `bne a0, t0, .data_bss_ok` (4 bytes `06551063`) con `j .data_bss_ok` (4 bytes `0600006F`). Esto **bypasea unpack+clear para todos los harts**. Las secciones que escribió el section-data pass quedan intactas.

**Resultado**: ROM avanza más allá del banner sin panic. Próximo blocker: CLIC interrupt controller (Phase 2.D).


## Goal

Eliminar el panic en `PC 0x4FC02954` que sigue después de Phase 2.A.3. Causa: el ROM hace `lw a5, 0(0x4FF3FFF4)` y obtiene `0x8067` cuando debería obtener `0x4FC1D0F0`. Pero el dump post-machine_init confirma que la dirección tiene el valor correcto. **Algo en el ROM startup overwrites esos bytes entre `reset` y `main+0x23E`**.

## Hipótesis (en orden de probabilidad)

### H1 — RAM clear loop del ROM startup

Real silicon hace BSS-zeroing en `_start` (parte del crt0). El ROM ELF probablemente trae un loop:
```asm
la a0, _bss_start
la a1, _bss_end
:loop  beq a0,a1,done
       sw zero,0(a0)
       addi a0,a0,4
       j loop
```

Si `_bss_start..._bss_end` cubre `0x4FF3FFD8..0x4FF3FFF8`, **machine_init pone los valores y luego el ROM los borra**. La fix sería:

- **Opción A**: que el section-data pass corra DESPUÉS del BSS clear. Pero el BSS clear corre dentro del ROM, no podemos hookear al final.
- **Opción B**: registrar las direcciones como NO-BSS. Imposible — están dentro del rango que el ROM considera BSS.
- **Opción C**: usar QEMU watchpoints para detectar quién escribe esos bytes. Y patchear el writer.
- **Opción D**: comprender que esas secciones SON `.bss.*` semánticamente (initial-data + clear + re-init runtime via constructor) y NO necesitan estar inicializadas. El panic tiene otra causa.

### H2 — El ELF symbol no es `0x4FC1D0F0` sino otro valor

El section dump del file offset 0x29c24 podría haber sido leído mal. Validar con `xxd -s 0x29c24 -l 4 /root/p4rom.elf`.

### H3 — El ROM espera que el caller pase la table en otro registro

Posible que `0x4FC02954` esté en un path donde A5 ya viene precargada del caller, NO de la table at `0x4FF3FFF4`. La table sólo se usa para constructor init, no en runtime.

### H4 — Cache aliasing

El ROM podría operar en modo no-cached y la dirección `0x4FF3FFF4` resuelve a otra zona física. Improbable porque el banner imprime correctamente, pero vale verificar.

## Acceptance criteria

- [ ] El ROM atraviesa el panic en `0x4FC02954` sin Load access fault.
- [ ] Diagnóstico documentado: hipótesis H1-H4, cuál fue.
- [ ] Si fue H1 (BSS clear): fix elegido (C o D).
- [ ] Cache_Invalidate_All ROM patch puede que quede o se elimine, depende.

## Pasos

1. **Validar Section data en file**:
   ```bash
   xxd -s 0x29c18 -l 32 /root/p4rom.elf
   ```
   Confirmar que `0x4FF3FFF4` debería ser `0xF0 0xD0 0xC1 0x4F` (LE = 0x4FC1D0F0).

2. **Walk ROM disassembly** desde el reset vector hasta `main+0x23E` buscando un BSS-clear loop:
   ```bash
   riscv64-unknown-elf-objdump -d /root/p4rom.elf | sed -n '/<reset_vector>/,/<main>/p'
   ```

3. **Watchpoint via QEMU monitor**:
   ```
   qemu-system-riscv32 -M esp32p4 ... -monitor stdio -S
   (qemu) watch 0x4FF3FFF4 4 access
   (qemu) c
   ```
   Ver qué PC dispara el watchpoint.

4. **Si confirma BSS-clear**:
   - Imprimir el rango `_bss_start..._bss_end` desde la ELF (símbolos del crt0).
   - Decidir: H1.opción D (probable: deferir section-data pass para que corra DESPUÉS del clear).

## Archivos a tocar

- `hw/riscv/esp32p4.c` — agregar logging temporal en machine_init para snapshot post-BSS-clear; o usar QEMU memory hooks.

## Notas

- La table `ets_ops_table_ptr @ 0x4FC1D0F0` apunta a una table de funciones ROM. Si A5 = 0x8067, entonces el ROM tomó un valor random tras el clear. Eso confirma fuertemente H1.
- El loop BSS-clear puede vivir en la **PT_LOAD del ROM CODE @ 0x4FC00000** y correr automáticamente durante `_start`. Es decir, NO podemos saltarlo sin patchear el ROM. La fix es hacer que el section-data pass se haga **post-BSS-clear**.
- Truco posible: agregar un breakpoint en `main` (o un hook RISC-V), y al disparar reescribir las secciones. QEMU permite esto con un GDB stub o con un memory hook custom.
- Solución elegante: implementar un "lazy section loader" que escriba esas secciones cuando la primera lectura ocurre.
