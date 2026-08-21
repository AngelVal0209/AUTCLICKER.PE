# AutoClicker

Autoclicker nativo para Windows que pulsa los botones izquierdo, derecho y central del ratón a intervalos configurables, con hotkeys globales, aleatoriedad anti-detección y grabadora de macros. Construido en Free Pascal con LCL (Lazarus), sin dependencias externas: un solo `.exe` portátil.

![Lenguaje](https://img.shields.io/badge/lenguaje-Free_Pascal_(ObjFPC)-2E7D32)
![IDE](https://img.shields.io/badge/framework-LCL_|_Lazarus-0F62A0)
![Plataforma](https://img.shields.io/badge/plataforma-Windows_7+-0078D6)
![API](https://img.shields.io/badge/api-Win32_|_MMSystem-5C2D91)
![Config](https://img.shields.io/badge/config-INI_portable-E6A700)

---

## Características

### Motor de clics (`TClicThread`)
- Hilo worker independiente de la UI: la ventana nunca se congela mientras hace clic.
- Programación por canal con `GetTickCount64`: cada botón mantiene su propia fecha límite `next[i]`, así tres botones activos clican cada uno a su ritmo dentro del mismo hilo.
- Bucle de sondeo con `Sleep(1)` combinado con `timeBeginPeriod(1)` (MMSystem) para resolución real de 1 ms, no los ~15 ms por defecto de Windows.
- Inyección de clics vía `Mouse_Event` con pares down/up exactos: izquierdo `$02/$04`, derecho `$08/$10`, central `$20/$40`.
- Contador global `FCount: Int64` compartido por los tres canales; al alcanzar el límite configurado el hilo termina solo.

### Intervalo con aleatoriedad
- Intervalo configurable en horas, minutos, segundos y milisegundos (`sedH/sedMin/sedS/sedMs`), calculado como `h*3600000 + m*60000 + s*1000 + ms`; mínimo admitido: 1 ms.
- Modo aleatorio opcional: desvío uniforme de `±RandMs` sobre el intervalo base (`iv + Random(2*rms+1) - rms`), acotado a mínimo 1 ms, para romper patrones mecánicos de clic.
- La configuración se captura en un snapshot (`Snapshot`) al arrancar: cambiar valores con el clicador activo no altera la sesión en curso.

### Modos de repetición
- **N veces**: repite hasta el número exacto de clics definido en `sedVeces`.
- **Hasta parar**: modo infinito (`limite = -1`) hasta pulsar Stop o la hotkey correspondiente.
- El botón **Iniciar** arranca siempre con el canal izquierdo activo; **Detener** apaga los tres canales de golpe (`SetAll(False)`).

### Posición del cursor
- **Cursor actual**: clica donde esté el puntero en cada momento.
- **Coordenadas fijas**: mueve el puntero con `SetCursorPos(x, y)` antes de cada clic a las coordenadas `sedX/sedY`.
- Validación al iniciar: rechaza coordenadas negativas o fuera de pantalla comparando contra `GetSystemMetrics(SM_CXSCREEN/SM_CYSCREEN)`.

### Hotkeys globales
- Tres hotkeys registradas a nivel de sistema con `RegisterHotKey` + `MOD_NOREPEAT` (no se auto-repiten al mantener pulsada), funcionan aunque la app esté minimizada o en segundo plano.
- Por defecto: **F6** alterna clic izquierdo, **F7** el derecho, **F8** el central; cada canal se enciende y apaga de forma independiente.
- Recepción por mensaje `WM_HOTKEY` (`$0312`) interceptado en `WndProc`, con ids internos 1–3 (`HOTID_L/HOTID_R/HOTID_W`).
- Si otra aplicación ya usa la tecla, avisa al arrancar y permite reasignarla sin cerrar el programa.
- Las etiquetas de la UI muestran el estado en vivo: `Left: F6 (activo)` cuando ese canal está disparando.

### Diálogo de reasignación de hotkeys (`THotDlg`)
- Pulsa el botón del canal (Left/Right/Middle) y luego cualquier tecla para capturarla vía `OnKeyDown`.
- `Esc` cancela la captura sin cambios.
- Reasignación atómica: desregistra la tecla vieja, intenta registrar la nueva y, si falla (tecla ocupada), restaura la anterior y muestra el aviso *"Esa tecla ya está asignada o no está disponible"*.
- Traducción legible de códigos virtuales con `KeyName`: `Esc`, `Espacio`, `Enter`, `Tab`, `F1`–`F12`, letras `A`–`Z`, dígitos `0`–`9` y hexadecimal para el resto.

### Grabadora y reproductor de macros (`TRecDlg`)
- **Grabar** lanza `TRecThread`, que sondea cada 5 ms y registra dos tipos de eventos: movimientos (solo cuando cambian las coordenadas) y transiciones down/up de los tres botones leídas con `GetAsyncKeyState`.
- Ignora los clics hechos sobre su propia ventana (`WindowFromPoint <> FSkipHwnd`), evitando auto-grabarse.
- Cada evento guarda timestamp `t: Int64` (tick), posición `(x, y)` y código de botón (`0` = movimiento, `$02/$08/$20` = press, `$04/$10/$40` = release); el array dinámico crece por bloques de 256 para evitar realojos constantes.
- **Reproducir** lanza `TPlayThread`, que reconstruye la secuencia respetando los tiempos originales relativos al primer evento: `SetCursorPos` para movimientos y `Mouse_Event` para clics.
- Estado en vivo refrescado por temporizador: `Grabando...`, `Reproduciendo...`, `N eventos - X s` o `Listo`.
- Detener grabación o reproducción corta el hilo con `Terminate` + `WaitFor` de forma síncrona.

### Persistencia de configuración
- Todo se guarda en `autoclicker.ini` junto al ejecutable (`ChangeFileExt(Application.ExeName, '.ini')`): configuración 100% portable, sin registro de Windows.
- Se guarda automáticamente al cerrar la app y cada vez que reasignas una hotkey; se carga al abrir.
- Secciones del INI: `[Interval]` (`H`, `Min`, `S`, `Ms`, `Rand`, `RandMs`), `[Repeat]` (`Veces`, `Count`), `[Cursor]` (`Mode`, `X`, `Y`) y `[Hotkeys]` (`L`, `R`, `W` con códigos de tecla virtual).

### Ciclo de vida seguro
- Al detener: espera acotada de 50 ms al worker; si está trabado dentro de `Mouse_Event`, la UI nunca se cuelga y el hilo se limpia solo al terminar (`ThreadDone`).
- Al cerrar la app: espera máxima de 3 s (30 × 100 ms) al worker, libera las 3 hotkeys con `UnregisterHotKey` y restaura la resolución del temporizador con `timeEndPeriod(1)`.

---

## Requisitos

| Dependencia | Versión |
|---|---|
| Windows | 7 o superior (`MOD_NOREPEAT` requiere Win7+) |
| Lazarus (con FPC incluido) | 2.x / 3.x |
| Free Pascal Compiler | 3.2.x |
| LCL (viene con Lazarus) | — |

No hay dependencias externas: solo LCL, la API Win32 y `MMSystem`.

---

## Instalación

```bash
# 1. Clonar repositorio
git clone <url-del-repo>
cd autoclicker

# 2a. Compilar desde consola con lazbuild
lazbuild autoclicker.lpi

# 2b. ...o abrir el proyecto en el IDE de Lazarus y pulsar F9
#     (Run > Run) tras abrir autoclicker.lpi
```

El ejecutable `autoclicker.exe` queda en la raíz del proyecto. Es portable: cópialo donde quieras junto con su `.ini`.

---

## Desarrollo

```bash
# Compilar el proyecto (release por defecto del .lpi)
lazbuild autoclicker.lpi

# Ejecutar
./autoclicker.exe

# Limpiar artefactos de compilación generados
rm -f *.o *.ppu *.obj *.compiled *.res
```

> Nota: si Windows Defender u otro antivirus marca el `.exe`, es un falso positivo típico de herramientas que sintetizan eventos de ratón (`Mouse_Event`).

---

## Uso

1. Define el intervalo (mínimo 1 ms) y, si quieres, activa la variación aleatoria en ms.
2. Elige repetición: número fijo de clics o *hasta parar*.
3. Elige posición: cursor actual o coordenadas fijas X/Y.
4. Pulsa **Iniciar** (arranca el clic izquierdo) o usa las hotkeys:
   - `F6` — alternar clic izquierdo
   - `F7` — alternar clic derecho
   - `F8` — alternar clic central
5. **Detener** apaga todos los canales. Desde *Hotkey setting* puedes cambiar F6/F7/F8 por cualquier otra tecla; desde *Recorder* puedes grabar y reproducir secuencias completas de movimiento y clic.

---

## Estructura del Proyecto

```
autoclicker/
├── autoclicker.lpr      # Punto de entrada GUI: inicializa Application y crea TMainForm
├── autoclicker.lpi      # Proyecto de Lazarus (configuración de compilación)
├── unit1.pas            # Ventana principal: intervalo, repetición, cursor,
│                        #   hotkeys globales, hilo de clics (TClicThread) e INI
├── unit1.lfm            # Diseño del formulario principal
├── unit2.pas            # THotDlg: diálogo de captura y reasignación de hotkeys
├── unit2.lfm            # Diseño del diálogo de hotkeys
├── unit3.pas            # TRecDlg + TRecThread/TPlayThread: grabadora y
│                        #   reproductor de macros de ratón
├── unit3.lfm            # Diseño del diálogo de grabación
├── icon.rc              # Recurso de icono para compilar en el ejecutable
├── autoclicker.ico      # Icono de la aplicación
└── autoclicker.ini      # Configuración persistente (se genera junto al .exe)
```

Los archivos `.o`, `.ppu`, `.res` y `.compiled` son artefactos de compilación y están ignorados por git.

---

## Stack Tecnológico

| Categoría | Tecnología |
|---|---|
| Lenguaje | Free Pascal (modo ObjFPC, `{$mode objfpc}{$H+}`) |
| Framework UI | LCL (Lazarus Component Library) |
| API de entrada | Win32: `RegisterHotKey`, `Mouse_Event`, `SetCursorPos`, `GetAsyncKeyState`, `GetCursorPos`, `WindowFromPoint` |
| Temporización | `GetTickCount64` + `timeBeginPeriod/timeEndPeriod` (MMSystem) |
| Concurrencia | `TThread` (worker de clics, grabador, reproductor) |
| Configuración | `TIniFile` (INI portable junto al ejecutable) |
| Destino | Ejecutable nativo Windows (GUI, `{$APPTYPE GUI}`) |

---

## Licencia

Proyecto personal sin licencia formal. Úsalo bajo tu propia responsabilidad: algunas aplicaciones y juegos penalizan la automatización de clics.
