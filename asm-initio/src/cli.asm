; =============================================================================
;  cli.asm -- argumentos, carga de la fuente, benchmark y volcado de datos
;
;  asminitio [--rows N] [--csv ARCHIVO | --pg [CONSULTA]] [--threads N]
;            [--bench [REPS]] [--thr N] [--group region|mes|canal]
;            [--dump-csv ARCHIVO] [--dump-bin DIR]
; =============================================================================
section .text

; print_sb: sb_buf + '\n' a stdout
print_sb:
        mov     edi, 10
        call    sb_ch
        mov     eax, SYS_WRITE
        mov     edi, 1
        lea     rsi, [sb_buf]
        mov     edx, [sb_len]
        syscall
        jmp     sb_reset

; streq(rsi, rdi) -> ZF=1 si iguales
streq:
.l:     mov     al, [rsi]
        cmp     al, [rdi]
        jne     .r
        test    al, al
        jz      .r
        inc     rsi
        inc     rdi
        jmp     .l
.r:     ret

; parse_count(rsi = "10M", "500K", "1G", "12345") -> rax
parse_count:
        xor     eax, eax
.d:     movzx   ecx, byte [rsi]
        sub     ecx, '0'
        cmp     ecx, 9
        ja      .suf
        imul    rax, rax, 10
        add     rax, rcx
        inc     rsi
        jmp     .d
.suf:   movzx   ecx, byte [rsi]
        or      ecx, 0x20
        cmp     ecx, 'k'
        jne     .m
        imul    rax, rax, 1000
        ret
.m:     cmp     ecx, 'm'
        jne     .g
        imul    rax, rax, 1000000
        ret
.g:     cmp     ecx, 'g'
        jne     .r
        imul    rax, rax, 1000000000
.r:     ret

; parse_args(rdi = argv, esi = argc)
%macro OPT 2                                ; nombre, etiqueta
        mov     rsi, rbx
        lea     rdi, [%1]
        call    streq
        je      %2
%endmacro
parse_args:
        push    rbx
        push    r12
        push    r13
        mov     r12, rdi
        mov     r13d, esi
        mov     ecx, 1
.lp:    cmp     ecx, r13d
        jae     .done
        mov     rbx, [r12 + rcx*8]
        push    rcx
        OPT     o_rows, .rows
        OPT     o_csv, .csv
        OPT     o_pg, .pg
        OPT     o_threads, .threads
        OPT     o_bench, .bench
        OPT     o_thr, .thr
        OPT     o_group, .group
        OPT     o_dumpcsv, .dumpcsv
        OPT     o_dumpbin, .dumpbin
        OPT     o_memory, .memory
        OPT     o_help, .help
        OPT     o_help2, .help
        lea     rsi, [e_badopt]
        call    eprint
        mov     rsi, rbx
        call    eprint
        lea     rsi, [s_nl]
        call    die
.next:  pop     rcx
        inc     ecx
        jmp     .lp
; ---- helpers para el argumento siguiente
.arg:   mov     rcx, [rsp+8]                ; indice (pusheado + ret)
        inc     rcx
        cmp     ecx, r13d
        jae     .missing
        mov     [rsp+8], rcx
        mov     rax, [r12 + rcx*8]
        ret
.missing:
        lea     rsi, [e_missing]
        call    die
.rows:  call    .arg
        mov     rsi, rax
        call    parse_count
        mov     rcx, NCAP
        cmp     rax, rcx
        jbe     .r1
        mov     rax, rcx
.r1:    test    eax, eax
        jnz     .r2
        inc     eax
.r2:    mov     [nrec], eax
        mov     dword [nrec_sel], -1
        jmp     .next
.csv:   call    .arg
        mov     [opt_csv], rax
        jmp     .next
.pg:    mov     byte [opt_pg], 1
        mov     rcx, [rsp]
        inc     ecx
        cmp     ecx, r13d
        jae     .next
        mov     rax, [r12 + rcx*8]
        cmp     word [rax], '--'
        je      .next
        mov     [rsp], rcx
        mov     [opt_pgquery], rax
        jmp     .next
.threads:
        call    .arg
        mov     rsi, rax
        call    parse_count
        mov     [opt_threads], eax
        jmp     .next
.bench: mov     dword [opt_bench], 5
        mov     rcx, [rsp]
        inc     ecx
        cmp     ecx, r13d
        jae     .next
        mov     rax, [r12 + rcx*8]
        movzx   edx, byte [rax]
        sub     edx, '0'
        cmp     edx, 9
        ja      .next
        mov     [rsp], rcx
        mov     rsi, rax
        call    parse_count
        mov     [opt_bench], eax
        jmp     .next
.thr:   call    .arg
        mov     rsi, rax
        call    parse_count
        mov     [thr], eax
        jmp     .next
.group: call    .arg
        mov     rbx, rax
        xor     ecx, ecx
.gl:    cmp     ecx, 3
        jae     .next
        push    rcx
        mov     rsi, rbx
        mov     rdi, [grp_colnames + rcx*8]
        call    streq
        pop     rcx
        je      .gset
        inc     ecx
        jmp     .gl
.gset:  mov     [group_key], ecx
        jmp     .next
.dumpcsv:
        call    .arg
        mov     [opt_dumpcsv], rax
        jmp     .next
.dumpbin:
        call    .arg
        mov     [opt_dumpbin], rax
        jmp     .next
.memory:
        mov     byte [rmode], 1
        jmp     .next
.help:  lea     rsi, [t_usage]
        call    eprint
        mov     eax, SYS_EXIT
        xor     edi, edi
        syscall
.done:  pop     r13
        pop     r12
        pop     rbx
        ret

; load_source -> rax = 0 ok o mensaje de error (sin cerrar el programa)
load_source:
        lea     rsi, [c_n0]
        mov     [comp_name], rsi
        mov     rdi, [opt_csv]
        test    rdi, rdi
        jnz     load_csv
        cmp     byte [opt_pg], 0
        je      .gen
        lea     rsi, [c_n0pg]
        mov     [comp_name], rsi
        jmp     pg_load
.gen:
        lea     rsi, [c_n0]
        mov     [comp_name], rsi
        lea     rdi, [src_short]
        lea     rsi, [c_a0]
        mov     edx, 18
        call    copy_z
        call    gen_data
        xor     eax, eax
        ret

; -----------------------------------------------------------------------------
; run_bench: corre el pipeline REPS veces en ambos modos y reporta el mejor
%macro BLINE 2                              ; etiqueta, ns (memoria)
        call    sb_reset
        SB_STR  %1
        mov     rdi, %2
        call    sb_ms3
        call    print_sb
%endmacro

; sb_ms3(rdi = ns) -> "    123,4 ms" (alineado)
sb_ms3:
        push    rbx
        mov     rax, rdi
        add     rax, 50000
        xor     edx, edx
        mov     ecx, 100000
        div     rcx
        mov     rbx, rax
        lea     rsi, [numtmp2]
        mov     rdi, rax
        xor     edx, edx
        call    fmt_num_sep
        mov     ecx, 7
        sub     ecx, eax                    ; relleno
.pad:   test    ecx, ecx
        jle     .np
        push    rcx
        mov     edi, ' '
        call    sb_ch
        pop     rcx
        dec     ecx
        jmp     .pad
.np:    mov     rdi, rbx
        call    sb_tenths
        SB_STR  t_ms
        pop     rbx
        ret

bench_mode:                                 ; ejecuta REPS veces y guarda minimos
        push    rbx
        push    r12
        lea     rdi, [best_ns]
        mov     rax, -1
        mov     ecx, 6
        rep stosq
        xor     ebx, ebx
.rep:   cmp     ebx, [opt_bench]
        jae     .done
        call    run_pipeline
        xor     ecx, ecx
.m:     cmp     ecx, 5
        jae     .tot
        mov     rax, [comp_ns + rcx*8]
        cmp     rax, [best_ns + rcx*8]
        jae     .nm
        mov     [best_ns + rcx*8], rax
.nm:    inc     ecx
        jmp     .m
.tot:   mov     rax, [pipe_ns]
        cmp     rax, [best_ns + 40]
        jae     .nt
        mov     [best_ns + 40], rax
.nt:    inc     ebx
        jmp     .rep
.done:  pop     r12
        pop     rbx
        ret

bench_report:                               ; imprime best_ns
        BLINE   t_b_filter, [best_ns+8]
        cmp     byte [rmode], 0
        jne     .nosort
        BLINE   t_b_sort, [best_ns+16]
.nosort:
        BLINE   t_b_rollup, [best_ns+24]
        BLINE   t_b_output, [best_ns+32]
        call    sb_reset
        SB_STR  t_b_total
        mov     rdi, [best_ns+40]
        call    sb_ms3
        SB_STR  t_b_paren
        mov     eax, [nrec]
        imul    rax, rax, 1000
        xor     edx, edx
        mov     rcx, [best_ns+40]
        test    rcx, rcx
        jz      .z
        div     rcx
.z:     mov     rdi, rax
        call    sb_num
        SB_STR  t_mregs
        mov     edi, ')'
        call    sb_ch
        call    print_sb
        ret

run_bench:
        push    rbx
        push    r12
        call    sb_reset
        SB_STR  t_b_head
        call    print_sb
        SB_STR  t_b_src
        movzx   eax, byte [src_mode]
        mov     rsi, [src_names + rax*8]
        call    sb_str
        cmp     byte [src_mode], 0
        je      .s1
        SB_STR  t_b_sep
        SB_STR  src_short
.s1:    call    print_sb
        SB_STR  t_b_rows
        mov     edi, [nrec]
        call    sb_num
        SB_STR  t_b_threads
        mov     edi, [nthreads]
        call    sb_num
        SB_STR  t_b_reps
        mov     edi, [opt_bench]
        call    sb_num
        call    print_sb
        SB_STR  t_b_query
        mov     eax, [filt_op]
        mov     rsi, [op_names + rax*8]
        call    sb_str
        mov     edi, ' '
        call    sb_ch
        mov     edi, [thr]
        call    sb_dec
        SB_STR  t_b_groupby
        mov     eax, [group_key]
        mov     rsi, [grp_colnames + rax*8]
        call    sb_str
        call    print_sb
        ; carga
        SB_STR  t_b_load
        mov     rdi, [load_ns]
        call    sb_ms3
        mov     rcx, [load_bytes]
        test    rcx, rcx
        jz      .nl
        SB_STR  t_b_paren
        mov     rax, [load_bytes]
        xor     edx, edx
        mov     ecx, 1000000
        div     rcx
        mov     rdi, rax
        call    sb_num
        SB_STR  t_b_mb
        mov     rax, [load_bytes]
        imul    rax, rax, 1000
        xor     edx, edx
        mov     rcx, [load_ns]
        div     rcx
        mov     rdi, rax
        call    sb_num
        SB_STR  t_b_mbs
.nl:    call    print_sb
        call    print_sb

        ; modo ordenado (fiel al grafo)
        mov     byte [rmode], 0
        SB_STR  t_b_mode0
        call    print_sb
        call    bench_mode
        call    bench_report
        call    print_sb
        ; modo en memoria
        mov     byte [rmode], 1
        SB_STR  t_b_mode1
        call    print_sb
        call    bench_mode
        call    bench_report
        call    print_sb

        ; resultado (para validar contra otras herramientas)
        SB_STR  t_b_result
        call    print_sb
        xor     r12d, r12d
.row:   cmp     r12d, [n_rows]
        jae     .done
        mov     ebx, [res_order + r12*4]
        SB_STR  t_b_indent
        mov     edi, [res_key + rbx*4]
        call    group_name
        mov     rsi, rax
        call    sb_str
        mov     edi, 9
        call    sb_ch
        mov     edi, [res_count + rbx*4]
        call    sb_dec
        mov     edi, 9
        call    sb_ch
        mov     rdi, [res_sum + rbx*8]
        call    sb_dec
        mov     edi, 9
        call    sb_ch
        mov     edi, [res_min + rbx*4]
        call    sb_dec
        mov     edi, 9
        call    sb_ch
        mov     edi, [res_max + rbx*4]
        call    sb_dec
        call    print_sb
        inc     r12d
        jmp     .row
.done:  pop     r12
        pop     rbx
        ret

; -----------------------------------------------------------------------------
; write_file(rdi = ruta, rsi = datos, rdx = largo) -> eax 0 / -1
write_file:
        push    rbx
        push    r12
        push    r13
        mov     r12, rsi
        mov     r13, rdx
        mov     eax, SYS_OPEN
        mov     esi, 0x241
        mov     edx, 0644o
        syscall
        test    eax, eax
        js      .err
        mov     ebx, eax
.lp:    test    r13, r13
        jz      .ok
        mov     rdx, r13
        mov     eax, 1 << 30
        cmp     rdx, rax
        cmova   rdx, rax
        mov     eax, SYS_WRITE
        mov     edi, ebx
        mov     rsi, r12
        syscall
        test    rax, rax
        jle     .werr
        add     r12, rax
        sub     r13, rax
        jmp     .lp
.ok:    mov     eax, SYS_CLOSE
        mov     edi, ebx
        syscall
        xor     eax, eax
        jmp     .out
.werr:  mov     eax, SYS_CLOSE
        mov     edi, ebx
        syscall
.err:   mov     eax, -1
.out:   pop     r13
        pop     r12
        pop     rbx
        ret

; dump_bin(rdi = directorio): region.u8 mes.u8 canal.u8 monto.u32
dump_bin:
        push    rbx
        push    r12
        mov     r12, rdi
        xor     ebx, ebx
.lp:    cmp     ebx, 4
        jae     .done
        call    sb_reset
        mov     rsi, r12
        call    sb_str
        mov     edi, '/'
        call    sb_ch
        mov     rsi, [dump_names + rbx*8]
        call    sb_str
        lea     rdi, [sb_buf]
        mov     eax, [nrec]
        mov     rdx, rax
        cmp     ebx, 3
        jne     .k
        shl     rdx, 2
        mov     rsi, [p_monto]
        jmp     .w
.k:     mov     rsi, [col_key + rbx*8]
.w:     call    write_file
        test    eax, eax
        js      .err
        inc     ebx
        jmp     .lp
.done:  xor     eax, eax
        pop     r12
        pop     rbx
        ret
.err:   lea     rsi, [e_dump]
        call    die

; dump_csv(rdi = ruta): region,mes,canal,monto con nombres
dump_csv:
        push    rbx
        push    r12
        push    r13
        push    r14
        mov     rax, rdi
        mov     eax, SYS_OPEN
        mov     esi, 0x241
        mov     edx, 0644o
        syscall
        test    eax, eax
        js      .err
        mov     r12d, eax
        mov     rsi, (8 << 20) + 4096
        call    mmap_reserve
        mov     r13, rax                    ; buffer
        mov     r14, rax                    ; cursor
        lea     rsi, [s_dump_header]
.h:     lodsb
        test    al, al
        jz      .hd
        mov     [r14], al
        inc     r14
        jmp     .h
.hd:    xor     ebx, ebx
.row:   cmp     ebx, [nrec]
        jae     .flush_end
        xor     ecx, ecx
.col:   push    rcx
        mov     rax, [col_key + rcx*8]
        movzx   edi, byte [rax + rbx]
        mov     eax, ecx
        call    col_name
        mov     rsi, rax
.cs:    lodsb
        test    al, al
        jz      .csd
        mov     [r14], al
        inc     r14
        jmp     .cs
.csd:   mov     byte [r14], ','
        inc     r14
        pop     rcx
        inc     ecx
        cmp     ecx, 3
        jb      .col
        mov     rax, [p_monto]
        mov     edi, [rax + rbx*4]
        mov     rsi, r14
        xor     edx, edx
        call    fmt_num_sep
        add     r14, rax
        mov     byte [r14], 10
        inc     r14
        inc     ebx
        mov     rax, r14
        sub     rax, r13
        cmp     rax, 8 << 20
        jb      .row
        call    .flush
        jmp     .row
.flush_end:
        call    .flush
        mov     eax, SYS_CLOSE
        mov     edi, r12d
        syscall
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret
.flush: mov     rsi, r13
        mov     rdx, r14
        sub     rdx, r13
.fl:    test    rdx, rdx
        jz      .fd
        push    rsi
        push    rdx
        mov     eax, SYS_WRITE
        mov     edi, r12d
        syscall
        pop     rdx
        pop     rsi
        test    rax, rax
        jle     .err
        add     rsi, rax
        sub     rdx, rax
        jmp     .fl
.fd:    mov     r14, r13
        ret
.err:   lea     rsi, [e_dump]
        call    die
