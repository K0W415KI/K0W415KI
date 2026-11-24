#!/usr/bin/env bash
# Corre el benchmark comparativo completo. Uso: bench/run_all.sh DIR_DE_TRABAJO
# Requiere: python3 con numpy, pandas, polars, duckdb (y opcional pyarrow), gcc.
set -euo pipefail
cd "$(dirname "$0")/.."
W="${1:?indicá un directorio de trabajo}"
BIN=./build/asminitio
mkdir -p "$W/b10" "$W/b100"

echo "### generando datos"
$BIN --rows 10M  --dump-bin "$W/b10"
$BIN --rows 100M --dump-bin "$W/b100"
$BIN --rows 10M  --dump-csv "$W/v10.csv"
$BIN --rows 100M --dump-csv "$W/v100.csv"
gcc -O3 -march=native -fopenmp bench/baseline.c -o "$W/baseline"

for n in 10M 100M; do
  echo; echo "### en memoria · $n"
  $BIN --rows $n --bench 5 | grep -E "TOTAL|^  [A-Z]"
  $BIN --rows $n --bench 5 --threads 1 | grep TOTAL
  d="$W/b${n%M}"
  "$W/baseline" "$d" 5 2>/dev/null
  python3 bench/bench.py mem "$d" 3
done

for n in 10 100; do
  echo; echo "### CSV de punta a punta · ${n}M"
  $BIN --csv "$W/v$n.csv" --bench 3 | grep -E "carga|TOTAL"
  python3 bench/bench.py csv "$W/v$n.csv" 2
done
