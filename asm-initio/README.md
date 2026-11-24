# ASM Initio

Un mini GDE de flujo de datos, al estilo de los grafos de Ab Initio, escrito **100 % en ensamblador x86-64** para Linux, con **cero dependencias**.

![ASM Initio](docs/screenshot.png)

Un grafo `INPUT FILE → FILTER BY EXPRESSION → SORT → ROLLUP → OUTPUT TABLE` procesa 100.000 registros de ventas por región. Muestra la cantidad de registros en cada flujo, el resultado tabulado con barras y la consulta SQL equivalente, que se actualiza en vivo al cambiar el umbral.

## Qué tiene de particular

- **Sin libc, sin Xlib, sin loader dinámico.** Es un ELF estático que solo usa syscalls (`socket`, `connect`, `read`, `write`, `poll`, `clock_gettime`…).
- **Protocolo X11 implementado a mano:** handshake, autenticación `MIT-MAGIC-COOKIE-1` (lee `~/.Xauthority`), `CreateWindow`, `InternAtom`, `ChangeProperty`, `PutImage` y decodificación de eventos.
- **Render por software:** framebuffer propio, rectángulos redondeados, círculos, degradés y texto con antialiasing (alfa de 8 bits) a partir de una fuente bitmap embebida.
- **Pipeline real, no simulado:** filtro, *counting/radix sort* estable por región y *rollup* sobre la entrada ordenada. El tiempo real del pipeline se mide y se muestra; la animación es solo visual.
- Resultados validados contra una implementación de referencia en Python.

## Compilar y ejecutar

Requisitos: solo `nasm` y `ld` (binutils).

```sh
cd asm-initio
make
./build/asminitio
```

Necesita un servidor X con visual TrueColor de 24/32 bits: Xorg, o XWayland en escritorios Wayland. En WSL2 funciona con WSLg.

## Controles

| Acción | Tecla / mouse |
|---|---|
| Ejecutar el grafo | `R`, `Enter`, `Espacio` o botón **EJECUTAR** |
| Subir / bajar el umbral de `monto` | `+` / `-`, rueda del mouse o botones |
| Generar datos nuevos | `N` o botón **DATOS NUEVOS** |
| Salir | `Q`, `Esc` o cerrar la ventana |

## Estructura

```
asm-initio/
├── src/asminitio.asm   # todo el programa
├── src/fonts.inc       # métricas de las fuentes (generado)
├── src/font_*.bin      # glifos con alfa de 8 bits, embebidos con incbin
├── tools/genfont.py    # rasteriza JetBrains Mono (solo para regenerar fuentes)
└── Makefile
```

Las fuentes bitmap derivan de [JetBrains Mono](https://www.jetbrains.com/lp/mono/) (SIL Open Font License 1.1).
