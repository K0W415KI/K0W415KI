# ASM Initio contra otras herramientas

Todas las herramientas ejecutan la misma consulta sobre los mismos datos, y todas devuelven exactamente los mismos números:

```sql
SELECT region, COUNT(*), SUM(monto), MIN(monto), MAX(monto)
FROM ventas WHERE monto > 300 GROUP BY region
```

**Máquina:** Xeon @ 2,1 GHz, 4 núcleos (AVX-512), 15 GB de RAM, Linux.
**Versiones:** DuckDB 2.0.1 · Polars 2.1.0 · pandas 3.0.5 (con pyarrow) · gcc 13.3 · PostgreSQL 16.
**Método:** mejor tiempo de 3 a 5 repeticiones, con los archivos ya en la caché del sistema operativo. Los scripts están en esta carpeta (`run_all.sh`, `bench.py`, `baseline.c`).

## 1. Datos ya en memoria (solo la consulta)

| Herramienta | 10 M filas | 100 M filas |
|---|---:|---:|
| **ASM Initio · ROLLUP en memoria** (4 hilos) | **7,8 ms** | **75–84 ms** |
| C `gcc -O3 -march=native` + OpenMP (4 hilos) | 12,9 ms | 119 ms |
| DuckDB | 14,1 ms | 117 ms |
| Polars | 17,0 ms | 152 ms |
| ASM Initio · FILTER → SORT → ROLLUP (fiel al grafo) | 16,8 ms | 246 ms |
| ASM Initio · en memoria, 1 hilo | 26,4 ms | 276 ms |
| C `-O3`, 1 hilo | 48,2 ms | 461 ms |
| pandas | 269 ms | 2.911 ms |

Con 200 M de filas, ASM Initio tarda 148 ms en memoria y 460 ms en modo fiel, con unos 3 GB de RAM.

## 2. De punta a punta desde CSV (lectura + consulta)

| Herramienta | 10 M (222 MB) | 100 M (2,2 GB) |
|---|---:|---:|
| **ASM Initio** (carga paralela + en memoria) | **232 ms** | **2,09 s** |
| Polars (`scan_csv`, lazy) | 235 ms | 2,66 s |
| DuckDB (`read_csv`) | 329 ms | 2,94 s |
| pandas (`read_csv`, motor pyarrow) | 1.093 ms | 13,6 s |

ASM Initio lee el CSV a unos 1,1 GB/s.

## 3. PostgreSQL 16 (tabla con 100 M filas)

| Escenario | 10 M | 100 M |
|---|---:|---:|
| Consulta dentro de PostgreSQL (pushdown, workers paralelos) | 325 ms | 2,6 s |
| Extraer con `psql` (`COPY ... TO STDOUT` a /dev/null) | 2,9 s | — |
| Extraer con ASM Initio (`COPY` + parseo) | 3,2 s | 32,4 s |
| Cada consulta posterior en ASM Initio, ya cargado | 13 ms | 71 ms |

Extraer está limitado por el servidor: `COPY` serializa en un solo proceso a unos 70 MB/s, y el cliente de ASM Initio va casi a la par de `psql`.

## Conclusiones

1. **En esta consulta, ASM Initio es el más rápido medido.** En memoria es entre 1,4 y 2 veces más rápido que DuckDB y Polars. Desde CSV empata con Polars en 10 M y le gana un 20 % en 100 M. Contra pandas, la diferencia es de 5 a 35 veces.
2. **La ventaja viene de la especialización más que del ensamblador.** Las claves son bytes (máximo 64 grupos), el filtro no tiene saltos y la agregación va fusionada en una sola pasada. C con el mismo algoritmo queda cerca (119 ms contra 75–84 ms). Con un solo hilo, la diferencia contra C (276 ms contra 461 ms) se explica por el filtro sin saltos.
3. **El modo fiel al grafo cuesta unas 3 veces más.** Materializar FILTER → SORT → ROLLUP es más lento que agregar en memoria. Es la misma decisión que en Ab Initio entre un Rollup sobre entrada ordenada y uno en memoria.
4. **Con PostgreSQL, conviene empujar la consulta al servidor.** Extraer 100 M filas tarda 32 s; resolver la consulta allá, 2,6 s. Extraer solo vale la pena para muchas consultas interactivas sobre el mismo conjunto: después cada una tarda unos 70 ms.
5. **Lo que no mide este benchmark:** DuckDB y Polars resuelven SQL arbitrario, joins, decimales, fechas, nulos, volcado a disco y datasets más grandes que la RAM. ASM Initio resuelve una sola forma de consulta. La velocidad se parece; la generalidad, no.

## Reproducir

```sh
cd asm-initio && make
bench/run_all.sh /tmp/bench      # genera datos, corre todo y valida resultados
```
