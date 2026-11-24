#!/usr/bin/env python3
"""Benchmark comparativo de ASM Initio contra otras herramientas.

Consulta (la misma en todas):
    SELECT region, COUNT(*), SUM(monto), MIN(monto), MAX(monto)
    FROM ventas WHERE monto > 300 GROUP BY region

Modos:
    mem DIR      columnas binarias ya en memoria (asminitio --dump-bin DIR)
    csv ARCHIVO  de punta a punta: leer el CSV + consulta
Imprime "herramienta<TAB>ms" (mejor de N) y valida los resultados entre si.
"""
import sys, time, numpy as np

def best(fn, reps):
    t, out = 1e18, None
    for _ in range(reps):
        t0 = time.perf_counter(); out = fn(); t = min(t, (time.perf_counter() - t0) * 1e3)
    return t, out

def norm(rows):  # [(grupo, count, sum, min, max)] ordenado
    return sorted((str(r[0]), int(r[1]), int(r[2]), int(r[3]), int(r[4])) for r in rows)

def mem(d, reps):
    import pandas as pd, polars as pl, duckdb
    cols = {c: np.fromfile(f"{d}/{c}.u8", np.uint8) for c in ["region", "mes", "canal"]}
    cols["monto"] = np.fromfile(f"{d}/monto.u32", np.uint32)
    res = {}
    pdf = pd.DataFrame(cols)
    def q_pandas():
        g = pdf[pdf.monto > 300].groupby("region").monto.agg(["count", "sum", "min", "max"])
        return norm(g.itertuples())
    res["pandas"] = best(q_pandas, reps)
    pldf = pl.DataFrame(cols)
    def q_polars():
        g = (pldf.lazy().filter(pl.col("monto") > 300).group_by("region")
             .agg(pl.len().alias("n"), pl.col("monto").cast(pl.UInt64).sum().alias("s"), pl.col("monto").min().alias("mn"), pl.col("monto").max().alias("mx")).collect())
        return norm(g.rows())
    res["polars"] = best(q_polars, reps)
    con = duckdb.connect(); con.register("ventas", pdf)
    sql = "SELECT region, COUNT(*), SUM(monto), MIN(monto), MAX(monto) FROM ventas WHERE monto > 300 GROUP BY region"
    res["duckdb"] = best(lambda: norm(con.execute(sql).fetchall()), reps)
    return res

def csv(path, reps):
    import pandas as pd, polars as pl, duckdb
    res = {}
    names = {"AMBA", "PAMPEANA", "CUYO", "NOA", "NEA", "PATAGONIA"}
    def q_pandas():
        df = pd.read_csv(path, engine="pyarrow") if HAVE_PA else pd.read_csv(path)
        g = df[df.monto > 300].groupby("region").monto.agg(["count", "sum", "min", "max"])
        return norm(g.itertuples())
    res["pandas" + ("+pyarrow" if HAVE_PA else "")] = best(q_pandas, reps)
    def q_polars():
        g = (pl.scan_csv(path).filter(pl.col("monto") > 300).group_by("region")
             .agg(pl.len().alias("n"), pl.col("monto").sum().alias("s"), pl.col("monto").min().alias("mn"), pl.col("monto").max().alias("mx")).collect())
        return norm(g.rows())
    res["polars"] = best(q_polars, reps)
    con = duckdb.connect()
    sql = f"SELECT region, COUNT(*), SUM(monto), MIN(monto), MAX(monto) FROM read_csv('{path}') WHERE monto > 300 GROUP BY region"
    res["duckdb"] = best(lambda: norm(con.execute(sql).fetchall()), reps)
    return res

try:
    import pyarrow  # noqa
    HAVE_PA = True
except ImportError:
    HAVE_PA = False

if __name__ == "__main__":
    mode, arg = sys.argv[1], sys.argv[2]
    reps = int(sys.argv[3]) if len(sys.argv) > 3 else 3
    res = mem(arg, reps) if mode == "mem" else csv(arg, reps)
    ref = None
    for name, (ms, out) in res.items():
        print(f"{name}\t{ms:.1f}")
        key = [r[1:] for r in out]
        if ref is None: ref = key
        elif key != ref: print(f"  !! {name} difiere del resto", file=sys.stderr)
    print("filas:", [r[1:] for r in next(iter(res.values()))[1]], file=sys.stderr)
