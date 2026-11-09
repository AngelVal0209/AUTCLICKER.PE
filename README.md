# AutoClicker

Autoclicker nativo para Windows que pulsa los botones izquierdo, derecho y central del ratón a intervalos configurables, con **Modo Hold** (*mantener pulsado para disparar*), hotkeys globales, indicador de **CPS en tiempo real**, aleatoriedad anti-detección y grabadora de macros. Construido en Free Pascal con LCL (Lazarus), sin dependencias externas: un solo `.exe` portátil.

![Lenguaje](https://img.shields.io/badge/lenguaje-Free_Pascal_(ObjFPC)-2E7D32)
![IDE](https://img.shields.io/badge/framework-LCL_|_Lazarus-0F62A0)
![Plataforma](https://img.shields.io/badge/plataforma-Windows_7+-0078D6)
![API](https://img.shields.io/badge/api-Win32_|_RawInput_|_MMSystem-5C2D91)
![Config](https://img.shields.io/badge/config-INI_portable-E6A700)

[Repositorio](https://github.com/AngelVal0209/AUTCLICKER.PE) · [Descargar `autoclicker.exe`](https://github.com/AngelVal0209/AUTCLICKER.PE/raw/main/autoclicker.exe)

---

## Características

### Motor de clics (`TClicThread`) e inyección atómica
- Hilo worker independiente de la UI con espera precisa por evento (`WaitForSingleObject` + `timeBeginPeriod(1)`), sin *busy-waiting* ni congelamientos.
- **Inyección atómica por lote (`SendClickPair` / `SendReleaseAndClickPair`)**: envía el par `DOWN` + `UP` en una única syscall `SendInput`, impidiendo que paquetes de movimiento de ratones de 1000–8000 Hz se intercalen entre la pulsación y la liberación (evitando pérdida de sensibilidad o girotes de cámara en juegos).
- Programación independiente por canal con `GetTickCount64` (`next[0..2]`): izquierdo (`$02/$04`), derecho (`$08/$10`) y central (`$20/$40`).
- Contador global `FCount: Int64`; al alcanzar el límite configurado notifica a la ventana principal (`WM_WORKER_DONE`) y detiene el ciclo limpiamente.

### Modo Hold — Mantener pulsado para autoclic (`TRawMouseThread`)
- Mantén presionado el botón físico del ratón para disparar ráfagas continuas y **suelta para parar al instante**.
- **Detección física sin lag (`Raw Input` + `HWND_MESSAGE`)**: distingue tus pulsaciones físicas reales (`hDevice <> 0`) de los clics inyectados (`hDevice = 0`) usando una ventana ligera *message-only* con drenaje en lote (`PeekMessage`) a prioridad normal, descartando el 99.9 % de paquetes de movimiento sin robar CPU al juego.
- **Respeto de clics simples**: al presionar el botón físico espera 1 intervalo antes de inyectar la ráfaga, permitiendo hacer clics normales en menús o inventario sin dobles clics accidentales.
- **Clic derecho libre por defecto (`chkHoldR`)**: el modo Hold actúa por defecto solo en el clic izquierdo para que puedas apuntar con la mira (ADS), rotar cámara o cubrirte con clic derecho sin interferencias; incluye casilla opcional para habilitar también el clic derecho en modo Hold.

### Intervalo con aleatoriedad y lectura de CPS en vivo
- Intervalo configurable en horas, minutos, segundos y milisegundos (`sedH/sedMin/sedS/sedMs`); piso de seguridad de 10 ms en modo Hold y 1 ms en modo normal.
- **Variación aleatoria (`±RandMs`)**: desvío uniforme acotado dinámicamente para romper patrones mecánicos.
- **Calculadora de cadencia en tiempo real (`lblCps`)**: muestra al instante el intervalo efectivo en `ms` y los clics por segundo (`CPS`), o el rango `mín–máx` de `ms` y `CPS` cuando la variación aleatoria está activa.
- **Edición en caliente (`Snapshot`)**: cualquier ajuste de intervalo, variación o coordenadas se aplica en vivo sin necesidad de detener el autoclicker.

### Modos de repetición y posición multimonitor
- **Repetir N veces** o **Repetir hasta detener (infinito)** tanto en modo normal como en modo Hold.
- **Posición actual (libre)** o **Coordenadas fijas (`X/Y`)** compatibles con configuraciones multimonitor (`SM_XVIRTUALSCREEN..SM_CYVIRTUALSCREEN`).

### Hotkeys globales (4 canales)
- Registradas a nivel de sistema con `RegisterHotKey` + `MOD_NOREPEAT`, funcionan con la app en segundo plano:
  - **Clic Izquierdo** (por defecto `F6`)
  - **Clic Derecho** (por defecto `F7`)
  - **Clic Central** (por defecto `F8`)
  - **Alternar Modo Hold** (por defecto `F1`)
- Desde **Configurar Hotkeys...** (`THotDlg`) puedes reasignar cualquiera de las 4 teclas en caliente con validación contra teclas duplicadas u ocupadas.

### Grabadora y reproductor de macros (`TRecDlg`)
- **Grabar (`TRecThread`)**: captura movimientos y transiciones `DOWN/UP` de los tres botones cada 5 ms con contador de eventos en tiempo real.
- Ignora automáticamente los clics sobre cualquier botón o control de la propia ventana de grabación (`GetAncestor(..., GA_ROOT)`).
- **Reproducir (`TPlayThread`)**: ejecuta la secuencia respetando los tiempos originales y reactiva los controles automáticamente al finalizar.

### Persistencia portable (`autoclicker.ini`)
- Guarda y restaura intervalos, aleatoriedad, repetición, modo y coordenadas de cursor, opción de clic derecho en Hold y las 4 hotkeys en `autoclicker.ini` junto al ejecutable, sin tocar el registro de Windows.

---

## Requisitos

| Dependencia | Versión |
|---|---|
| Windows | 7 / 10 / 11 (`MOD_NOREPEAT` requiere Win7+) |
| Lazarus (para compilar) | 2.x / 3.x / 4.x |
| Free Pascal Compiler | 3.2.x |

---

## Instalación

### Opción A — Descargar el ejecutable (recomendada)

1. Descarga [`autoclicker.exe`](https://github.com/AngelVal0209/AUTCLICKER.PE/raw/main/autoclicker.exe) desde el repositorio.
2. Guárdalo en cualquier carpeta y ejecútalo con doble clic.

> **Nota para juegos que corren como Administrador**: si el juego se ejecuta con permisos elevados, ejecuta también `autoclicker.exe` como Administrador para que Windows (UIPI) permita enviar `SendInput` a la ventana del juego.

### Opción B — Clonar el repositorio

```bash
git clone https://github.com/AngelVal0209/AUTCLICKER.PE.git
cd AUTCLICKER.PE
./autoclicker.exe
```

---

## Desarrollo

Para compilar desde código fuente necesitas [Lazarus](https://www.lazarus-ide.org/) con FPC 3.2.x:

```bash
# Compilar el proyecto desde consola
lazbuild -B autoclicker.lpi

# Ejecutar
./autoclicker.exe
```

---

## Estructura del Proyecto

```
autoclicker/
├── autoclicker.lpr      # Punto de entrada GUI: inicializa Application y crea TMainForm
├── autoclicker.lpi      # Proyecto de Lazarus (configuración de compilación)
├── unit1.pas            # Ventana principal: motor TClicThread, Raw Input (TRawMouseThread),
│                        #   inyección atómica SendInput, hotkeys globales, CPS en vivo e INI
├── unit1.lfm            # Diseño del formulario principal
├── unit2.pas            # THotDlg: captura y reasignación de las 4 hotkeys en caliente
├── unit2.lfm            # Diseño del diálogo de hotkeys
├── unit3.pas            # TRecDlg + TRecThread/TPlayThread: grabadora y reproductor de macros
├── unit3.lfm            # Diseño del diálogo de grabación
├── icon.rc              # Recurso de icono
├── autoclicker.ico      # Icono de la aplicación
└── autoclicker.ini      # Configuración persistente (generado junto al .exe)
```

---

## Stack Tecnológico

| Categoría | Tecnología |
|---|---|
| Lenguaje | Free Pascal (`{$mode objfpc}{$H+}`) |
| Framework UI | LCL (Lazarus Component Library) |
| API de entrada | Win32: `SendInput`, `RegisterRawInputDevices` (`WM_INPUT`), `RegisterHotKey`, `SetCursorPos`, `GetAsyncKeyState` |
| Temporización | `GetTickCount64` + `WaitForSingleObject` + `timeBeginPeriod/timeEndPeriod` (`MMSystem`) |
| Concurrencia | `TThread` (`TClicThread`, `TRawMouseThread`, `TRecThread`, `TPlayThread`) |
| Configuración | `TIniFile` (INI portable junto al ejecutable) |

---

## Licencia

Proyecto personal. Úsalo bajo tu propia responsabilidad.
