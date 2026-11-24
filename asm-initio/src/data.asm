; =============================================================================
;  data.asm -- dataset de ventas y pipeline real:
;  INPUT (generador) -> FILTER (6 operadores, sin saltos) -> SORT (counting
;  sort estable por clave) -> ROLLUP (count/sum/avg/min/max) -> OUTPUT (orden)
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

rand32:                                     ; xorshift32
        mov     eax, [seed]
        mov     edx, eax
        shl     edx, 13
        xor     eax, edx
        mov     edx, eax
        shr     edx, 17
        xor     eax, edx
        mov     edx, eax
        shl     edx, 5
        xor     eax, edx
        mov     [seed], eax
        ret

; gen_data: genera [nrec] ventas con estacionalidad mensual y canal
gen_data:
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15
        call    now_ns
        mov     r15, rax
        mov     eax, [seed]
        mov     [seed0], eax
        xor     ebx, ebx
.lp:    cmp     ebx, [nrec]
        jae     .done
        call    rand32
        mov     r14d, eax
        mov     ecx, eax
        and     ecx, 15
        movzx   r12d, byte [region_weights + rcx]
        mov     [rec_region + rbx], r12b
        mov     ecx, r14d
        shr     ecx, 8
        and     ecx, 0xffff
        imul    ecx, 12
        shr     ecx, 16
        mov     [rec_mes + rbx], cl
        mov     r13d, ecx                   ; mes
        mov     ecx, r14d
        shr     ecx, 24
        and     ecx, 15
        movzx   ecx, byte [canal_weights + rcx]
        mov     [rec_canal + rbx], cl
        push    rcx
        call    rand32
        xor     edx, edx
        div     dword [region_max + r12*4]
        mov     eax, edx
        imul    eax, [month_factor + r13*4]
        xor     edx, edx
        mov     ecx, 100
        div     ecx
        pop     rcx
        cmp     ecx, 2                      ; mayorista: tickets 1,5x
        jne     .nm
        lea     eax, [rax + rax*2]
        shr     eax, 1
.nm:    add     eax, 10
        mov     [rec_monto + rbx*4], eax
        inc     ebx
        jmp     .lp
.done:  call    now_ns
        sub     rax, r15
        mov     [gen_ns], rax
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

; filtro sin saltos: siempre escribe el indice y avanza segun la condicion
%macro FILTER_LOOP 1
        xor     ecx, ecx
        xor     edx, edx
%%lp:   cmp     ecx, r9d
        jae     %%done
        mov     [f_idx + rdx*4], ecx
        xor     eax, eax
        cmp     [rec_monto + rcx*4], r8d
        %1      al
        add     edx, eax
        inc     ecx
        jmp     %%lp
%%done: jmp     .fdone
%endmacro

; run_pipeline: ejecuta todo el grafo y mide cada componente
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
        mov     r8d, [thr]
        mov     r9d, [nrec]
        mov     eax, [filt_op]
        jmp     [.ops + rax*8]
.ops:   dq      .gt, .ge, .lt, .le, .eq, .ne
.gt:    FILTER_LOOP seta
.ge:    FILTER_LOOP setae
.lt:    FILTER_LOOP setb
.le:    FILTER_LOOP setbe
.eq:    FILTER_LOOP sete
.ne:    FILTER_LOOP setne
.fdone: mov     [n_filter], edx
        mov     r12d, edx
        call    now_ns
        mov     rcx, rax
        sub     rcx, r14
        mov     [comp_ns+8], rcx
        mov     r14, rax

        ; ---------------------------------------------------- SORT
        mov     eax, [group_key]
        mov     rbx, [key_base + rax*8]
        xor     eax, eax
        lea     rdi, [cnt]
        mov     ecx, 16
        rep stosd
        xor     ecx, ecx
.c:     cmp     ecx, r12d
        jae     .cdone
        mov     eax, [f_idx + rcx*4]
        movzx   eax, byte [rbx + rax]
        inc     dword [cnt + rax*4]
        inc     ecx
        jmp     .c
.cdone: xor     eax, eax
        xor     ecx, ecx
.pre:   mov     [pos + rcx*4], eax
        add     eax, [cnt + rcx*4]
        inc     ecx
        cmp     ecx, 16
        jb      .pre
        xor     ecx, ecx
.sc:    cmp     ecx, r12d
        jae     .scdone
        mov     edx, [f_idx + rcx*4]
        movzx   eax, byte [rbx + rdx]
        mov     r8d, [pos + rax*4]
        inc     dword [pos + rax*4]
        mov     [s_idx + r8*4], edx
        inc     ecx
        jmp     .sc
.scdone:
        call    now_ns
        mov     rcx, rax
        sub     rcx, r14
        mov     [comp_ns+16], rcx
        mov     r14, rax

        ; ---------------------------------------------------- ROLLUP
        xor     ecx, ecx                    ; i
        xor     r13d, r13d                  ; filas
.grp:   cmp     ecx, r12d
        jae     .rdone
        mov     eax, [s_idx + rcx*4]
        movzx   r11d, byte [rbx + rax]      ; clave del grupo
        xor     edx, edx                    ; count
        xor     r8d, r8d                    ; sum
        mov     r9d, 0xffffffff             ; min
        xor     r10d, r10d                  ; max
.acc:   cmp     ecx, r12d
        jae     .emit
        mov     eax, [s_idx + rcx*4]
        movzx   esi, byte [rbx + rax]
        cmp     esi, r11d
        jne     .emit
        mov     eax, [rec_monto + rax*4]
        add     r8, rax
        cmp     eax, r9d
        cmovb   r9d, eax
        cmp     eax, r10d
        cmova   r10d, eax
        inc     edx
        inc     ecx
        jmp     .acc
.emit:  mov     [res_key + r13*4], r11d
        mov     [res_count + r13*4], edx
        mov     [res_sum + r13*8], r8
        mov     [res_min + r13*4], r9d
        mov     [res_max + r13*4], r10d
        mov     rax, r8
        mov     r8d, edx
        xor     edx, edx
        div     r8
        mov     [res_avg + r13*4], eax
        inc     r13d
        jmp     .grp
.rdone: mov     [n_rows], r13d
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
        mov     rax, [gen_ns]
        mov     [comp_ns], rax

        ; scroll fuera de rango tras el cambio
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

; res_val(edi fila, esi columna) -> rax valor para ordenar
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

; sort_results: insertion sort estable de res_order segun sort_col/sort_desc
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
        mov     r12d, [res_order + rbx*4]   ; elemento a insertar
        mov     edi, r12d
        mov     esi, [sort_col]
        call    res_val
        mov     r14, rax                    ; su valor
        mov     r13d, ebx
.inner: test    r13d, r13d
        jz      .place
        mov     r15d, [res_order + r13*4 - 4]
        mov     edi, r15d
        mov     esi, [sort_col]
        call    res_val
        cmp     byte [sort_desc], 0
        jne     .desc
        cmp     rax, r14                    ; asc: mover si prev > actual
        jbe     .place
        jmp     .shift
.desc:  cmp     rax, r14                    ; desc: mover si prev < actual
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

; group_name(edi clave) -> rax nombre del grupo segun group_key
group_name:
        mov     eax, [group_key]
        mov     rax, [grp_tables + rax*8]
        mov     rax, [rax + rdi*8]
        ret

; -----------------------------------------------------------------------------
; export_csv: escribe resultado.csv (open/write/close) y muestra un toast
export_csv:
        push    rbx
        push    r12
        push    r13
        cmp     byte [run_state], 0
        jne     .have
        call    run_pipeline
        mov     byte [run_state], 2
.have:  lea     rdi, [csvbuf]
        mov     rbx, rdi
        ; encabezado
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
        mov     esi, 0x241                  ; O_WRONLY | O_CREAT | O_TRUNC
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
; .cat: copia z-string rsi en rbx
.cat:   mov     al, [rsi]
        test    al, al
        jz      .catd
        mov     [rbx], al
        inc     rsi
        inc     rbx
        jmp     .cat
.catd:  ret
; .catnum: ',' + numero en rax (sin separador de miles)
.catnum:
        mov     rdi, rax
        mov     byte [rbx], ','
        inc     rbx
        mov     rsi, rbx
        xor     edx, edx
        call    fmt_num_sep
        add     rbx, rax
        ret
