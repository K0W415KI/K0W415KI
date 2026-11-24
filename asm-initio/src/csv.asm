; =============================================================================
;  csv.asm -- lector de CSV paralelo (archivo mapeado o buffer de PostgreSQL)
;
;  1. encabezado: delimitador ( , ; TAB ) y columnas por nombre:
;       region|región|zona  mes|month|periodo  canal|channel  monto|amount|importe|total
;  2. se parte el buffer en un chunk por hilo (en limites de linea)
;  3. pasada 1 (SSE2): cuenta lineas por chunk -> fila inicial de cada chunk
;  4. pasada 2: parsea y codifica categorias con un diccionario por hilo
;  5. se fusionan los diccionarios (orden alfabetico) y pasada 3 remapea
; =============================================================================
section .text

%define MAXCOLS 64
%define NAMELEN 14

; parse_csv_buffer(rsi = inicio, rdx = largo) -> rax = 0 ok, o mensaje de error
parse_csv_buffer:
        push    rbx
        push    rbp
        push    r12
        push    r13
        push    r14
        push    r15
        mov     rbp, rsi
        lea     r15, [rsi + rdx]            ; fin
        ; BOM UTF-8
        cmp     rdx, 3
        jb      .nobom
        cmp     word [rbp], 0xBBEF
        jne     .nobom
        cmp     byte [rbp+2], 0xBF
        jne     .nobom
        add     rbp, 3
.nobom: cmp     rbp, r15
        jae     .empty
        ; fin del encabezado
        mov     rbx, rbp
.hl:    cmp     rbx, r15
        jae     .hend
        cmp     byte [rbx], 10
        je      .hend
        inc     rbx
        jmp     .hl
.hend:  ; delimitador: el mas frecuente entre , ; TAB
        xor     ecx, ecx                    ; comas
        xor     edx, edx                    ; punto y coma
        xor     r8d, r8d                    ; tabs
        mov     rsi, rbp
.dl:    cmp     rsi, rbx
        jae     .dd
        mov     al, [rsi]
        cmp     al, ','
        jne     .d1
        inc     ecx
.d1:    cmp     al, ';'
        jne     .d2
        inc     edx
.d2:    cmp     al, 9
        jne     .d3
        inc     r8d
.d3:    inc     rsi
        jmp     .dl
.dd:    mov     byte [csv_delim], ','
        mov     eax, ecx
        cmp     edx, eax
        jbe     .d4
        mov     byte [csv_delim], ';'
        mov     eax, edx
.d4:    cmp     r8d, eax
        jbe     .d5
        mov     byte [csv_delim], 9
.d5:    ; roles de columna
        lea     rdi, [csv_role]
        mov     al, 0xFF
        mov     ecx, MAXCOLS
        rep stosb
        mov     dword [col_present], 0
        xor     r12d, r12d                  ; indice de columna
        mov     rsi, rbp
.hf:    cmp     rsi, rbx
        ja      .hdone
        ; normalizar campo en hdrbuf (minusculas, sin comillas/espacios/\r)
        xor     ecx, ecx
.hc:    cmp     rsi, rbx
        jae     .hce
        mov     al, [rsi]
        cmp     al, [csv_delim]
        je      .hce
        inc     rsi
        cmp     al, '"'
        je      .hc
        cmp     al, ' '
        je      .hc
        cmp     al, 13
        je      .hc
        cmp     al, 'A'
        jb      .hs
        cmp     al, 'Z'
        ja      .hs
        or      al, 0x20
.hs:    cmp     ecx, 30
        jae     .hc
        mov     [hdrbuf + rcx], al
        inc     ecx
        jmp     .hc
.hce:   mov     byte [hdrbuf + rcx], 0
        inc     rsi                         ; salta el delimitador (o el \n)
        ; buscar alias
        lea     r13, [csv_aliases]
.al:    movzx   r14d, byte [r13]            ; rol (0xFF = fin)
        cmp     r14d, 0xFF
        je      .anext
        lea     rdi, [r13+1]
        lea     r8, [hdrbuf]
.ac:    mov     al, [rdi]
        cmp     al, [r8]
        jne     .askip
        test    al, al
        jz      .amatch
        inc     rdi
        inc     r8
        jmp     .ac
.askip: ; avanzar al proximo alias
        lea     rdi, [r13+1]
.as:    cmp     byte [rdi], 0
        je      .as2
        inc     rdi
        jmp     .as
.as2:   lea     r13, [rdi+1]
        jmp     .al
.amatch:
        cmp     byte [col_present + r14], 0 ; primera aparicion del rol
        jne     .anext
        cmp     r12d, MAXCOLS
        jae     .anext
        mov     byte [col_present + r14], 1
        mov     [csv_role + r12], r14b
.anext: inc     r12d
        cmp     rsi, rbx
        jbe     .hf
.hdone: cmp     byte [col_present + 3], 0
        je      .nomonto
        lea     rax, [rbx+1]                ; primer byte de datos
        cmp     rax, r15
        jbe     .hd2
        mov     rax, r15
.hd2:   mov     [csv_data], rax
        mov     [csv_end], r15

        ; ---- chunks en limites de linea
        mov     r12, r15
        sub     r12, rax                    ; largo de datos
        mov     [chunk_beg], rax
        mov     r13d, 1
.ch:    cmp     r13d, [nthreads]
        jae     .chd
        mov     rax, r12
        imul    rax, r13
        xor     edx, edx
        mov     ecx, [nthreads]
        div     rcx
        add     rax, [csv_data]
        mov     rcx, [chunk_beg + r13*8 - 8]
        cmp     rax, rcx
        cmovb   rax, rcx
.adv:   cmp     rax, r15
        jae     .setb
        cmp     byte [rax], 10
        je      .nl
        inc     rax
        jmp     .adv
.nl:    inc     rax
.setb:  mov     [chunk_beg + r13*8], rax
        mov     [chunk_end + r13*8 - 8], rax
        inc     r13d
        jmp     .ch
.chd:   mov     eax, [nthreads]
        mov     [chunk_end + rax*8 - 8], r15

        ; ---- pasada 1: lineas por chunk
        lea     rdi, [count_worker]
        call    parallel
        xor     eax, eax
        xor     ecx, ecx
.pr:    cmp     ecx, [nthreads]
        jae     .prd
        mov     [chunk_row0 + rcx*8], rax
        add     rax, [chunk_rows + rcx*8]
        inc     ecx
        jmp     .pr
.prd:   cmp     rax, NCAP
        ja      .toobig

        ; ---- pasada 2: parseo
        lea     rdi, [parse_worker]
        call    parallel
        call    csv_merge
        lea     rdi, [remap_worker]
        call    parallel

        ; ---- compactar si hubo lineas vacias
        xor     r12d, r12d                  ; destino
        xor     r13d, r13d                  ; chunk
.cp:    cmp     r13d, [nthreads]
        jae     .cpd
        mov     rsi, [chunk_row0 + r13*8]
        mov     r14, [chunk_act + r13*8]
        cmp     rsi, r12
        je      .cpn
        xor     ebx, ebx
.cpc:   cmp     ebx, 3
        jae     .cpm
        mov     rax, [col_key + rbx*8]
        lea     rdi, [rax + r12]
        lea     rsi, [rax]
        add     rsi, [chunk_row0 + r13*8]
        mov     rcx, r14
        rep movsb
        inc     ebx
        jmp     .cpc
.cpm:   mov     rax, [p_monto]
        lea     rdi, [rax + r12*4]
        mov     rsi, [chunk_row0 + r13*8]
        lea     rsi, [rax + rsi*4]
        lea     rcx, [r14*4]
        rep movsb
.cpn:   add     r12, r14
        inc     r13d
        jmp     .cp
.cpd:   mov     [nrec], r12d
        xor     eax, eax
        jmp     .out
.empty: lea     rax, [e_csv_empty]
        jmp     .out
.nomonto:
        lea     rax, [e_csv_nomonto]
        jmp     .out
.toobig:
        lea     rax, [e_csv_big]
.out:   pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbp
        pop     rbx
        ret

; count_worker: cuenta '\n' en el chunk con SSE2 (16 bytes por vuelta)
count_worker:
        mov     eax, edi
        mov     rsi, [chunk_beg + rax*8]
        mov     rdx, [chunk_end + rax*8]
        mov     r9, rdx
        mov     ecx, 0x0A0A0A0A
        movd    xmm1, ecx
        pshufd  xmm1, xmm1, 0
        xor     r8d, r8d
.v:     lea     rcx, [rsi+16]
        cmp     rcx, rdx
        ja      .t
        movdqu  xmm0, [rsi]
        pcmpeqb xmm0, xmm1
        pmovmskb ecx, xmm0
        popcnt  ecx, ecx
        add     r8, rcx
        add     rsi, 16
        jmp     .v
.t:     cmp     rsi, rdx
        jae     .end
        cmp     byte [rsi], 10
        jne     .tn
        inc     r8
.tn:    inc     rsi
        jmp     .t
.end:   mov     rcx, [chunk_beg + rax*8]
        cmp     r9, rcx
        jbe     .st
        cmp     byte [r9-1], 10
        je      .st
        inc     r8                          ; ultima linea sin \n
.st:    mov     [chunk_rows + rax*8], r8
        ret

; dict_lookup(edi = hilo*3+col, rsi = texto, edx = largo) -> eax codigo local
dict_lookup:
        push    rbx
        push    r12
        mov     eax, 2166136261             ; FNV-1a
        xor     ecx, ecx
.h:     cmp     ecx, edx
        jae     .hd
        movzx   r8d, byte [rsi + rcx]
        xor     eax, r8d
        imul    eax, 16777619
        inc     ecx
        jmp     .h
.hd:    and     eax, 127
        mov     r9d, edi
        shl     r9d, 7
        lea     r9, [d_slot + r9]
        mov     r10d, edi
        shl     r10d, 9
        lea     r10, [d_ptr + r10]
        mov     r11d, edi
        shl     r11d, 8
        lea     r11, [d_len + r11]
.probe: movzx   ecx, byte [r9 + rax]
        test    ecx, ecx
        jz      .insert
        dec     ecx
        cmp     edx, [r11 + rcx*4]
        jne     .next
        mov     r12, [r10 + rcx*8]
        xor     ebx, ebx
.cmp:   cmp     ebx, edx
        jae     .found
        mov     r8b, [rsi + rbx]
        cmp     r8b, [r12 + rbx]
        jne     .next
        inc     ebx
        jmp     .cmp
.found: mov     eax, ecx
        jmp     .out
.next:  inc     eax
        and     eax, 127
        jmp     .probe
.insert:
        mov     ecx, [d_cnt + rdi*4]
        cmp     ecx, MAXGRP - 1
        jae     .full
        mov     [r10 + rcx*8], rsi
        mov     [r11 + rcx*4], edx
        lea     r8d, [rcx+1]
        mov     [r9 + rax], r8b
        inc     dword [d_cnt + rdi*4]
        mov     eax, ecx
        jmp     .out
.full:  mov     eax, MAXGRP - 1             ; "(otros)"
.out:   pop     r12
        pop     rbx
        ret

; parse_uint(rsi = texto, edx = largo) -> eax (parte entera, saturada)
parse_uint:
        xor     eax, eax
        xor     ecx, ecx
.sk:    cmp     ecx, edx
        jae     .r
        movzx   r8d, byte [rsi + rcx]
        cmp     r8d, ' '
        je      .s1
        cmp     r8d, '$'
        je      .s1
        cmp     r8d, '-'
        je      .neg
        jmp     .dg
.s1:    inc     ecx
        jmp     .sk
.dg:    cmp     ecx, edx
        jae     .r
        movzx   r8d, byte [rsi + rcx]
        sub     r8d, '0'
        cmp     r8d, 9
        ja      .r
        imul    rax, rax, 10
        add     rax, r8
        inc     ecx
        mov     r9d, 0xFFFFFFFF
        cmp     rax, r9
        jbe     .dg
        mov     eax, 0xFFFFFFFF
.r:     ret
.neg:   xor     eax, eax
        ret

; parse_worker: pasada 2 sobre el chunk del hilo
%define PW_K    rsp                         ; 4 bytes: claves de la fila
%define PW_M    rsp+4                       ; monto
%define PW_COL  rsp+8
%define PW_TID  rsp+12
parse_worker:
        push    rbx
        push    rbp
        push    r12
        push    r13
        push    r14
        push    r15
        sub     rsp, 24
        mov     [PW_TID], edi
        mov     r13d, edi
        ; limpiar diccionarios del hilo
        imul    eax, edi, 3
        mov     ecx, eax
        mov     dword [d_cnt + rcx*4], 0
        mov     dword [d_cnt + rcx*4 + 4], 0
        mov     dword [d_cnt + rcx*4 + 8], 0
        shl     eax, 7
        lea     rdi, [d_slot + rax]
        xor     eax, eax
        mov     ecx, 3*128/8
        rep stosq
        mov     rbp, [chunk_beg + r13*8]
        mov     r15, [chunk_end + r13*8]
        mov     rbx, [chunk_row0 + r13*8]
        movzx   r14d, byte [csv_delim]
.line:  cmp     rbp, r15
        jae     .done
        movzx   eax, byte [rbp]
        cmp     eax, 10
        je      .blank
        cmp     eax, 13
        jne     .row
        lea     rcx, [rbp+1]
        cmp     rcx, r15
        jae     .blank
        cmp     byte [rcx], 10
        jne     .row
        inc     rbp
.blank: inc     rbp
        jmp     .line
.row:   mov     dword [PW_K], 0
        mov     dword [PW_M], 0
        mov     dword [PW_COL], 0
.field: mov     r12, rbp                    ; inicio del campo
        cmp     rbp, r15
        jae     .fend
        cmp     byte [rbp], '"'
        jne     .plain
        inc     rbp
        mov     r12, rbp
.q:     cmp     rbp, r15
        jae     .qe
        cmp     byte [rbp], '"'
        je      .qe
        inc     rbp
        jmp     .q
.qe:    mov     rdx, rbp
        sub     rdx, r12                    ; largo
        push    rdx
        cmp     rbp, r15
        jae     .qs
        inc     rbp                         ; comilla de cierre
.qs:    cmp     rbp, r15                    ; hasta el delimitador o fin de linea
        jae     .qd
        movzx   eax, byte [rbp]
        cmp     eax, r14d
        je      .qd
        cmp     eax, 10
        je      .qd
        inc     rbp
        jmp     .qs
.qd:    pop     rdx
        jmp     .store
.plain: cmp     rbp, r15
        jae     .pe
        movzx   eax, byte [rbp]
        cmp     eax, r14d
        je      .pe
        cmp     eax, 10
        je      .pe
        inc     rbp
        jmp     .plain
.pe:    mov     rdx, rbp
        sub     rdx, r12
        test    rdx, rdx
        jz      .store
        cmp     byte [rbp-1], 13
        jne     .store
        dec     rdx
.store: mov     ecx, [PW_COL]
        cmp     ecx, MAXCOLS
        jae     .sep
        movzx   eax, byte [csv_role + rcx]
        cmp     eax, 3
        je      .monto
        ja      .sep
        ; categoria
        push    rax
        imul    edi, r13d, 3
        add     edi, eax
        mov     rsi, r12
        call    dict_lookup
        pop     rcx
        mov     [PW_K + rcx], al
        jmp     .sep
.monto: mov     rsi, r12
        call    parse_uint
        mov     [PW_M], eax
.sep:   inc     dword [PW_COL]
.fend:  cmp     rbp, r15
        jae     .emit
        movzx   eax, byte [rbp]
        cmp     eax, r14d
        jne     .eol
        inc     rbp
        jmp     .field
.eol:   inc     rbp                         ; '\n'
.emit:  mov     rax, [col_key]
        mov     cl, [PW_K]
        mov     [rax + rbx], cl
        mov     rax, [col_key+8]
        mov     cl, [PW_K+1]
        mov     [rax + rbx], cl
        mov     rax, [col_key+16]
        mov     cl, [PW_K+2]
        mov     [rax + rbx], cl
        mov     rax, [p_monto]
        mov     ecx, [PW_M]
        mov     [rax + rbx*4], ecx
        inc     rbx
        jmp     .line
.done:  sub     rbx, [chunk_row0 + r13*8]
        mov     [chunk_act + r13*8], rbx
        add     rsp, 24
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbp
        pop     rbx
        ret

; remap_worker: codigos locales -> globales
remap_worker:
        push    rbx
        mov     r8d, edi
        mov     rsi, [chunk_row0 + r8*8]
        mov     rdx, [chunk_act + r8*8]
        add     rdx, rsi
        xor     ebx, ebx
.c:     cmp     ebx, 3
        jae     .done
        cmp     byte [col_present + rbx], 0
        je      .nc
        imul    eax, r8d, 3
        add     eax, ebx
        shl     eax, 6
        lea     r9, [remap + rax]
        mov     r10, [col_key + rbx*8]
        mov     rcx, rsi
.r:     cmp     rcx, rdx
        jae     .nc
        movzx   eax, byte [r10 + rcx]
        mov     al, [r9 + rax]
        mov     [r10 + rcx], al
        inc     rcx
        jmp     .r
.nc:    inc     ebx
        jmp     .c
.done:  pop     rbx
        ret

; str_less(rsi a, ecx la, rdi b, edx lb) -> CF=1 si a < b
str_less:
        xor     r8d, r8d
.lp:    cmp     r8d, ecx
        jae     .aend
        cmp     r8d, edx
        jae     .ge
        mov     al, [rsi + r8]
        cmp     al, [rdi + r8]
        jb      .lt
        ja      .ge
        inc     r8d
        jmp     .lp
.aend:  cmp     ecx, edx
        jb      .lt
.ge:    clc
        ret
.lt:    stc
        ret

; month_index(rsi = texto, ecx = largo) -> eax 0..11, o 12 si no es un mes
month_index:
        xor     eax, eax
        cmp     ecx, 3
        jne     .no
.lp:    mov     rdx, [month_name + rax*8]
        mov     r8b, [rsi]
        and     r8b, 0xDF                   ; mayusculas
        cmp     r8b, [rdx]
        jne     .nx
        mov     r8b, [rsi+1]
        and     r8b, 0xDF
        cmp     r8b, [rdx+1]
        jne     .nx
        mov     r8b, [rsi+2]
        and     r8b, 0xDF
        cmp     r8b, [rdx+2]
        je      .r
.nx:    inc     eax
        cmp     eax, 12
        jb      .lp
.no:    mov     eax, 12
.r:     ret

; csv_merge: diccionario global por columna, ordenado alfabeticamente
csv_merge:
        push    rbx
        push    rbp
        push    r12
        push    r13
        push    r14
        push    r15
        lea     rax, [name_pool]
        mov     [pool_ptr], rax
        xor     r12d, r12d                  ; columna
.col:   cmp     r12d, 3
        jae     .done
        cmp     byte [col_present + r12], 0
        jne     .have
        ; columna ausente: un solo grupo "-"
        mov     eax, r12d
        shl     eax, 6
        lea     rcx, [c_dash]
        mov     [col_names + rax*8], rcx
        mov     dword [col_ngrp + r12*4], 1
        xor     ecx, ecx                    ; remap en cero
.zr:    cmp     ecx, [nthreads]
        jae     .nextc
        imul    eax, ecx, 3
        add     eax, r12d
        shl     eax, 6
        lea     rdi, [remap + rax]
        push    rcx
        xor     eax, eax
        mov     ecx, 8
        rep stosq
        pop     rcx
        inc     ecx
        jmp     .zr
.have:  xor     ebx, ebx                    ; globales
        mov     byte [g_over], 0
        xor     r13d, r13d                  ; hilo
.th:    cmp     r13d, [nthreads]
        jae     .sort
        imul    ebp, r13d, 3
        add     ebp, r12d                   ; indice de diccionario
        ; codigo 63 local (desborde) -> desborde global
        mov     eax, ebp
        shl     eax, 6
        mov     byte [remap + rax + 63], 63
        xor     r14d, r14d                  ; codigo local
.lc:    cmp     r14d, [d_cnt + rbp*4]
        jae     .nth
        mov     eax, ebp
        shl     eax, 6
        add     eax, r14d
        mov     rsi, [d_ptr + rax*8]
        mov     ecx, [d_len + rax*4]
        ; buscar en la lista global
        xor     r15d, r15d
.gs:    cmp     r15d, ebx
        jae     .gnew
        cmp     ecx, [g_len + r15*4]
        jne     .gn
        mov     rdi, [g_ptr + r15*8]
        xor     edx, edx
.gc:    cmp     edx, ecx
        jae     .gfound
        mov     al, [rsi + rdx]
        cmp     al, [rdi + rdx]
        jne     .gn
        inc     edx
        jmp     .gc
.gn:    inc     r15d
        jmp     .gs
.gnew:  cmp     ebx, MAXGRP - 1
        jae     .gover
        mov     [g_ptr + rbx*8], rsi
        mov     [g_len + rbx*4], ecx
        mov     r15d, ebx
        inc     ebx
        jmp     .gfound
.gover: mov     byte [g_over], 1
        mov     r15d, 63
.gfound:
        mov     eax, ebp
        shl     eax, 6
        add     eax, r14d
        mov     [remap + rax], r15b
        inc     r14d
        jmp     .lc
.nth:   cmp     dword [d_cnt + rbp*4], MAXGRP - 1
        jb      .nth2
        mov     byte [g_over], 1
.nth2:  inc     r13d
        jmp     .th
        ; ¿son todos meses (ENE..DIC)? -> orden cronologico
.sort:  mov     byte [g_months], 0
        cmp     ebx, 2
        jb      .msk
        xor     r13d, r13d
.mo:    cmp     r13d, ebx
        jae     .mall
        mov     rsi, [g_ptr + r13*8]
        mov     ecx, [g_len + r13*4]
        call    month_index
        cmp     eax, 12
        jae     .msk
        mov     [g_midx + r13], al
        inc     r13d
        jmp     .mo
.mall:  mov     byte [g_months], 1
.msk:   xor     ecx, ecx
.oi:    cmp     ecx, ebx
        jae     .os
        mov     [g_ord + rcx*4], ecx
        inc     ecx
        jmp     .oi
.os:    mov     r13d, 1
.oo:    cmp     r13d, ebx
        jae     .rank
        mov     r14d, [g_ord + r13*4]
        mov     r15d, r13d
.oin:   test    r15d, r15d
        jz      .opl
        mov     ebp, [g_ord + r15*4 - 4]
        mov     rsi, [g_ptr + r14*8]
        mov     ecx, [g_len + r14*4]
        mov     rdi, [g_ptr + rbp*8]
        mov     edx, [g_len + rbp*4]
        cmp     byte [g_months], 0
        je      .alpha
        movzx   eax, byte [g_midx + r14]    ; meses: orden cronologico
        cmp     al, [g_midx + rbp]
        jae     .opl
        jmp     .osh
.alpha: call    str_less                    ; actual < anterior ?
        jnc     .opl
.osh:
        mov     [g_ord + r15*4], ebp
        dec     r15d
        jmp     .oin
.opl:   mov     [g_ord + r15*4], r14d
        inc     r13d
        jmp     .oo
.rank:  xor     ecx, ecx
.rk:    cmp     ecx, ebx
        jae     .rko
        mov     eax, [g_ord + rcx*4]
        mov     [g_rank + rax], cl
        inc     ecx
        jmp     .rk
.rko:   mov     byte [g_rank + 63], bl      ; desborde va al final
        ; aplicar rank al remap de cada hilo
        xor     r13d, r13d
.ap:    cmp     r13d, [nthreads]
        jae     .names
        imul    eax, r13d, 3
        add     eax, r12d
        shl     eax, 6
        lea     rdi, [remap + rax]
        xor     ecx, ecx
.apc:   cmp     ecx, MAXGRP
        jae     .apn
        movzx   eax, byte [rdi + rcx]
        mov     al, [g_rank + rax]
        mov     [rdi + rcx], al
        inc     ecx
        jmp     .apc
.apn:   inc     r13d
        jmp     .ap
        ; nombres (copiados al pool, truncados sin cortar UTF-8)
.names: xor     r13d, r13d
.nm:    cmp     r13d, ebx
        jae     .over
        mov     eax, [g_ord + r13*4]
        mov     rsi, [g_ptr + rax*8]
        mov     ecx, [g_len + rax*4]
        mov     rdi, [pool_ptr]
        mov     eax, r12d
        shl     eax, 6
        add     eax, r13d
        mov     [col_names + rax*8], rdi
        test    ecx, ecx
        jnz     .nz
        lea     rax, [t_empty_val]
        mov     edx, r12d
        shl     edx, 6
        add     edx, r13d
        mov     [col_names + rdx*8], rax
        jmp     .nn
.nz:    cmp     ecx, NAMELEN
        jbe     .cpy
        mov     ecx, NAMELEN
.bk:    mov     al, [rsi + rcx]
        and     al, 0xC0
        cmp     al, 0x80
        jne     .cpy
        dec     ecx
        jnz     .bk
.cpy:   rep movsb
        mov     byte [rdi], 0
        add     qword [pool_ptr], 16
.nn:    inc     r13d
        jmp     .nm
.over:  mov     eax, ebx
        cmp     byte [g_over], 0
        je      .setn
        mov     ecx, r12d
        shl     ecx, 6
        add     ecx, ebx
        lea     rdx, [t_others]
        mov     [col_names + rcx*8], rdx
        inc     eax
.setn:  mov     [col_ngrp + r12*4], eax
.nextc: inc     r12d
        jmp     .col
.done:  pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbp
        pop     rbx
        ret

; -----------------------------------------------------------------------------
; load_csv(rdi = ruta) -> rax = 0 ok o mensaje de error
load_csv:
        push    rbx
        push    r12
        push    r13
        push    r14
        mov     r12, rdi
        call    now_ns
        mov     r14, rax
        mov     eax, SYS_OPEN
        mov     rdi, r12
        xor     esi, esi
        xor     edx, edx
        syscall
        test    eax, eax
        js      .eopen
        mov     ebx, eax
        mov     eax, 5                      ; fstat
        mov     edi, ebx
        lea     rsi, [statbuf]
        syscall
        mov     r13, [statbuf + 48]         ; st_size
        test    r13, r13
        jz      .eempty
        mov     eax, SYS_MMAP
        xor     edi, edi
        mov     rsi, r13
        mov     edx, 1                      ; PROT_READ
        mov     r10d, 2                     ; MAP_PRIVATE
        mov     r8d, ebx
        xor     r9d, r9d
        syscall
        cmp     rax, -4096
        ja      .eopen
        push    rax
        mov     eax, SYS_CLOSE
        mov     edi, ebx
        syscall
        mov     rsi, [rsp]
        mov     rdx, r13
        call    parse_csv_buffer
        mov     rbx, rax
        pop     rdi
        mov     eax, 11                     ; munmap
        mov     rsi, r13
        syscall
        test    rbx, rbx
        jnz     .ret
        call    now_ns
        sub     rax, r14
        mov     [load_ns], rax
        mov     [load_bytes], r13
        mov     byte [src_mode], 1
        ; etiqueta: nombre de archivo sin directorio
        mov     rsi, r12
        mov     rdx, r12
.bn:    mov     al, [rsi]
        test    al, al
        jz      .bnd
        inc     rsi
        cmp     al, '/'
        jne     .bn
        mov     rdx, rsi
        jmp     .bn
.bnd:   mov     rsi, rdx
        lea     rdi, [src_short]
        mov     edx, 18
        call    copy_z
        mov     rsi, r12
        lea     rdi, [src_path]
        mov     edx, 200
        call    copy_z
        xor     eax, eax
        jmp     .ret
.eopen: mov     eax, SYS_CLOSE
        mov     edi, ebx
        syscall
        lea     rax, [e_csv_open]
        jmp     .ret
.eempty:
        mov     eax, SYS_CLOSE
        mov     edi, ebx
        syscall
        lea     rax, [e_csv_empty]
.ret:   mov     rbx, rax
        mov     rax, rbx
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret
