// Baseline en C: el mismo FILTER + ROLLUP en memoria que ASM Initio,
// sobre las columnas binarias que vuelca `asminitio --dump-bin DIR`.
// gcc -O3 -march=native -fopenmp baseline.c -o baseline
#include <fcntl.h>
#include <omp.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

static void *map(const char *dir, const char *name, size_t *n) {
    char p[512]; snprintf(p, sizeof p, "%s/%s", dir, name);
    int fd = open(p, O_RDONLY); struct stat st; fstat(fd, &st); *n = st.st_size;
    void *m = mmap(0, st.st_size, PROT_READ, MAP_PRIVATE | MAP_POPULATE, fd, 0);
    close(fd); return m;
}
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1e3 + t.tv_nsec / 1e6; }

typedef struct { uint64_t cnt, sum; uint32_t mn, mx; } agg_t;

int main(int argc, char **argv) {
    const char *dir = argv[1]; int reps = argc > 2 ? atoi(argv[2]) : 5; uint32_t thr = 300;
    size_t n, n4; const uint8_t *key = map(dir, "region.u8", &n); const uint32_t *m = map(dir, "monto.u32", &n4);
    for (int mode = 0; mode < 2; mode++) {
        int threads = mode ? omp_get_max_threads() : 1; double best = 1e18; agg_t res[64];
        for (int r = 0; r < reps; r++) {
            double t0 = now();
            agg_t part[64][64] = {0};
            for (int t = 0; t < 64; t++) for (int k = 0; k < 64; k++) part[t][k].mn = UINT32_MAX;
            #pragma omp parallel num_threads(threads)
            {
                int t = omp_get_thread_num(); agg_t *a = part[t];
                #pragma omp for schedule(static)
                for (size_t i = 0; i < n; i++) {
                    uint32_t v = m[i];
                    if (v > thr) { agg_t *g = &a[key[i]]; g->cnt++; g->sum += v; if (v < g->mn) g->mn = v; if (v > g->mx) g->mx = v; }
                }
            }
            for (int k = 0; k < 64; k++) { res[k] = (agg_t){0, 0, UINT32_MAX, 0};
                for (int t = 0; t < threads; t++) { res[k].cnt += part[t][k].cnt; res[k].sum += part[t][k].sum;
                    if (part[t][k].mn < res[k].mn) res[k].mn = part[t][k].mn; if (part[t][k].mx > res[k].mx) res[k].mx = part[t][k].mx; } }
            double dt = now() - t0; if (dt < best) best = dt;
        }
        printf("%s\t%.2f\n", mode ? "c_openmp" : "c_1hilo", best);
        if (mode) for (int k = 0; k < 6; k++) fprintf(stderr, "%d\t%lu\t%lu\t%u\t%u\n", k, res[k].cnt, res[k].sum, res[k].mn, res[k].mx);
    }
    return 0;
}
