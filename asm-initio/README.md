# ASM Initio

Un GDE de flujo de datos, al estilo de los grafos de Ab Initio, escrito **100 % en ensamblador x86-64** para Linux, con **cero dependencias**.

![ASM Initio](docs/screenshot.png)

El grafo `INPUT FILE → FILTER BY EXPRESSION → SORT → ROLLUP → OUTPUT TABLE` procesa hasta **1.000.000 de registros** de ventas (región, mes, canal y monto). Los componentes se arrastran, sus propiedades se editan, se pueden ver los registros que pasan por cada flujo y el SQL equivalente se reescribe en vivo.

## Qué podés hacer

| | |
|---|---|
| **Arrastrar componentes** | Los flujos son curvas Bézier con antialiasing que los siguen. |
| **Inspector de propiedades** | Click en un componente para ver métricas (entrada, salida, tiempo y throughput medidos) y editar sus parámetros. |
| **Filtro editable** | Seis operadores (`>`, `>=`, `<`, `<=`, `=`, `!=`) y umbral con botones, rueda del mouse o tipeando el valor. |
| **Agrupar por** | Región, mes o canal. SORT y ROLLUP se reconfiguran juntos. |
| **Resultado** | COUNT, SUM, AVG, MIN y MAX por grupo, con barras. Click en un encabezado ordena por esa columna (asc/desc). |
| **Ver datos** | Click en un flujo para ver sus registros reales. Tiene scroll con rueda, PgUp/PgDn y una barra arrastrable. En el flujo ordenado se marcan los cortes de grupo. |
| **SQL vivo** | La consulta equivalente refleja operador, umbral, clave y orden, y resalta la cláusula del componente seleccionado. |
| **Exportar CSV** | Escribe `resultado.csv` con `open`/`write`/`close`. |
| **Más** | Menú contextual (click derecho), doble click para ver la salida, tooltips, notificaciones, ventana redimensionable. |

<p>
<img src="docs/animacion.png" width="49%" alt="Animación del grafo">
<img src="docs/visor.png" width="49%" alt="Visor de datos">
</p>

## Lo técnico

- **ELF estático sin libc, sin Xlib y sin loader dinámico.** Solo syscalls: `socket`, `connect`, `poll`, `read`, `write`, `mmap`, `shmget`, `shmat`, `clock_gettime`, `open`…
- **Protocolo X11 implementado a mano:**
  - handshake y autenticación `MIT-MAGIC-COOKIE-1` (lee `~/.Xauthority`);
  - `GetKeyboardMapping`, para que las teclas funcionen con cualquier layout;
  - `InternAtom`, `_NET_WM_NAME`, `WM_DELETE_WINDOW` y size hints;
  - cursores del sistema (`CreateGlyphCursor`);
  - eventos de teclado, mouse, arrastre y resize.
- **Extensión MIT-SHM:** el framebuffer es un segmento de memoria compartida con el servidor X (`ShmPutImage`, sincronizado con `ShmCompletion`). Si no está disponible, por ejemplo con un servidor remoto o en algunos contenedores, cae automáticamente a `PutImage` por franjas.
- **Render por software:**
  - alpha blending en dos canales por operación;
  - rectángulos redondeados con antialiasing (cobertura calculada con SSE);
  - curvas Bézier cúbicas en punto fijo, rasterizadas con una máscara de cobertura;
  - sombras, degradés y texto con alfa de 8 bits.
- **UI en modo inmediato:** cada frame se dibuja completo y registra sus zonas clickeables; los eventos se resuelven contra esa lista.
- **Pipeline:**
  - filtro *branchless* (`setcc` + suma), especializado por operador;
  - *counting sort* estable O(n);
  - *rollup* sobre la entrada ordenada;
  - *insertion sort* del resultado.
  - Cada etapa se mide por separado.
- Resultados validados contra una implementación de referencia en Python.

## Compilar y ejecutar

Requisitos: solo `nasm` y `ld` (binutils).

```sh
cd asm-initio
make
./build/asminitio
```

Necesita un servidor X con visual TrueColor de 24/32 bits: Xorg, o XWayland en escritorios Wayland. En WSL2 funciona con WSLg.

## Teclado

| Tecla | Acción |
|---|---|
| `R` / `Enter` / `Espacio` | Ejecutar el grafo |
| `N` | Datos nuevos |
| `1` `2` `3` | 10K / 100K / 1M registros |
| `+` / `-` | Umbral del filtro |
| `F` | Tipear el umbral (`Enter` confirma, `Esc` cancela) |
| `O` | Siguiente operador del filtro |
| `G` | Siguiente clave de agrupación |
| `V` | Ver datos de salida del componente seleccionado |
| `Tab` / `←` `→` | Recorrer componentes |
| `↑` `↓` `PgUp` `PgDn` `Inicio` `Fin` | Desplazar tablas |
| `E` | Exportar CSV |
| `Esc` | Cerrar menú / deseleccionar / volver (sale si no hay nada abierto) |
| `Q` | Salir |

## Estructura

```
asm-initio/
├── src/main.asm    # entrada, bucle principal, datos y estado
├── src/x11.asm     # protocolo X11, auth, MIT-SHM, teclado, cursores
├── src/gfx.asm     # rasterizador: blending, AA, Bézier, texto
├── src/data.asm    # generador, pipeline, orden, exportación CSV
├── src/ui.asm      # hit testing, eventos, paneles y widgets
├── src/defs.inc    # constantes, layout y macros
├── src/font_*.bin  # glifos con alfa de 8 bits (incbin)
├── tools/genfont.py  # rasteriza JetBrains Mono (solo para regenerar fuentes)
└── Makefile
```

Las fuentes bitmap derivan de [JetBrains Mono](https://www.jetbrains.com/lp/mono/) (SIL Open Font License 1.1).
