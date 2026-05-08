# Phase 2.M — Bypass FreeRTOS scheduler, reach app_main + initArduino

**Estado**: ✅ done · commit `e555e8ccfd`

## Goal

Phase 2.L.next dejó vTaskStartScheduler corriendo end-to-end pero ningún task se dispatchaba (sin CLIC IRQ delivery, scheduler crea tasks pero nunca las ejecuta).

Approach: skipear el scheduler entero y llamar **main_task → app_main** directamente desde start_cpu0's contexto. Sí: rompe el modelo task-based de FreeRTOS, pero permite que el código de aplicación se ejecute linealmente.

## Patches (4 nuevos, 40 totales)

1. **start_cpu0 → main_task direct**: en `0x40009256`, replace `jal esp_startup_start_app` (`0xCE1FD06F`) con `jal main_task` (`0x05A1F0EF`, target = 0x400282B0). main_task corre en stack de start_cpu0 sincrónicamente.

2. **main_task: skip CPU1 wait**: en `0x400282D2`, NOP el `beqz a5, -4` (`0xDFF5` → `0x0001`). Sin HP_CPU1 emulado, `s_other_cpu_startup_done` nunca se setea.

3. **main_task: bypass TWDT err check**: en `0x40028306`, `c.beqz a0, +0x26` (`0xC11D`) → `c.j +38` (`0xA01D`). Si `esp_task_wdt_init` falla (probable sin scheduler), saltamos a `app_main` igual.

4. **app_main → setup() direct**: en `0x4000307C`, replace `j xTaskCreateUniversal` (`0xCE1FD06F`) con `j setup` (`0xFA4FC06F`, target = 0x40000020). Sin scheduler, loopTask nunca correría — saltamos directo a setup() del Arduino.

## Resultado

**174 unique IDF/Arduino runtime functions ejecutan** (vs 138 antes). Nuevos paths alcanzados:
- `main_task` ← objetivo de Phase 2.M
- `app_main` ← objetivo final esperado
- `initArduino` ← Arduino runtime init
- `__sinit`, `__retarget_lock_init_recursive`, `global_stdio_init`
- `esp_task_wdt_init`, `lock_init_generic`, `_lock_acquire`, `_lock_release`
- `spi_flash_mmap` ← stuck here
- `vprintf`, `_vfprintf_r`, `esp_log_cache_get_level`

## Próximo blocker

**`initArduino` → `spi_flash_mmap` stuck**. La función intenta mapear flash via cache MMU pero algo no responde. Phase 2.N investiga.

Si destrabamos eso, debería seguir:
- `setup()` → `Serial0.begin(115200)` → `pinMode(2, OUTPUT)` → **`Serial.println("...")` → UART output**.

## Estado consolidado del proyecto

| Métrica | Sesión inicio | Sesión actual |
|---|---|---|
| ROM panics | yes | ❌ no |
| FreeRTOS scheduler entered | ❌ | ✅ runs end-to-end |
| `main_task` reached | ❌ | ✅ |
| `app_main` reached | ❌ | ✅ |
| `initArduino` reached | ❌ | ✅ executing |
| First UART output | ❌ | ⏭️ a un blocker (Phase 2.N) |

**A una iteración del primer "Hello world!" del Arduino blink**.
