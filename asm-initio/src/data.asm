; =============================================================================
;  data.asm -- dataset columnar y pipeline paralelo
;
;  Columnas (mmap reservado, hasta NCAP filas):
;     col_key[0..2]  bytes: region, mes, canal (codigos de diccionario)
;     p_monto        uint32
;  Pipeline (nthreads hilos):
;     FILTER  -> sin saltos (setcc), por chunk; cuenta por clave
;                (en modo "en memoria" ademas agrega count/sum/min/max)
;     SORT    -> counting sort estable y paralelo (posiciones por hilo y clave)
;     ROLLUP  -> recorre la entrada ordenada por corridas de clave
;     OUTPUT  -> ordena las filas del resultado
; =============================================================================
section .text

; now_ns -> rax (CLOCK_MONOTONIC)
now_ns:
        mov     eax, SYS_CLOCK_GETTIME
        mov     edi, 1
        lea     rsi, [timespec]
        syscall
        mov     rax, [timespec]
        imul    rax, rax, 1000000000
        add     rax, [timespec+8]
        ret

now_ms:
        call    now_ns
        xor     edx, edx
        mov     ecx, 1000000
        div     rcx
        ret

; mmap_reserve(rsi = bytes) -> rax (reserva virtual, sin cargo hasta usarse)
mmap_reserve:
        mov     eax, SYS_MMAP
        xor     edi, edi
        mov     edx, 3
        mov     r10d, 0x4022                ; PRIVATE | ANONYMOUS | NORESERVE
        mov     r8, -1
        xor     r9d, r9d
        syscall
        cmp     rax, -4096
        ja      .fail
        ret
.fail:  DIE     e_mem

alloc_data:
        push    rbx
        xor     ebx, ebx
.k:     mov     rsi, NCAP
        call    mmap_reserve
        mov     [col_key + rbx*8], rax
        inc     ebx
        cmp     ebx, 3
        jb      .k
        mov     rsi, NCAP*4
        call    mmap_reserve
        mov     [p_monto], rax
        mov     rsi, NCAP*4 + 64
        call    mmap_reserve
        mov     [p_gidx], rax
        mov     rsi, NCAP*4
        call    mmap_reserve
        mov     [p_fidx], rax
        mov     rsi, NCAP*4
        call    mmap_reserve
        mov     [p_sidx], rax
        pop     rbx
        ret

; set_gen_names: diccionarios del dataset generado
set_gen_names:
        xor     ecx, ecx
.r:     mov     rax, [region_name + rcx*8]
        mov     [col_names + rcx*8], rax
        inc     ecx
        cmp     ecx, 6
        jb      .r
        xor     ecx, ecx
.m:     mov     rax, [month_name + rcx*8]
        mov     [col_names + MAXGRP*8 + rcx*8], rax
        inc     ecx
        cmp     ecx, 12
        jb      .m
        xor     ecx, ecx
.c:     mov     rax, [canal_name + rcx*8]
        mov     [col_names + MAXGRP*16 + rcx*8], rax
        inc     ecx
        cmp     ecx, 3
        jb      .c
        mov     dword [col_ngrp], 6
        mov     dword [col_ngrp+4], 12
        mov     dword [col_ngrp+8], 3
        ret

; -----------------------------------------------------------------------------
;  Generador: bloques de 64K filas, cada uno con su semilla derivada de
;  (seed, bloque). El resultado no depende de la cantidad de hilos.
; -----------------------------------------------------------------------------
%define GEN_SHIFT 16

%macro XS 0                                 ; xorshift32 sobre r13d -> eax
        mov     eax, r13d
        mov     edx, eax
        shl     edx, 13
        xor     eax, edx
        mov     edx, eax
        shr     edx, 17
        xor     eax, edx
        mov     edx, eax
        shl     edx, 5
        xor     eax, edx
        mov     r13d, eax
%endmacro

gen_data:
        push    rbx
        call    now_ns
        mov     rbx, rax
        mov     eax, [seed]
        mov     [seed0], eax
        mov     eax, [nrec]
        add     eax, (1 << GEN_SHIFT) - 1
        shr     eax, GEN_SHIFT
        mov     [gen_blocks], eax
        lea     rdi, [gen_worker]
        call    parallel
        call    set_gen_names
        call    now_ns
        sub     rax, rbx
        mov     [load_ns], rax
        mov     byte [src_mode], 0
        mov     qword [load_bytes], 0
        pop     rbx
        ret

gen_worker:
        push    rbx
        push    rbp
        push    r12
        push    r13
        push    r14
        push    r15
        mov     r12d, edi                   ; bloque actual
        mov     r8, [col_key]
        mov     r9, [col_key+8]
        mov     r10, [col_key+16]
        mov     r11, [p_monto]
.blk:   cmp     r12d, [gen_blocks]
        jae     .done
        ; semilla del bloque: splitmix32(seed0 + bloque * phi)
        mov     eax, r12d
        imul    eax, 0x9E3779B9
        add     eax, [seed0]
        mov     edx, eax
        shr     edx, 16
        xor     eax, edx
        imul    eax, 0x7feb352d
        mov     edx, eax
        shr     edx, 15
        xor     eax, edx
        imul    eax, 0x846ca68b
        mov     edx, eax
        shr     edx, 16
        xor     eax, edx
        or      eax, 1
        mov     r13d, eax
        mov     esi, r12d
        shl     esi, GEN_SHIFT              ; fila inicial
        lea     edi, [rsi + (1 << GEN_SHIFT)]
        cmp     edi, [nrec]
        jbe     .row
        mov     edi, [nrec]
.row:   cmp     esi, edi
        jae     .nextblk
        XS
        mov     ebx, eax
        mov     ecx, eax
        and     ecx, 15
        movzx   r14d, byte [region_weights + rcx]
        mov     [r8 + rsi], r14b
        mov     ecx, ebx
        shr     ecx, 8
        and     ecx, 0xffff
        imul    ecx, 12
        shr     ecx, 16
        mov     [r9 + rsi], cl
        mov     r15d, ecx
        mov     ecx, ebx
        shr     ecx, 24
        and     ecx, 15
        movzx   ebx, byte [canal_weights + rcx]
        mov     [r10 + rsi], bl
        XS
        mov     ecx, [region_max + r14*4]
        imul    rax, rcx
        shr     rax, 32                     ; [0, max)
        imul    eax, [month_factor + r15*4]
        imul    rax, rax, 0x51EB851F
        shr     rax, 37                     ; / 100
        cmp     ebx, 2                      ; mayorista: 1,5x
        jne     .nm
        lea     eax, [rax + rax*2]
        shr     eax, 1
.nm:    add     eax, 10
        mov     [r11 + rsi*4], eax
        inc     esi
        jmp     .row
.nextblk:
        add     r12d, [nthreads]
        jmp     .blk
.done:  pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbp
        pop     rbx
        ret

; -----------------------------------------------------------------------------
;  Pipeline
; -----------------------------------------------------------------------------

; FILTER + conteo por clave (modo ordenado)
%macro FCNT 1
%%lp:   cmp     rcx, r14
        jae     %%done
        mov     [r9 + rdx*4], ecx
        movzx   ebx, byte [rdi + rcx]
        xor     ebp, ebp
        cmp     [rsi + rcx*4], r8d
        %1      bpl
        add     edx, ebp
        add     [r10 + rbx*4], ebp
        inc     rcx
        jmp     %%lp
%%done: jmp     .fdone
%endmacro

; FILTER + agregacion completa por clave (modo en memoria)
%macro FAGG 1
%%lp:   cmp     rcx, r14
        jae     %%done
        mov     eax, [rsi + rcx*4]
        movzx   ebx, byte [rdi + rcx]
        mov     [r9 + rdx*4], ecx
        xor     ebp, ebp
        cmp     eax, r8d
        %1      bpl
        add     edx, ebp
        add     [r10 + rbx*4], ebp          ; count
        neg     rbp                         ; 0 o -1
        mov     r15, rax
        and     r15, rbp
        add     [r11 + rbx*8], r15          ; sum
        mov     r15d, ebp
        not     r15d
        or      r15d, eax                   ; candidato a minimo
        cmp     r15d, [r12 + rbx*4]
        jae     %%nmin
        mov     [r12 + rbx*4], r15d
%%nmin: mov     r15d, eax
        and     r15d, ebp                   ; candidato a maximo
        cmp     r15d, [r13 + rbx*4]
        jbe     %%nmax
        mov     [r13 + rbx*4], r15d
%%nmax: inc     rcx
        jmp     %%lp
%%done: jmp     .fdone
%endmacro

; partials_ptrs(edi = tid) -> r10 cnt, r11 sum, r12 min, r13 max (y los limpia)
partials_reset:
        mov     eax, edi
        shl     eax, 8                      ; tid * 64 * 4
        lea     r10, [t_cnt + rax]
        lea     r12, [t_min + rax]
        lea     r13, [t_max + rax]
        shl     eax, 1
        lea     r11, [t_sum + rax]
        xor     ecx, ecx
.z:     mov     dword [r10 + rcx*4], 0
        mov     qword [r11 + rcx*8], 0
        mov     dword [r12 + rcx*4], -1
        mov     dword [r13 + rcx*4], 0
        inc     ecx
        cmp     ecx, MAXGRP
        jb      .z
        ret

filter_worker:
        push    rbx
        push    rbp
        push    r12
        push    r13
        push    r14
        push    r15
        push    rdi
        mov     r15d, edi
        mov     esi, [nrec]
        call    chunk
        mov     [t_start + r15*8], rax
        mov     r14, rdx                    ; fin
        push    rax
        mov     edi, r15d
        call    partials_reset
        pop     rcx                         ; i = inicio
        mov     r9, [p_gidx]
        lea     r9, [r9 + rcx*4]            ; salida del hilo
        mov     rsi, [p_monto]
        mov     eax, [group_key]
        mov     rdi, [col_key + rax*8]
        mov     r8d, [thr]
        xor     edx, edx
        movzx   eax, byte [rmode]
        imul    eax, 6
        add     eax, [filt_op]
        jmp     [.ops + rax*8]
.ops:   dq      .c0, .c1, .c2, .c3, .c4, .c5, .a0, .a1, .a2, .a3, .a4, .a5
.c0:    FCNT    seta
.c1:    FCNT    setae
.c2:    FCNT    setb
.c3:    FCNT    setbe
.c4:    FCNT    sete
.c5:    FCNT    setne
.a0:    FAGG    seta
.a1:    FAGG    setae
.a2:    FAGG    setb
.a3:    FAGG    setbe
.a4:    FAGG    sete
.a5:    FAGG    setne
.fdone: pop     rdi
        mov     [t_fc + rdi*4], edx
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbp
        pop     rbx
        ret

; compact_worker: gidx (por chunk) -> fidx contiguo
compact_worker:
        mov     eax, edi
        mov     rsi, [t_start + rax*8]
        shl     rsi, 2
        add     rsi, [p_gidx]
        mov     rdi, [t_foff + rax*8]
        shl     rdi, 2
        add     rdi, [p_fidx]
        mov     ecx, [t_fc + rax*4]
        shl     rcx, 2
        rep movsb
        ret

; scatter_worker: counting sort estable (cada hilo escribe sus posiciones)
scatter_worker:
        push    rbx
        mov     eax, edi
        mov     ecx, [t_fc + rax*4]
        mov     rsi, [t_start + rax*8]
        shl     rsi, 2
        add     rsi, [p_gidx]
        shl     eax, 8
        lea     r10, [t_pos + rax]
        mov     eax, [group_key]
        mov     rdi, [col_key + rax*8]
        mov     r9, [p_sidx]
        xor     edx, edx
.lp:    cmp     edx, ecx
        jae     .done
        mov     eax, [rsi + rdx*4]
        movzx   ebx, byte [rdi + rax]
        mov     r8d, [r10 + rbx*4]
        inc     dword [r10 + rbx*4]
        mov     [r9 + r8*4], eax
        inc     edx
        jmp     .lp
.done:  pop     rbx
        ret

; rollup_worker: agrega por corridas de clave sobre la entrada ordenada
rollup_worker:
        push    rbx
        push    rbp
        push    r12
        push    r13
        push    r14
        push    r15
        push    rdi
        mov     esi, [n_filter]
        call    chunk
        mov     rbx, rax                    ; i
        mov     r14, rdx                    ; fin
        mov     edi, [rsp]
        call    partials_reset
        cmp     rbx, r14
        jae     .out
        mov     r9, [p_sidx]
        mov     eax, [group_key]
        mov     rdi, [col_key + rax*8]
        mov     rsi, [p_monto]
        mov     eax, [r9 + rbx*4]
        movzx   r15d, byte [rdi + rax]      ; clave de la corrida
.run:   xor     ecx, ecx                    ; count
        xor     r8d, r8d                    ; sum
        mov     ebp, -1                     ; min
        xor     edx, edx                    ; max
.lp:    cmp     rbx, r14
        jae     .flush
        mov     eax, [r9 + rbx*4]
        movzx   eax, byte [rdi + rax]
        cmp     eax, r15d
        jne     .flush
        mov     eax, [r9 + rbx*4]
        mov     eax, [rsi + rax*4]
        inc     ecx
        add     r8, rax
        cmp     eax, ebp
        cmovb   ebp, eax
        cmp     eax, edx
        cmova   edx, eax
        inc     rbx
        jmp     .lp
.flush: add     [r10 + r15*4], ecx
        add     [r11 + r15*8], r8
        cmp     ebp, [r12 + r15*4]
        jae     .f1
        mov     [r12 + r15*4], ebp
.f1:    cmp     edx, [r13 + r15*4]
        jbe     .f2
        mov     [r13 + r15*4], edx
.f2:    cmp     rbx, r14
        jae     .out
        mov     eax, [r9 + rbx*4]
        movzx   r15d, byte [rdi + rax]
        jmp     .run
.out:   pop     rdi
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbp
        pop     rbx
        ret

; run_pipeline: ejecuta el grafo y mide cada etapa
run_pipeline:
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15
        call    now_ns
        mov     r15, rax
        mov     r14, rax

        ; ---------------------------------------------------- FILTER
        lea     rdi, [filter_worker]
        call    parallel
        xor     eax, eax
        xor     ecx, ecx
.pre:   cmp     ecx, [nthreads]
        jae     .pred
        mov     [t_foff + rcx*8], rax
        mov     edx, [t_fc + rcx*4]
        add     rax, rdx
        inc     ecx
        jmp     .pre
.pred:  mov     [n_filter], eax
        lea     rdi, [compact_worker]
        call    parallel
        call    now_ns
        mov     rcx, rax
        sub     rcx, r14
        mov     [comp_ns+8], rcx
        mov     r14, rax

        ; ---------------------------------------------------- SORT
        mov     qword [comp_ns+16], 0
        cmp     byte [rmode], 0
        jne     .rollup
        ; posiciones: para cada clave, los hilos en orden (estable)
        xor     eax, eax                    ; base
        xor     ecx, ecx                    ; clave
.pk:    cmp     ecx, MAXGRP
        jae     .pkd
        xor     edx, edx                    ; hilo
.pt:    cmp     edx, [nthreads]
        jae     .ptd
        mov     r8d, edx
        shl     r8d, 6
        add     r8d, ecx
        mov     [t_pos + r8*4], eax
        add     eax, [t_cnt + r8*4]
        inc     edx
        jmp     .pt
.ptd:   inc     ecx
        jmp     .pk
.pkd:   lea     rdi, [scatter_worker]
        call    parallel
        call    now_ns
        mov     rcx, rax
        sub     rcx, r14
        mov     [comp_ns+16], rcx
        mov     r14, rax

        ; ---------------------------------------------------- ROLLUP
        lea     rdi, [rollup_worker]
        call    parallel
.rollup:
        ; combinar parciales por clave (en orden de clave)
        xor     ebx, ebx                    ; clave
        xor     r13d, r13d                  ; filas
.mk:    cmp     ebx, MAXGRP
        jae     .mkd
        xor     ecx, ecx                    ; count
        xor     r8d, r8d                    ; sum
        mov     r9d, -1                     ; min
        xor     r10d, r10d                  ; max
        xor     edx, edx
.mt:    cmp     edx, [nthreads]
        jae     .mtd
        mov     eax, edx
        shl     eax, 6
        add     eax, ebx
        add     ecx, [t_cnt + rax*4]
        add     r8, [t_sum + rax*8]
        mov     r11d, [t_min + rax*4]
        cmp     r11d, r9d
        cmovb   r9d, r11d
        mov     r11d, [t_max + rax*4]
        cmp     r11d, r10d
        cmova   r10d, r11d
        inc     edx
        jmp     .mt
.mtd:   test    ecx, ecx
        jz      .mn
        mov     [res_key + r13*4], ebx
        mov     [res_count + r13*4], ecx
        mov     [res_sum + r13*8], r8
        mov     [res_min + r13*4], r9d
        mov     [res_max + r13*4], r10d
        mov     rax, r8
        xor     edx, edx
        div     rcx
        mov     [res_avg + r13*4], eax
        inc     r13d
.mn:    inc     ebx
        jmp     .mk
.mkd:   mov     [n_rows], r13d
        call    now_ns
        mov     rcx, rax
        sub     rcx, r14
        mov     [comp_ns+24], rcx
        mov     r14, rax

        ; ---------------------------------------------------- OUTPUT
        call    sort_results
        call    now_ns
        mov     rcx, rax
        sub     rcx, r14
        mov     [comp_ns+32], rcx
        sub     rax, r15
        mov     [pipe_ns], rax
        mov     rax, [load_ns]
        mov     [comp_ns], rax
        mov     eax, [n_rows]
        cmp     [res_scroll], eax
        jb      .ok
        mov     dword [res_scroll], 0
.ok:    pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

; res_val(edi fila, esi columna) -> rax
res_val:
        mov     eax, esi
        jmp     [.t + rax*8]
.t:     dq      .k, .c, .s, .a, .mi, .ma
.k:     mov     eax, [res_key + rdi*4]
        ret
.c:     mov     eax, [res_count + rdi*4]
        ret
.s:     mov     rax, [res_sum + rdi*8]
        ret
.a:     mov     eax, [res_avg + rdi*4]
        ret
.mi:    mov     eax, [res_min + rdi*4]
        ret
.ma:    mov     eax, [res_max + rdi*4]
        ret

; sort_results: insertion sort estable de res_order
sort_results:
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15
        xor     ecx, ecx
.init:  cmp     ecx, MAXGRP
        jae     .go
        mov     [res_order + rcx*4], ecx
        inc     ecx
        jmp     .init
.go:    mov     ebx, 1
.outer: cmp     ebx, [n_rows]
        jae     .done
        mov     r12d, [res_order + rbx*4]
        mov     edi, r12d
        mov     esi, [sort_col]
        call    res_val
        mov     r14, rax
        mov     r13d, ebx
.inner: test    r13d, r13d
        jz      .place
        mov     r15d, [res_order + r13*4 - 4]
        mov     edi, r15d
        mov     esi, [sort_col]
        call    res_val
        cmp     byte [sort_desc], 0
        jne     .desc
        cmp     rax, r14
        jbe     .place
        jmp     .shift
.desc:  cmp     rax, r14
        jae     .place
.shift: mov     [res_order + r13*4], r15d
        dec     r13d
        jmp     .inner
.place: mov     [res_order + r13*4], r12d
        inc     ebx
        jmp     .outer
.done:  pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

; group_name(edi = codigo) -> rax nombre (columna = group_key)
group_name:
        mov     eax, [group_key]
        jmp     col_name

; col_name(eax = columna, edi = codigo) -> rax
col_name:
        shl     eax, 6
        add     eax, edi
        mov     rax, [col_names + rax*8]
        test    rax, rax
        jnz     .r
        lea     rax, [c_dash]
.r:     ret

; sb_time(rdi = ns): "812 µs", "12,3 ms" o "1,2 s"
sb_time:
        cmp     rdi, 1000000
        jb      .us
        mov     rax, 10000000000
        cmp     rdi, rax
        jae     .s
        mov     rax, rdi
        add     rax, 50000
        xor     edx, edx
        mov     ecx, 100000
        div     rcx
        mov     rdi, rax
        call    sb_tenths
        SB_STR  t_ms
        ret
.s:     mov     rax, rdi
        xor     edx, edx
        mov     ecx, 100000000
        div     rcx
        mov     rdi, rax
        call    sb_tenths
        SB_STR  t_s
        ret
.us:    mov     rax, rdi
        add     rax, 500
        xor     edx, edx
        mov     ecx, 1000
        div     rcx
        mov     rdi, rax
        call    sb_num
        SB_STR  t_us
        ret

; -----------------------------------------------------------------------------
; export_csv: escribe resultado.csv y muestra un toast
export_csv:
        push    rbx
        push    r12
        push    r13
        cmp     byte [run_state], 0
        jne     .have
        call    run_pipeline
        mov     byte [run_state], 2
.have:  lea     rbx, [csvbuf]
        mov     eax, [group_key]
        mov     rsi, [grp_colnames + rax*8]
        call    .cat
        lea     rsi, [csv_header]
        call    .cat
        xor     r12d, r12d
.row:   cmp     r12d, [n_rows]
        jae     .write
        mov     r13d, [res_order + r12*4]
        mov     edi, [res_key + r13*4]
        call    group_name
        mov     rsi, rax
        call    .cat
        mov     eax, [res_count + r13*4]
        call    .catnum
        mov     rax, [res_sum + r13*8]
        call    .catnum
        mov     eax, [res_avg + r13*4]
        call    .catnum
        mov     eax, [res_min + r13*4]
        call    .catnum
        mov     eax, [res_max + r13*4]
        call    .catnum
        mov     byte [rbx], 10
        inc     rbx
        inc     r12d
        jmp     .row
.write: mov     eax, SYS_OPEN
        lea     rdi, [csv_file]
        mov     esi, 0x241
        mov     edx, 0644o
        syscall
        test    eax, eax
        js      .fail
        mov     r12d, eax
        mov     eax, SYS_WRITE
        mov     edi, r12d
        lea     rsi, [csvbuf]
        mov     rdx, rbx
        sub     rdx, rsi
        syscall
        mov     r13, rax
        mov     eax, SYS_CLOSE
        mov     edi, r12d
        syscall
        test    r13, r13
        js      .fail
        call    sb_reset
        SB_STR  t_exported
        mov     edi, [n_rows]
        call    sb_num
        SB_STR  t_rows_suffix
        lea     rsi, [sb_buf]
        mov     edi, C_GREEN
        call    show_toast
        jmp     .out
.fail:  lea     rsi, [t_export_fail]
        mov     edi, C_RED
        call    show_toast
.out:   pop     r13
        pop     r12
        pop     rbx
        ret
.cat:   mov     al, [rsi]
        test    al, al
        jz      .catd
        mov     [rbx], al
        inc     rsi
        inc     rbx
        jmp     .cat
.catd:  ret
.catnum:
        mov     rdi, rax
        mov     byte [rbx], ','
        inc     rbx
        mov     rsi, rbx
        xor     edx, edx
        call    fmt_num_sep
        add     rbx, rax
        ret
