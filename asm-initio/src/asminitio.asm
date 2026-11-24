; =============================================================================
;  ASM INITIO -- un grafo de datos estilo GDE, en x86-64 puro
; -----------------------------------------------------------------------------
;  * Cero dependencias: ni libc, ni Xlib, ni loader dinamico.
;  * Habla el protocolo X11 directamente sobre un socket UNIX via syscalls.
;  * Renderiza por software en un framebuffer propio y lo envia con PutImage.
;  * Pipeline real sobre 100.000 registros: FILTER -> SORT (radix) -> ROLLUP.
;
;  Compilar:  nasm -f elf64 src/asminitio.asm -o build/asminitio.o
;             ld -s -o build/asminitio build/asminitio.o
; =============================================================================

bits 64

%include "fonts.inc"

; ---------------------------------------------------------------- constantes
%define W               960
%define H               624
%define NREC            100000
%define NREG            6
%define STAGE           550             ; ms por etapa de la animacion
%define ANIM_LINKS_END  (4*STAGE)
%define ANIM_END        (ANIM_LINKS_END + 600)
%define THR_STEP        50
%define THR_MAX         950

%define SYS_READ        0
%define SYS_WRITE       1
%define SYS_OPEN        2
%define SYS_CLOSE       3
%define SYS_POLL        7
%define SYS_SOCKET      41
%define SYS_CONNECT     42
%define SYS_EXIT        60
%define SYS_CLOCK_GETTIME 228

; paleta
%define C_BG            0x0f1117
%define C_PANEL         0x171a23
%define C_BORDER        0x262b38
%define C_TEXT          0xe6e9ef
%define C_MUTED         0x8a93a6
%define C_DIM           0x4b5263
%define C_YELLOW        0xf5c542
%define C_GREEN         0x3ccf7a
%define C_LINK          0x363c4c
%define C_BOX           0x1d212c
%define C_KW            0xc792ea
%define C_FN            0x82aaff
%define C_NUM           0xf78c6c
%define C_CMT           0x6b8f71

; geometria
%define GX0             40              ; x del primer componente
%define GSTEP           188             ; separacion entre componentes
%define BOXW            128
%define BOXH            96
%define BOXY            116
%define LINKY           (BOXY + 50)

; ------------------------------------------------------------------- macros
%macro SYSCALL3 4
        mov     eax, %1
        mov     rdi, %2
        mov     rsi, %3
        mov     rdx, %4
        syscall
%endmacro

; TEXT x, y, str, color, font   (no usar rdi/rsi/rdx/rcx/r8 como argumentos)
%macro TEXT 5
        mov     edi, %1
        mov     esi, %2
        lea     rdx, [%3]
        mov     ecx, %4
        lea     r8, [%5]
        call    draw_text
%endmacro

%macro RECT 5
        mov     edi, %1
        mov     esi, %2
        mov     edx, %3
        mov     ecx, %4
        mov     r8d, %5
        call    fill_rect
%endmacro

%macro ROUND 6
        mov     edi, %1
        mov     esi, %2
        mov     edx, %3
        mov     ecx, %4
        mov     r8d, %5
        mov     r9d, %6
        call    fill_round
%endmacro

%macro DIE 1
        lea     rsi, [%1]
        call    die
%endmacro

; ===================================================================== DATA
section .data

font_s:         dd FONT_S_W, FONT_S_H
                dq font_s_data
font_l:         dd FONT_L_W, FONT_L_H
                dq font_l_data

s_DISPLAY:      db "DISPLAY", 0
s_XAUTHORITY:   db "XAUTHORITY", 0
s_HOME:         db "HOME", 0
s_xauthfile:    db "/.Xauthority", 0
s_x11path:      db "/tmp/.X11-unix/X"
s_cookie:       db "MIT-MAGIC-COOKIE-1"
s_wm_protocols: db "WM_PROTOCOLS"
s_wm_delete:    db "WM_DELETE_WINDOW"
s_wm_name:      db "ASM Initio"
s_wm_name_len   equ $ - s_wm_name
s_wm_class:     db "asminitio", 0, "AsmInitio", 0
s_wm_class_len  equ $ - s_wm_class

e_connect:      db "asminitio: no pude conectar al servidor X (DISPLAY?)", 10, 0
e_refused:      db "asminitio: el servidor X rechazo la conexion: ", 0
e_auth:         db "asminitio: el servidor X pide autenticacion adicional", 10, 0
e_io:           db "asminitio: error de E/S con el servidor X", 10, 0
e_visual:       db "asminitio: se necesita un visual TrueColor de 24/32 bits LSB", 10, 0
e_atom:         db "asminitio: error en InternAtom", 10, 0
s_nl:           db 10, 0

; --- textos de la UI (UTF-8; draw_text decodifica Latin-1 de 2 bytes)
t_title:        db "ASM INITIO", 0
t_subtitle:     db "grafo de datos en x86-64 puro", 0
t_badge:        db "0 dependencias · X11 a mano · sin libc", 0
t_graph:        db "GRAFO", 0
t_graphfile:    db "ventas_por_region.mp", 0
t_run:          db "EJECUTAR (R)", 0
t_minus:        db "-", 0
t_plus:         db "+", 0
t_newdata:      db "DATOS NUEVOS (N)", 0
t_filterlbl:    db "monto >", 0
t_st_idle1:     db "Listo. Presioná EJECUTAR.", 0
t_st_idle2:     db " registros en memoria", 0
t_st_run1:      db "Ejecutando grafo...", 0
t_st_run2:      db "registros fluyendo por los flujos", 0
t_st_ok1:       db "OK · pipeline real: ", 0
t_us:           db " µs", 0
t_st_ok2:       db "(la animación es para humanos)", 0
t_sqltitle:     db "SQL EQUIVALENTE  ·  Oracle / BigQuery / MSSQL", 0
t_restitle:     db "OUTPUT TABLE  ·  resultado", 0
t_h_region:     db "REGIÓN", 0
t_h_regs:       db "REGS", 0
t_h_total:      db "TOTAL $", 0
t_h_prom:       db "PROM", 0
t_total:        db "TOTAL", 0
t_empty1:       db "Sin resultados todavía.", 0
t_empty2:       db "Ejecutá el grafo con R o con el botón.", 0
t_processing:   db "procesando...", 0
t_footer:       db "R ejecutar  ·  +/- o rueda: umbral  ·  N datos nuevos  ·  Q/Esc salir  ·  ELF estático, sin libc ni Xlib", 0

; componentes: nombre, linea1, linea2, color de cabecera
c_n0:   db "INPUT FILE", 0
c_n1:   db "FILTER BY EXPR", 0
c_n2:   db "SORT", 0
c_n3:   db "ROLLUP", 0
c_n4:   db "OUTPUT TABLE", 0
c_a0:   db "ventas.dat", 0
c_a1:   db "monto > ", 0
c_a2:   db "key: region", 0
c_a3:   db "key: region", 0
c_a4:   db "resultado", 0
c_b0:   db " regs", 0
c_b1:   db "reject: ", 0
c_b2:   db "radix estable", 0
c_b3:   db "count, sum", 0
c_b4:   db " filas", 0
c_dash: db "-", 0

comp_name:      dq c_n0, c_n1, c_n2, c_n3, c_n4
comp_l1:        dq c_a0, c_a1, c_a2, c_a3, c_a4
comp_l2:        dq 0,    0,    c_b2, c_b3, 0
comp_color:     dd 0x2f6fde, 0xb0569e, 0xd9822b, 0x2a9d8f, 0x2f6fde

; SQL
q_select:   db "SELECT", 0
q_region_c: db "region,", 0
q_count:    db "COUNT", 0
q_star:     db "(*)", 0
q_as:       db "AS", 0
q_registros: db "registros,", 0
q_sum:      db "SUM", 0
q_avg:      db "AVG", 0
q_monto_p:  db "(monto)", 0
q_total:    db "total,", 0
q_promedio: db "promedio", 0
q_from:     db "FROM", 0
q_ventas:   db "ventas", 0
q_where:    db "WHERE", 0
q_monto_gt: db "monto >", 0
q_groupby:  db "GROUP BY", 0
q_orderby:  db "ORDER BY", 0
q_region:   db "region", 0
q_region_s: db "region;", 0
q_c1:       db "-- Sin motor SQL: el filtro, el sort", 0
q_c2:       db "-- y el rollup corren en x86-64 puro.", 0

; regiones
r_0:    db "AMBA", 0
r_1:    db "PAMPEANA", 0
r_2:    db "CUYO", 0
r_3:    db "NOA", 0
r_4:    db "NEA", 0
r_5:    db "PATAGONIA", 0
region_name:    dq r_0, r_1, r_2, r_3, r_4, r_5
region_color:   dd 0x4e9af1, 0xf1a34e, 0x5bd18b, 0xe0607e, 0xb38cf0, 0x4fd1d9
region_max:     dd 900, 800, 600, 450, 400, 1000
region_weights: db 0,0,0,0,0, 1,1,1, 2,2, 3,3, 4,4, 5,5

; botones: x, y, w, h, color, pad, label
%define BTN_RUN   0
%define BTN_MINUS 1
%define BTN_PLUS  2
%define BTN_NEW   3
%define NBTN      4
%define BTN_SIZE  32
buttons:
        dd 16,  268, 140, 36, 0x2f9e5c, 0
        dq t_run
        dd 272, 268, 36,  36, 0x3a4152, 0
        dq t_minus
        dd 384, 268, 36,  36, 0x3a4152, 0
        dq t_plus
        dd 436, 268, 160, 36, 0x3b5ba8, 0
        dq t_newdata

seed:           dd 0x2545F491
thr:            dd 300
hover:          dd -1

; ====================================================================== BSS
section .bss
envp:           resq 1
xfd:            resd 1
id_base:        resd 1
root:           resd 1
depth:          resd 1
maxreq:         resd 1
strip_rows:     resd 1
wid:            resd 1
gc:             resd 1
atom_protocols: resd 1
atom_delete:    resd 1
dispnum:        resb 16
dispnum_len:    resd 1
auth_ptr:       resq 1
auth_len:       resd 1
sockaddr:       resb 112
pathbuf:        resb 512
req:            resb 256
evbuf:          resb 8192
evlen:          resd 1
pollfd:         resb 8
timespec:       resq 2
numbuf:         resb 32
numtmp:         resb 32

dirty:          resb 1
run_state:      resb 1              ; 0 nunca, 1 animando, 2 listo
anim_start:     resq 1
anim_t:         resd 1
pipe_ns:        resq 1

n_filter:       resd 1
n_rows:         resd 1
cnt:            resd 8
pos:            resd 8
res_region:     resd 8
res_count:      resd 8
res_sum:        resq 8

alignb 64
authbuf:        resb 65536
setupbuf:       resb 262144
rec_region:     resb NREC
f_region:       resb NREC
s_region:       resb NREC
alignb 64
rec_monto:      resd NREC
f_monto:        resd NREC
s_monto:        resd NREC
alignb 64
fb:             resd W*H

; ===================================================================== CODE
section .text
global _start

_start:
        mov     rax, [rsp]                  ; argc
        lea     rbx, [rsp + rax*8 + 16]     ; envp
        mov     [envp], rbx

        call    x11_connect
        call    x11_create_window
        call    gen_data
        mov     byte [dirty], 1

main_loop:
        cmp     byte [run_state], 1
        jne     .noanim
        call    update_anim
.noanim:
        cmp     byte [dirty], 0
        je      .poll
        call    render
        call    present
        mov     byte [dirty], 0
.poll:
        mov     eax, [xfd]
        mov     [pollfd], eax
        mov     dword [pollfd+4], 1         ; events=POLLIN, revents=0
        mov     edx, -1
        cmp     byte [run_state], 1
        jne     .wait
        mov     edx, 16                     ; ~60 fps mientras anima
.wait:
        mov     eax, SYS_POLL
        lea     rdi, [pollfd]
        mov     esi, 1
        syscall
        test    eax, eax
        jle     main_loop                   ; timeout o EINTR
        movzx   eax, word [pollfd+6]
        test    eax, 1
        jnz     .readable
        test    eax, 0x18                   ; POLLERR | POLLHUP
        jnz     quit
        jmp     main_loop
.readable:
        call    read_events
        jmp     main_loop

quit:
        mov     eax, SYS_EXIT
        xor     edi, edi
        syscall

; -----------------------------------------------------------------------------
; die(rsi = mensaje z-string) -> stderr, exit(1)
die:
        call    eprint
        mov     eax, SYS_EXIT
        mov     edi, 1
        syscall

; eprint(rsi = z-string) -> stderr
eprint:
        mov     rdx, rsi
.len:   cmp     byte [rdx], 0
        je      .go
        inc     rdx
        jmp     .len
.go:    sub     rdx, rsi
        mov     eax, SYS_WRITE
        mov     edi, 2
        syscall
        ret

; getenv(rdi = nombre) -> rax = valor o 0
getenv:
        mov     r8, [envp]
.next:  mov     rsi, [r8]
        test    rsi, rsi
        jz      .none
        mov     rcx, rdi
.cmp:   mov     al, [rcx]
        test    al, al
        jz      .endname
        cmp     al, [rsi]
        jne     .skip
        inc     rcx
        inc     rsi
        jmp     .cmp
.endname:
        cmp     byte [rsi], '='
        jne     .skip
        lea     rax, [rsi+1]
        ret
.skip:  add     r8, 8
        jmp     .next
.none:  xor     eax, eax
        ret

; write_full(rsi = buf, rdx = len) al socket X
write_full:
        push    rbx
        push    r12
        mov     rbx, rsi
        mov     r12, rdx
.lp:    test    r12, r12
        jz      .done
        mov     eax, SYS_WRITE
        mov     edi, [xfd]
        mov     rsi, rbx
        mov     rdx, r12
        syscall
        cmp     rax, -4                     ; EINTR
        je      .lp
        test    rax, rax
        jle     .err
        add     rbx, rax
        sub     r12, rax
        jmp     .lp
.done:  pop     r12
        pop     rbx
        ret
.err:   DIE     e_io

; read_full(rsi = buf, rdx = len) desde el socket X
read_full:
        push    rbx
        push    r12
        mov     rbx, rsi
        mov     r12, rdx
.lp:    test    r12, r12
        jz      .done
        mov     eax, SYS_READ
        mov     edi, [xfd]
        mov     rsi, rbx
        mov     rdx, r12
        syscall
        cmp     rax, -4
        je      .lp
        test    rax, rax
        jle     .err
        add     rbx, rax
        sub     r12, rax
        jmp     .lp
.done:  pop     r12
        pop     rbx
        ret
.err:   DIE     e_io

; try_connect(rdi = sockaddr, esi = len) -> eax = fd o -1
try_connect:
        push    rbx
        push    r12
        push    r13
        mov     r12, rdi
        mov     r13d, esi
        mov     eax, SYS_SOCKET
        mov     edi, 1                      ; AF_UNIX
        mov     esi, 1                      ; SOCK_STREAM
        xor     edx, edx
        syscall
        test    eax, eax
        js      .fail
        mov     ebx, eax
        mov     eax, SYS_CONNECT
        mov     edi, ebx
        mov     rsi, r12
        mov     edx, r13d
        syscall
        test    eax, eax
        jns     .ok
        mov     eax, SYS_CLOSE
        mov     edi, ebx
        syscall
.fail:  mov     eax, -1
        jmp     .out
.ok:    mov     eax, ebx
.out:   pop     r13
        pop     r12
        pop     rbx
        ret

; =============================================================================
;  X11: conexion, autenticacion y handshake
; =============================================================================
x11_connect:
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15

        ; --- DISPLAY=[host]:N[.S]  -> N
        lea     rdi, [s_DISPLAY]
        call    getenv
        lea     rdi, [dispnum]
        xor     ecx, ecx
        test    rax, rax
        jz      .defdisp
.colon: mov     dl, [rax]
        test    dl, dl
        jz      .defdisp
        inc     rax
        cmp     dl, ':'
        jne     .colon
.digit: mov     dl, [rax]
        cmp     dl, '0'
        jb      .digdone
        cmp     dl, '9'
        ja      .digdone
        mov     [rdi+rcx], dl
        inc     ecx
        inc     rax
        cmp     ecx, 8
        jb      .digit
.digdone:
        test    ecx, ecx
        jnz     .havenum
.defdisp:
        mov     byte [rdi], '0'
        mov     ecx, 1
.havenum:
        mov     [dispnum_len], ecx

        ; --- sockaddr_un: "/tmp/.X11-unix/X<N>"
        mov     word [sockaddr], 1
        lea     rdi, [sockaddr+2]
        lea     rsi, [s_x11path]
        mov     ecx, 16
        rep movsb
        lea     rsi, [dispnum]
        mov     ecx, [dispnum_len]
        rep movsb
        mov     byte [rdi], 0
        lea     rdi, [sockaddr]
        mov     esi, [dispnum_len]
        add     esi, 2 + 16 + 1
        call    try_connect
        test    eax, eax
        jns     .connected
        ; --- reintento con el socket abstracto "\0/tmp/.X11-unix/X<N>"
        lea     rdi, [sockaddr+3]
        lea     rsi, [sockaddr+2]
        mov     ecx, [dispnum_len]
        add     ecx, 16
        add     rdi, rcx
        add     rsi, rcx
        dec     rdi
        dec     rsi
        std                                 ; corrimiento de 1 byte hacia la derecha
        rep movsb
        cld
        mov     byte [sockaddr+2], 0
        lea     rdi, [sockaddr]
        mov     esi, [dispnum_len]
        add     esi, 2 + 1 + 16
        call    try_connect
        test    eax, eax
        jns     .connected
        DIE     e_connect
.connected:
        mov     [xfd], eax

        call    load_xauth

        ; --- pedido de conexion (little endian, X11.0)
        lea     rdi, [req]
        xor     eax, eax
        mov     ecx, 48/8
        push    rdi
        rep stosq
        pop     rdi
        mov     byte [rdi], 'l'
        mov     word [rdi+2], 11
        mov     edx, 12
        cmp     qword [auth_ptr], 0
        je      .send
        mov     word [rdi+6], 18
        mov     word [rdi+8], 16
        lea     rsi, [s_cookie]
        lea     rdi, [req+12]
        mov     ecx, 18
        rep movsb
        mov     rsi, [auth_ptr]
        lea     rdi, [req+32]
        mov     ecx, 16
        rep movsb
        mov     edx, 48
.send:  lea     rsi, [req]
        call    write_full

        ; --- respuesta: 8 bytes + datos adicionales
        lea     rsi, [setupbuf]
        mov     edx, 8
        call    read_full
        movzx   edx, word [setupbuf+6]
        shl     edx, 2
        cmp     edx, 262144 - 8
        ja      .ioerr
        lea     rsi, [setupbuf+8]
        call    read_full
        movzx   eax, byte [setupbuf]
        cmp     eax, 1
        je      .success
        cmp     eax, 2
        je      .needauth
        ; fallo: motivo en setupbuf+8, largo en setupbuf[1]
        lea     rsi, [e_refused]
        call    eprint
        movzx   edx, byte [setupbuf+1]
        mov     eax, SYS_WRITE
        mov     edi, 2
        lea     rsi, [setupbuf+8]
        syscall
        DIE     s_nl
.needauth:
        DIE     e_auth
.ioerr: DIE     e_io

.success:
        lea     rsi, [setupbuf]
        mov     eax, [rsi+12]
        mov     [id_base], eax
        movzx   eax, word [rsi+26]
        mov     [maxreq], eax
        cmp     byte [rsi+30], 0            ; image-byte-order LSBFirst
        jne     .badvis
        movzx   r12d, byte [rsi+29]         ; cantidad de formatos
        movzx   eax, word [rsi+24]          ; largo del vendor
        add     eax, 3
        and     eax, ~3
        lea     r13, [rsi + 40 + rax]       ; formatos
        lea     r14, [r13 + r12*8]          ; primera pantalla
        mov     eax, [r14]
        mov     [root], eax
        movzx   r15d, byte [r14+38]         ; profundidad raiz
        mov     [depth], r15d
        ; buscar bpp de esa profundidad
        xor     ecx, ecx
.fmt:   cmp     ecx, r12d
        jae     .badvis
        movzx   eax, byte [r13 + rcx*8]
        cmp     eax, r15d
        je      .fmtfound
        inc     ecx
        jmp     .fmt
.fmtfound:
        cmp     byte [r13 + rcx*8 + 1], 32
        jne     .badvis
        cmp     r15d, 24
        jb      .badvis

        ; filas por PutImage: largo maximo de pedido (unidades de 4 bytes)
        mov     eax, [maxreq]
        sub     eax, 6
        xor     edx, edx
        mov     ecx, W
        div     ecx
        cmp     eax, 64
        jbe     .rowsok
        mov     eax, 64
.rowsok:
        mov     [strip_rows], eax

        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret
.badvis:
        DIE     e_visual

; -----------------------------------------------------------------------------
; load_xauth: busca MIT-MAGIC-COOKIE-1 para nuestro display en ~/.Xauthority
load_xauth:
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15
        mov     qword [auth_ptr], 0

        lea     rdi, [s_XAUTHORITY]
        call    getenv
        test    rax, rax
        jnz     .open
        lea     rdi, [s_HOME]
        call    getenv
        test    rax, rax
        jz      .none
        lea     rdi, [pathbuf]
        mov     rsi, rax
.cp:    lodsb
        test    al, al
        jz      .cpdone
        stosb
        lea     rcx, [pathbuf+480]
        cmp     rdi, rcx
        jb      .cp
.cpdone:
        lea     rsi, [s_xauthfile]
        mov     ecx, 13
        rep movsb
        lea     rax, [pathbuf]
.open:  mov     rdi, rax
        mov     eax, SYS_OPEN
        xor     esi, esi
        xor     edx, edx
        syscall
        test    eax, eax
        js      .none
        mov     ebx, eax
        xor     r12d, r12d                  ; bytes leidos
.rd:    mov     eax, SYS_READ
        mov     edi, ebx
        lea     rsi, [authbuf + r12]
        mov     edx, 65536
        sub     edx, r12d
        jz      .rddone
        syscall
        test    rax, rax
        jle     .rddone
        add     r12d, eax
        jmp     .rd
.rddone:
        mov     eax, SYS_CLOSE
        mov     edi, ebx
        syscall

        lea     r13, [authbuf + r12]        ; fin
        lea     r12, [authbuf]              ; cursor
.entry: lea     rax, [r12+2]
        cmp     rax, r13
        ja      .none
        add     r12, 2                      ; family
        call    rd_field                    ; address
        jc      .none
        call    rd_field                    ; number
        jc      .none
        mov     r14, rax
        mov     r15d, ecx
        call    rd_field                    ; name
        jc      .none
        mov     rbx, rax
        push    rcx
        call    rd_field                    ; data
        pop     rdx
        jc      .none
        ; name == MIT-MAGIC-COOKIE-1 ?
        cmp     edx, 18
        jne     .entry
        cmp     ecx, 16
        jne     .entry
        push    rax
        mov     rsi, rbx
        lea     rdi, [s_cookie]
        mov     ecx, 18
        repe cmpsb
        pop     rax
        jne     .entry
        ; number vacio (comodin) o igual a nuestro display
        test    r15d, r15d
        jz      .match
        cmp     r15d, [dispnum_len]
        jne     .entry
        push    rax
        mov     rsi, r14
        lea     rdi, [dispnum]
        mov     ecx, r15d
        repe cmpsb
        pop     rax
        jne     .entry
.match: mov     [auth_ptr], rax
.none:  pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

; rd_field: lee campo (u16 BE largo + datos) en r12 (cursor) / r13 (fin)
;   -> rax = ptr, ecx = largo, CF=1 si se pasa del fin
rd_field:
        lea     rax, [r12+2]
        cmp     rax, r13
        ja      .err
        movzx   ecx, word [r12]
        xchg    cl, ch
        add     r12, 2
        mov     rax, r12
        add     r12, rcx
        cmp     r12, r13
        ja      .err
        clc
        ret
.err:   stc
        ret

; -----------------------------------------------------------------------------
; intern_atom(rsi = nombre, edx = largo) -> eax = atom   (sincronico)
intern_atom:
        push    rbx
        mov     ebx, edx
        lea     rdi, [req]
        mov     byte [rdi], 16              ; InternAtom
        mov     byte [rdi+1], 0
        lea     eax, [rbx+3]
        shr     eax, 2
        add     eax, 2
        mov     [rdi+2], ax
        mov     [rdi+4], bx
        mov     word [rdi+6], 0
        add     rdi, 8
        mov     ecx, ebx
        rep movsb
        mov     dword [rdi], 0              ; padding
        lea     edx, [rbx+3]
        and     edx, ~3
        add     edx, 8
        lea     rsi, [req]
        call    write_full
.wait:  lea     rsi, [evbuf]
        mov     edx, 32
        call    read_full
        movzx   eax, byte [evbuf]
        test    eax, eax
        jz      .err
        cmp     eax, 1
        jne     .wait                       ; evento: ignorar
        mov     eax, [evbuf+8]
        pop     rbx
        ret
.err:   DIE     e_atom

; change_property(esi = property, edx = type, ecx = format, r8 = data, r9d = n unidades)
change_property:
        push    rbx
        push    r12
        mov     ebx, ecx                    ; format
        mov     r12d, r9d
        lea     rdi, [req]
        mov     byte [rdi], 18              ; ChangeProperty
        mov     byte [rdi+1], 0             ; Replace
        mov     eax, [wid]
        mov     [rdi+4], eax
        mov     [rdi+8], esi
        mov     [rdi+12], edx
        mov     [rdi+16], bl
        mov     byte [rdi+17], 0
        mov     word [rdi+18], 0
        mov     [rdi+20], r12d
        ; bytes de datos
        mov     eax, r12d
        cmp     ebx, 32
        jne     .b8
        shl     eax, 2
.b8:    mov     ecx, eax
        lea     rdi, [req+24]
        mov     rsi, r8
        rep movsb
        mov     dword [rdi], 0
        add     eax, 3
        shr     eax, 2
        lea     edx, [rax + 6]
        mov     [req+2], dx
        shl     edx, 2
        lea     rsi, [req]
        call    write_full
        pop     r12
        pop     rbx
        ret

; -----------------------------------------------------------------------------
x11_create_window:
        mov     eax, [id_base]
        or      eax, 1
        mov     [wid], eax
        mov     eax, [id_base]
        or      eax, 2
        mov     [gc], eax

        ; CreateWindow
        lea     rdi, [req]
        mov     byte [rdi], 1
        mov     byte [rdi+1], 0             ; depth = CopyFromParent
        mov     word [rdi+2], 10
        mov     eax, [wid]
        mov     [rdi+4], eax
        mov     eax, [root]
        mov     [rdi+8], eax
        mov     dword [rdi+12], 0           ; x, y
        mov     word [rdi+16], W
        mov     word [rdi+18], H
        mov     word [rdi+20], 0            ; borde
        mov     word [rdi+22], 1            ; InputOutput
        mov     dword [rdi+24], 0           ; visual = CopyFromParent
        mov     dword [rdi+28], 0x802       ; BackPixel | EventMask
        mov     dword [rdi+32], C_BG
        ; Exposure | KeyPress | ButtonPress | PointerMotion | StructureNotify
        mov     dword [rdi+36], 0x8000 | 0x1 | 0x4 | 0x40 | 0x20000
        lea     rsi, [req]
        mov     edx, 40
        call    write_full

        ; WM_DELETE_WINDOW, para cerrar prolijo desde el gestor de ventanas
        lea     rsi, [s_wm_protocols]
        mov     edx, 12
        call    intern_atom
        mov     [atom_protocols], eax
        lea     rsi, [s_wm_delete]
        mov     edx, 16
        call    intern_atom
        mov     [atom_delete], eax

        mov     esi, [atom_protocols]
        mov     edx, 4                      ; ATOM
        mov     ecx, 32
        lea     r8, [atom_delete]
        mov     r9d, 1
        call    change_property

        mov     esi, 39                     ; WM_NAME
        mov     edx, 31                     ; STRING
        mov     ecx, 8
        lea     r8, [s_wm_name]
        mov     r9d, s_wm_name_len
        call    change_property

        mov     esi, 67                     ; WM_CLASS
        mov     edx, 31
        mov     ecx, 8
        lea     r8, [s_wm_class]
        mov     r9d, s_wm_class_len
        call    change_property

        ; WM_NORMAL_HINTS: tamanio fijo (min = max)
        lea     rdi, [pathbuf]
        xor     eax, eax
        mov     ecx, 18
        rep stosd
        mov     dword [pathbuf], 16 | 32    ; PMinSize | PMaxSize
        mov     dword [pathbuf+20], W
        mov     dword [pathbuf+24], H
        mov     dword [pathbuf+28], W
        mov     dword [pathbuf+32], H
        mov     esi, 40                     ; WM_NORMAL_HINTS
        mov     edx, 41                     ; WM_SIZE_HINTS
        mov     ecx, 32
        lea     r8, [pathbuf]
        mov     r9d, 18
        call    change_property

        ; CreateGC
        lea     rdi, [req]
        mov     byte [rdi], 55
        mov     byte [rdi+1], 0
        mov     word [rdi+2], 4
        mov     eax, [gc]
        mov     [rdi+4], eax
        mov     eax, [wid]
        mov     [rdi+8], eax
        mov     dword [rdi+12], 0
        lea     rsi, [req]
        mov     edx, 16
        call    write_full

        ; MapWindow
        lea     rdi, [req]
        mov     byte [rdi], 8
        mov     byte [rdi+1], 0
        mov     word [rdi+2], 2
        mov     eax, [wid]
        mov     [rdi+4], eax
        lea     rsi, [req]
        mov     edx, 8
        call    write_full
        ret

; -----------------------------------------------------------------------------
; present: framebuffer -> ventana, en franjas de PutImage (ZPixmap)
present:
        push    rbx
        push    r12
        xor     ebx, ebx
.lp:    cmp     ebx, H
        jge     .done
        mov     r12d, [strip_rows]
        mov     eax, H
        sub     eax, ebx
        cmp     r12d, eax
        cmovg   r12d, eax
        lea     rdi, [req]
        mov     byte [rdi], 72              ; PutImage
        mov     byte [rdi+1], 2             ; ZPixmap
        mov     eax, r12d
        imul    eax, W
        add     eax, 6
        mov     [rdi+2], ax
        mov     eax, [wid]
        mov     [rdi+4], eax
        mov     eax, [gc]
        mov     [rdi+8], eax
        mov     word [rdi+12], W
        mov     [rdi+14], r12w
        mov     word [rdi+16], 0
        mov     [rdi+18], bx
        mov     byte [rdi+20], 0
        mov     eax, [depth]
        mov     [rdi+21], al
        mov     word [rdi+22], 0
        lea     rsi, [req]
        mov     edx, 24
        call    write_full
        mov     eax, ebx
        imul    eax, W*4
        lea     rsi, [fb + rax]
        mov     edx, r12d
        imul    edx, W*4
        call    write_full
        add     ebx, r12d
        jmp     .lp
.done:  pop     r12
        pop     rbx
        ret

; -----------------------------------------------------------------------------
; read_events: lee del socket y despacha bloques de 32 bytes
read_events:
        push    rbx
        push    r12
        mov     eax, SYS_READ
        mov     edi, [xfd]
        mov     ecx, [evlen]
        lea     rsi, [evbuf + rcx]
        mov     edx, 8192
        sub     edx, ecx
        syscall
        cmp     rax, -4
        je      .out
        test    rax, rax
        jle     quit                        ; servidor cerro la conexion
        add     [evlen], eax
        lea     rbx, [evbuf]
        mov     r12d, [evlen]
.lp:    cmp     r12d, 32
        jb      .keep
        mov     ecx, 32
        cmp     byte [rbx], 1               ; reply: puede traer datos extra
        jne     .one
        mov     eax, [rbx+4]
        shl     eax, 2
        add     ecx, eax
        cmp     r12d, ecx
        jb      .keep
        jmp     .adv
.one:   push    rcx
        mov     rdi, rbx
        call    handle_event
        pop     rcx
.adv:   add     rbx, rcx
        sub     r12d, ecx
        jmp     .lp
.keep:  ; mover el resto al principio
        lea     rdi, [evbuf]
        mov     rsi, rbx
        mov     ecx, r12d
        rep movsb
        mov     [evlen], r12d
.out:   pop     r12
        pop     rbx
        ret

; handle_event(rdi = evento de 32 bytes)
handle_event:
        movzx   eax, byte [rdi]
        and     eax, 0x7f
        cmp     eax, 12                     ; Expose
        je      .expose
        cmp     eax, 2                      ; KeyPress
        je      .key
        cmp     eax, 4                      ; ButtonPress
        je      .button
        cmp     eax, 6                      ; MotionNotify
        je      .motion
        cmp     eax, 33                     ; ClientMessage
        je      .client
        ret
.expose:
        mov     byte [dirty], 1
        ret
.client:
        mov     eax, [rdi+12]
        cmp     eax, [atom_delete]
        je      quit
        ret
.key:   movzx   eax, byte [rdi+1]           ; keycode (evdev/xkb)
        cmp     eax, 9                      ; Escape
        je      quit
        cmp     eax, 24                     ; q
        je      quit
        cmp     eax, 27                     ; r
        je      action_run
        cmp     eax, 36                     ; Return
        je      action_run
        cmp     eax, 65                     ; espacio
        je      action_run
        cmp     eax, 104                    ; KP_Enter
        je      action_run
        cmp     eax, 21                     ; = / +
        je      action_up
        cmp     eax, 86                     ; KP_Add
        je      action_up
        cmp     eax, 20                     ; -
        je      action_down
        cmp     eax, 82                     ; KP_Subtract
        je      action_down
        cmp     eax, 61                     ; '-' en teclado espaniol/latam
        je      action_down
        cmp     eax, 35                     ; '+' en teclado espaniol/latam
        je      action_up
        cmp     eax, 57                     ; n
        je      action_new
        ret
.button:
        movzx   eax, byte [rdi+1]
        cmp     eax, 4                      ; rueda arriba
        je      action_up
        cmp     eax, 5                      ; rueda abajo
        je      action_down
        cmp     eax, 1
        jne     .ret
        movsx   esi, word [rdi+26]
        movsx   edi, word [rdi+24]
        call    hit_test
        cmp     eax, BTN_RUN
        je      action_run
        cmp     eax, BTN_MINUS
        je      action_down
        cmp     eax, BTN_PLUS
        je      action_up
        cmp     eax, BTN_NEW
        je      action_new
.ret:   ret
.motion:
        movsx   esi, word [rdi+26]
        movsx   edi, word [rdi+24]
        call    hit_test
        cmp     eax, [hover]
        je      .ret
        mov     [hover], eax
        mov     byte [dirty], 1
        ret

; hit_test(edi = x, esi = y) -> eax = indice de boton o -1
hit_test:
        xor     ecx, ecx
        lea     r8, [buttons]
.lp:    cmp     ecx, NBTN
        jae     .none
        mov     eax, edi
        sub     eax, [r8]
        js      .next
        cmp     eax, [r8+8]
        jge     .next
        mov     eax, esi
        sub     eax, [r8+4]
        js      .next
        cmp     eax, [r8+12]
        jge     .next
        mov     eax, ecx
        ret
.next:  inc     ecx
        add     r8, BTN_SIZE
        jmp     .lp
.none:  mov     eax, -1
        ret

; ---------------------------------------------------------------- acciones
action_run:
        call    run_pipeline
        call    now_ms
        mov     [anim_start], rax
        mov     dword [anim_t], 0
        mov     byte [run_state], 1
        mov     byte [dirty], 1
        ret

action_up:
        mov     eax, [thr]
        add     eax, THR_STEP
        cmp     eax, THR_MAX
        jle     .ok
        mov     eax, THR_MAX
.ok:    mov     [thr], eax
        jmp     thr_changed
action_down:
        mov     eax, [thr]
        sub     eax, THR_STEP
        jns     .ok
        xor     eax, eax
.ok:    mov     [thr], eax
thr_changed:
        mov     byte [dirty], 1
        cmp     byte [run_state], 0         ; si ya corrio: resultado en vivo
        je      .r
        call    run_pipeline
.r:     ret

action_new:
        rdtsc
        or      eax, 1
        mov     [seed], eax
        call    gen_data
        jmp     action_run

; now_ms -> rax ; now_ns -> rax  (CLOCK_MONOTONIC)
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

update_anim:
        call    now_ms
        sub     rax, [anim_start]
        mov     [anim_t], eax
        mov     byte [dirty], 1
        cmp     eax, ANIM_END
        jb      .r
        mov     byte [run_state], 2
.r:     ret

; =============================================================================
;  Datos y pipeline
; =============================================================================
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

gen_data:
        push    rbx
        push    r12
        xor     ebx, ebx
.lp:    call    rand32
        and     eax, 15
        movzx   r12d, byte [region_weights + rax]
        mov     [rec_region + rbx], r12b
        call    rand32
        xor     edx, edx
        div     dword [region_max + r12*4]
        add     edx, 10
        mov     [rec_monto + rbx*4], edx
        inc     ebx
        cmp     ebx, NREC
        jb      .lp
        pop     r12
        pop     rbx
        ret

; run_pipeline: FILTER (monto > thr) -> SORT radix por region -> ROLLUP
run_pipeline:
        push    rbx
        push    r12
        push    r13
        push    r15
        call    now_ns
        mov     r15, rax

        ; ---- FILTER BY EXPRESSION
        mov     r8d, [thr]
        xor     ecx, ecx
        xor     edx, edx
.f:     mov     eax, [rec_monto + rcx*4]
        cmp     eax, r8d
        jbe     .fskip
        mov     [f_monto + rdx*4], eax
        mov     al, [rec_region + rcx]
        mov     [f_region + rdx], al
        inc     edx
.fskip: inc     ecx
        cmp     ecx, NREC
        jb      .f
        mov     [n_filter], edx
        mov     r12d, edx                   ; n

        ; ---- SORT: counting/radix sort estable por clave region
        xor     eax, eax
        lea     rdi, [cnt]
        mov     ecx, 8
        rep stosd
        xor     ecx, ecx
.c:     cmp     ecx, r12d
        jae     .cdone
        movzx   eax, byte [f_region + rcx]
        inc     dword [cnt + rax*4]
        inc     ecx
        jmp     .c
.cdone: xor     eax, eax
        xor     ecx, ecx
.pre:   mov     [pos + rcx*4], eax
        add     eax, [cnt + rcx*4]
        inc     ecx
        cmp     ecx, 8
        jb      .pre
        xor     ecx, ecx
.sc:    cmp     ecx, r12d
        jae     .scdone
        movzx   eax, byte [f_region + rcx]
        mov     edx, [pos + rax*4]
        inc     dword [pos + rax*4]
        mov     [s_region + rdx], al
        mov     eax, [f_monto + rcx*4]
        mov     [s_monto + rdx*4], eax
        inc     ecx
        jmp     .sc
.scdone:

        ; ---- ROLLUP sobre entrada ordenada (key: region)
        xor     ecx, ecx                    ; i
        xor     ebx, ebx                    ; filas
.grp:   cmp     ecx, r12d
        jae     .rdone
        movzx   r13d, byte [s_region + rcx]
        xor     edx, edx                    ; count
        xor     r8d, r8d                    ; sum
.acc:   cmp     ecx, r12d
        jae     .emit
        movzx   eax, byte [s_region + rcx]
        cmp     eax, r13d
        jne     .emit
        mov     eax, [s_monto + rcx*4]
        add     r8, rax
        inc     edx
        inc     ecx
        jmp     .acc
.emit:  mov     [res_region + rbx*4], r13d
        mov     [res_count + rbx*4], edx
        mov     [res_sum + rbx*8], r8
        inc     ebx
        jmp     .grp
.rdone: mov     [n_rows], ebx

        call    now_ns
        sub     rax, r15
        mov     [pipe_ns], rax
        pop     r15
        pop     r13
        pop     r12
        pop     rbx
        ret

; =============================================================================
;  Graficos por software
; =============================================================================

; fill_rect(edi x, esi y, edx w, ecx h, r8d color) -- con recorte
fill_rect:
        lea     eax, [rdi+rdx]              ; x1
        lea     r9d, [rsi+rcx]              ; y1
        test    edi, edi
        jns     .x0
        xor     edi, edi
.x0:    test    esi, esi
        jns     .y0
        xor     esi, esi
.y0:    cmp     eax, W
        jle     .x1
        mov     eax, W
.x1:    cmp     r9d, H
        jle     .y1
        mov     r9d, H
.y1:    sub     eax, edi
        jle     .ret
        sub     r9d, esi
        jle     .ret
        mov     r10d, esi
        imul    r10d, W
        add     r10d, edi
        lea     r10, [fb + r10*4]
        mov     r11d, eax
        mov     eax, r8d
.row:   mov     rdi, r10
        mov     ecx, r11d
        rep stosd
        add     r10, W*4
        dec     r9d
        jnz     .row
.ret:   ret

; fill_round(edi x, esi y, edx w, ecx h, r8d radio, r9d color)
fill_round:
        push    rbx
        push    rbp
        push    r12
        push    r13
        push    r14
        push    r15
        push    r9                          ; [rsp] = color
        mov     r12d, edi
        mov     r13d, esi
        mov     r14d, edx
        mov     r15d, ecx
        mov     ebp, r8d
        xor     ebx, ebx
.row:   cmp     ebx, r15d
        jge     .done
        xor     eax, eax                    ; d
        cmp     ebx, ebp
        jge     .chk2
        mov     eax, ebp
        sub     eax, ebx
        jmp     .haved
.chk2:  mov     ecx, r15d
        dec     ecx
        sub     ecx, ebp
        cmp     ebx, ecx
        jle     .haved
        mov     eax, ebx
        sub     eax, ecx
.haved: test    eax, eax
        jz      .draw
        imul    eax, eax
        mov     ecx, ebp
        imul    ecx, ebp
        sub     ecx, eax                    ; r^2 - d^2
        add     ecx, ebp                    ; un poco mas redondo
        mov     eax, ebp
.sq:    mov     edx, eax
        imul    edx, eax
        cmp     edx, ecx
        jle     .sqd
        dec     eax
        jmp     .sq
.sqd:   mov     ecx, ebp
        sub     ecx, eax
        mov     eax, ecx                    ; inset
.draw:  lea     edi, [r12+rax]
        lea     esi, [r13+rbx]
        mov     edx, r14d
        sub     edx, eax
        sub     edx, eax
        mov     ecx, 1
        mov     r8d, [rsp]
        call    fill_rect
        inc     ebx
        jmp     .row
.done:  pop     r9
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbp
        pop     rbx
        ret

; fill_circle(edi cx, esi cy, edx r, ecx color)
fill_circle:
        push    rbx
        push    rbp
        push    r12
        push    r13
        push    r14
        push    r15
        mov     r12d, edi
        mov     r13d, esi
        mov     r14d, edx
        mov     r15d, ecx
        mov     ebp, edx
        imul    ebp, edx
        add     ebp, edx                    ; r^2 + r
        mov     ebx, r14d
        neg     ebx
.dy:    cmp     ebx, r14d
        jg      .done
        mov     eax, r14d
.f:     mov     ecx, eax
        imul    ecx, eax
        mov     edx, ebx
        imul    edx, ebx
        add     ecx, edx
        cmp     ecx, ebp
        jle     .got
        dec     eax
        jmp     .f
.got:   mov     edi, r12d
        sub     edi, eax
        lea     esi, [r13+rbx]
        lea     edx, [rax*2+1]
        mov     ecx, 1
        mov     r8d, r15d
        call    fill_rect
        inc     ebx
        jmp     .dy
.done:  pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbp
        pop     rbx
        ret

; lerp_color(edi c1, esi c2, edx num, ecx den) -> eax
lerp_color:
        push    rbx
        push    r12
        mov     r8d, edx
        mov     r9d, ecx
        xor     r12d, r12d
        xor     ecx, ecx
.ch:    mov     eax, edi
        shr     eax, cl
        and     eax, 0xff
        mov     ebx, esi
        shr     ebx, cl
        and     ebx, 0xff
        sub     ebx, eax
        imul    ebx, r8d
        mov     r10d, eax
        mov     eax, ebx
        cdq
        idiv    r9d
        add     eax, r10d
        shl     eax, cl
        or      r12d, eax
        add     ecx, 8
        cmp     ecx, 24
        jb      .ch
        mov     eax, r12d
        pop     r12
        pop     rbx
        ret

; fill_vgrad(edi x, esi y, edx w, ecx h, r8d c1, r9d c2)
fill_vgrad:
        push    rbx
        push    rbp
        push    r12
        push    r13
        push    r14
        push    r15
        mov     r12d, edi
        mov     r13d, esi
        mov     r14d, edx
        mov     r15d, ecx
        mov     ebp, r8d
        push    r9
        xor     ebx, ebx
.lp:    cmp     ebx, r15d
        jge     .done
        mov     edi, ebp
        mov     esi, [rsp]
        mov     edx, ebx
        mov     ecx, r15d
        call    lerp_color
        mov     r8d, eax
        mov     edi, r12d
        lea     esi, [r13+rbx]
        mov     edx, r14d
        mov     ecx, 1
        call    fill_rect
        inc     ebx
        jmp     .lp
.done:  pop     r9
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbp
        pop     rbx
        ret

; draw_char(edi x, esi y, edx codepoint, ecx color, r8 font) -- alfa 8 bits
draw_char:
        push    rbx
        push    rbp
        push    r12
        push    r13
        push    r14
        push    r15
        mov     r12d, edi
        mov     r13d, esi
        mov     r14d, ecx
        cmp     edx, 32
        jb      .q
        cmp     edx, 255
        jbe     .ok
.q:     mov     edx, '?'
.ok:    sub     edx, 32
        mov     r9d, [r8]                   ; w
        mov     r10d, [r8+4]                ; h
        mov     eax, r9d
        imul    eax, r10d
        imul    eax, edx
        mov     r15, [r8+8]
        add     r15, rax                    ; glifo
        xor     ebx, ebx
.row:   cmp     ebx, r10d
        jge     .done
        lea     eax, [r13+rbx]
        cmp     eax, H
        jae     .nextrow
        imul    eax, W
        mov     r11d, eax
        xor     ecx, ecx
.col:   cmp     ecx, r9d
        jge     .nextrow
        movzx   edx, byte [r15+rcx]
        test    edx, edx
        jz      .nextcol
        lea     eax, [r12+rcx]
        cmp     eax, W
        jae     .nextcol
        add     eax, r11d
        lea     rdi, [fb + rax*4]
        cmp     edx, 255
        jne     .blend
        mov     [rdi], r14d
        jmp     .nextcol
.blend: mov     eax, edx
        shr     eax, 7
        add     edx, eax                    ; a: 0..256
        mov     eax, 256
        sub     eax, edx                    ; 256 - a
        mov     esi, [rdi]
        mov     ebp, esi
        and     esi, 0xFF00FF
        imul    esi, eax
        mov     r8d, r14d
        and     r8d, 0xFF00FF
        imul    r8d, edx
        add     esi, r8d
        shr     esi, 8
        and     esi, 0xFF00FF
        and     ebp, 0x00FF00
        imul    ebp, eax
        mov     r8d, r14d
        and     r8d, 0x00FF00
        imul    r8d, edx
        add     ebp, r8d
        shr     ebp, 8
        and     ebp, 0x00FF00
        or      esi, ebp
        mov     [rdi], esi
.nextcol:
        inc     ecx
        jmp     .col
.nextrow:
        add     r15, r9
        inc     ebx
        jmp     .row
.done:  pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbp
        pop     rbx
        ret

; next_cp: decodifica UTF-8 (hasta Latin-1) en [rbx], avanza rbx -> edx (0 = fin)
next_cp:
        movzx   edx, byte [rbx]
        test    edx, edx
        jz      .r
        inc     rbx
        cmp     edx, 0x80
        jb      .r
        cmp     edx, 0xC2
        je      .c2
        cmp     edx, 0xC3
        je      .c3
.skip:  mov     al, [rbx]                   ; otro multibyte: saltear y '?'
        and     al, 0xC0
        cmp     al, 0x80
        jne     .qm
        inc     rbx
        jmp     .skip
.qm:    mov     edx, '?'
        ret
.c2:    movzx   edx, byte [rbx]
        inc     rbx
        ret
.c3:    movzx   edx, byte [rbx]
        inc     rbx
        add     edx, 0x40
.r:     ret

; draw_text(edi x, esi y, rdx str, ecx color, r8 font) -> eax = x final
draw_text:
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15
        mov     r12d, edi
        mov     r13d, esi
        mov     rbx, rdx
        mov     r14d, ecx
        mov     r15, r8
.lp:    call    next_cp
        test    edx, edx
        jz      .done
        mov     edi, r12d
        mov     esi, r13d
        mov     ecx, r14d
        mov     r8, r15
        call    draw_char
        add     r12d, [r15]
        jmp     .lp
.done:  mov     eax, r12d
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

; text_width(rdx str, r8 font) -> eax
text_width:
        push    rbx
        mov     rbx, rdx
        xor     ecx, ecx
.lp:    call    next_cp
        test    edx, edx
        jz      .done
        inc     ecx
        jmp     .lp
.done:  mov     eax, ecx
        imul    eax, [r8]
        pop     rbx
        ret

; fmt_num(rdi valor, rsi destino) -> eax largo; separador de miles '.'
fmt_num:
        mov     rax, rdi
        lea     r9, [numtmp]
        xor     ecx, ecx
        xor     r10d, r10d
        mov     r11d, 10
.lp:    xor     edx, edx
        div     r11
        add     dl, '0'
        mov     [r9+rcx], dl
        inc     ecx
        inc     r10d
        test    rax, rax
        jz      .rev
        cmp     r10d, 3
        jne     .lp
        mov     byte [r9+rcx], '.'
        inc     ecx
        xor     r10d, r10d
        jmp     .lp
.rev:   mov     eax, ecx
        xor     edx, edx
.r:     dec     ecx
        mov     r8b, [r9+rcx]
        mov     [rsi+rdx], r8b
        inc     edx
        test    ecx, ecx
        jnz     .r
        mov     byte [rsi+rdx], 0
        ret

; draw_num(edi x, esi y, rdx valor, ecx color, r8 font) -> eax x final
draw_num:
        push    rbx
        push    r12
        push    r13
        push    r14
        mov     ebx, edi
        mov     r12d, esi
        mov     r13d, ecx
        mov     r14, r8
        mov     rdi, rdx
        lea     rsi, [numbuf]
        call    fmt_num
        mov     edi, ebx
        mov     esi, r12d
        lea     rdx, [numbuf]
        mov     ecx, r13d
        mov     r8, r14
        call    draw_text
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

; draw_num_right(edi x_derecha, esi y, rdx valor, ecx color, r8 font)
draw_num_right:
        push    rbx
        push    r12
        push    r13
        push    r14
        mov     ebx, edi
        mov     r12d, esi
        mov     r13d, ecx
        mov     r14, r8
        mov     rdi, rdx
        lea     rsi, [numbuf]
        call    fmt_num
        imul    eax, [r14]
        sub     ebx, eax
        mov     edi, ebx
        mov     esi, r12d
        lea     rdx, [numbuf]
        mov     ecx, r13d
        mov     r8, r14
        call    draw_text
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

; draw_text_center(edi x, esi y, edx w, rcx str, r8d color, r9 font)
draw_text_center:
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15
        mov     ebx, edi
        mov     r12d, esi
        mov     r13d, edx
        mov     r14, rcx
        mov     r15d, r8d
        push    r9
        mov     rdx, r14
        mov     r8, r9
        call    text_width
        mov     edi, r13d
        sub     edi, eax
        sar     edi, 1
        add     edi, ebx
        mov     esi, r12d
        mov     rdx, r14
        mov     ecx, r15d
        pop     r8
        call    draw_text
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

; panel(edi x, esi y, edx w, ecx h) -- tarjeta con borde redondeado
panel:
        push    rbx
        push    r12
        push    r13
        push    r14
        mov     ebx, edi
        mov     r12d, esi
        mov     r13d, edx
        mov     r14d, ecx
        ROUND   ebx, r12d, r13d, r14d, 8, C_BORDER
        lea     edi, [rbx+1]
        lea     esi, [r12+1]
        lea     edx, [r13-2]
        lea     ecx, [r14-2]
        mov     r8d, 7
        mov     r9d, C_PANEL
        call    fill_round
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

; =============================================================================
;  Escena
; =============================================================================

; link_prog(edi = i) -> eax 0..1000
link_prog:
        movzx   eax, byte [run_state]
        test    eax, eax
        jz      .zero
        cmp     eax, 2
        je      .full
        mov     eax, [anim_t]
        imul    edx, edi, STAGE
        sub     eax, edx
        jle     .zero
        cmp     eax, STAGE
        jge     .full
        imul    eax, 1000
        xor     edx, edx
        mov     ecx, STAGE
        div     ecx
        ret
.zero:  xor     eax, eax
        ret
.full:  mov     eax, 1000
        ret

; comp_status(edi = j) -> eax 0 inactivo, 1 corriendo, 2 terminado
comp_status:
        movzx   eax, byte [run_state]
        test    eax, eax
        jz      .r
        cmp     eax, 2
        je      .r
        lea     ecx, [rdi+1]
        cmp     ecx, 4
        jbe     .e
        mov     ecx, 4
.e:     imul    ecx, STAGE                  ; fin
        lea     edx, [rdi-1]
        test    edx, edx
        jns     .s
        xor     edx, edx
.s:     imul    edx, STAGE                  ; inicio
        mov     r8d, [anim_t]
        mov     eax, 2
        cmp     r8d, ecx
        jge     .r
        mov     eax, 1
        cmp     r8d, edx
        jge     .r
        xor     eax, eax
.r:     ret

; link_target(edi = i) -> eax registros que atraviesan el flujo i
link_target:
        mov     eax, NREC
        test    edi, edi
        jz      .r
        mov     eax, [n_rows]
        cmp     edi, 3
        je      .r
        mov     eax, [n_filter]
.r:     ret

render:
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15

        ; fondo + cabecera
        RECT    0, 0, W, H, C_BG
        mov     edi, 0
        mov     esi, 0
        mov     edx, W
        mov     ecx, 58
        mov     r8d, 0x1c2b4d
        mov     r9d, 0x121622
        call    fill_vgrad
        RECT    0, 58, W, 1, C_BORDER
        TEXT    22, 9, t_title, 0xffffff, font_l
        TEXT    200, 21, t_subtitle, C_MUTED, font_s
        lea     rdx, [t_badge]
        lea     r8, [font_s]
        call    text_width
        mov     edi, W - 22
        sub     edi, eax
        TEXT    edi, 21, t_badge, 0x9fb4da, font_s

        ; ---------------------------------------------------------- grafo
        mov     edi, 16
        mov     esi, 72
        mov     edx, W - 32
        mov     ecx, 184
        call    panel
        TEXT    32, 80, t_graph, C_MUTED, font_s
        TEXT    84, 80, t_graphfile, C_DIM, font_s

        ; flujos (debajo de los componentes)
        xor     ebx, ebx
.links: cmp     ebx, 4
        jae     .comps
        mov     edi, ebx
        call    draw_link
        inc     ebx
        jmp     .links
.comps: xor     ebx, ebx
.cl:    cmp     ebx, 5
        jae     .controls
        mov     edi, ebx
        call    draw_component
        inc     ebx
        jmp     .cl

        ; ------------------------------------------------------- controles
.controls:
        xor     ebx, ebx
.bl:    cmp     ebx, NBTN
        jae     .thr
        mov     edi, ebx
        call    draw_button
        inc     ebx
        jmp     .bl
.thr:   TEXT    172, 277, t_filterlbl, C_MUTED, font_s
        ROUND   312, 268, 68, 36, 6, 0x0b0d12
        mov     eax, [thr]
        lea     rsi, [numbuf]
        mov     rdi, rax
        call    fmt_num
        mov     edi, 312
        mov     esi, 277
        mov     edx, 68
        lea     rcx, [numbuf]
        mov     r8d, C_YELLOW
        lea     r9, [font_s]
        call    draw_text_center
        call    draw_status

        ; ---------------------------------------------------- paneles inferiores
        call    draw_sql
        call    draw_results
        TEXT    16, 600, t_footer, C_DIM, font_s

        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

; draw_button(edi = indice)
draw_button:
        push    rbx
        push    r12
        mov     ebx, edi
        imul    r12d, edi, BTN_SIZE
        lea     r12, [buttons + r12]
        mov     eax, [r12+16]
        cmp     ebx, [hover]
        jne     .nohover
        mov     edi, eax
        mov     esi, 0xffffff
        mov     edx, 1
        mov     ecx, 5
        call    lerp_color
.nohover:
        mov     edi, [r12]
        mov     esi, [r12+4]
        mov     edx, [r12+8]
        mov     ecx, [r12+12]
        mov     r8d, 6
        mov     r9d, eax
        call    fill_round
        mov     edi, [r12]
        mov     esi, [r12+4]
        mov     eax, [r12+12]
        sub     eax, FONT_S_H
        sar     eax, 1
        add     esi, eax
        mov     edx, [r12+8]
        mov     rcx, [r12+24]
        mov     r8d, 0xffffff
        lea     r9, [font_s]
        call    draw_text_center
        pop     r12
        pop     rbx
        ret

; draw_status: texto de estado a la derecha de los botones
draw_status:
        push    rbx
        movzx   eax, byte [run_state]
        cmp     eax, 1
        je      .run
        cmp     eax, 2
        je      .ok
        TEXT    616, 266, t_st_idle1, C_TEXT, font_s
        mov     edi, 616
        mov     esi, 286
        mov     edx, NREC
        mov     ecx, C_MUTED
        lea     r8, [font_s]
        call    draw_num
        TEXT    eax, 286, t_st_idle2, C_MUTED, font_s
        jmp     .r
.run:   TEXT    616, 266, t_st_run1, C_YELLOW, font_s
        TEXT    616, 286, t_st_run2, C_MUTED, font_s
        jmp     .r
.ok:    TEXT    616, 266, t_st_ok1, C_GREEN, font_s
        mov     ebx, eax
        mov     rax, [pipe_ns]
        add     rax, 500
        xor     edx, edx
        mov     ecx, 1000
        div     rcx
        mov     rdx, rax
        mov     edi, ebx
        mov     esi, 266
        mov     ecx, C_GREEN
        lea     r8, [font_s]
        call    draw_num
        TEXT    eax, 266, t_us, C_GREEN, font_s
        TEXT    616, 286, t_st_ok2, C_DIM, font_s
.r:     pop     rbx
        ret

; draw_link(edi = i)
draw_link:
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15
        mov     ebx, edi
        imul    r12d, edi, GSTEP
        add     r12d, GX0 + BOXW            ; x inicio
        call    link_prog
        mov     r13d, eax                   ; permille
        ; color segun estado
        mov     r14d, C_LINK
        test    r13d, r13d
        jz      .col
        mov     r14d, C_YELLOW
        cmp     r13d, 1000
        jb      .col
        mov     r14d, C_GREEN
.col:   RECT    r12d, LINKY-1, GSTEP-BOXW, 3, r14d
        ; punta de flecha
        xor     r15d, r15d
.arrow: cmp     r15d, 6
        jae     .arrowdone
        lea     edi, [r12 + GSTEP - BOXW - 2]
        sub     edi, r15d
        mov     esi, LINKY
        sub     esi, r15d
        lea     ecx, [r15*2+1]
        mov     edx, 1
        mov     r8d, r14d
        call    fill_rect
        inc     r15d
        jmp     .arrow
.arrowdone:
        ; puertos
        mov     edi, r12d
        mov     esi, LINKY
        mov     edx, 4
        mov     ecx, r14d
        call    fill_circle
        ; registros en vuelo
        test    r13d, r13d
        jz      .label
        cmp     r13d, 1000
        jae     .label
        xor     r15d, r15d
.dots:  cmp     r15d, 3
        jae     .label
        mov     eax, [anim_t]
        shr     eax, 3
        imul    edx, r15d, 20
        add     eax, edx
        xor     edx, edx
        mov     ecx, GSTEP - BOXW - 10
        div     ecx
        lea     edi, [r12 + rdx + 4]
        mov     esi, LINKY
        mov     edx, 3
        mov     ecx, 0xfff3b0
        call    fill_circle
        inc     r15d
        jmp     .dots
.label: ; cantidad de registros sobre el flujo
        movzx   eax, byte [run_state]
        test    eax, eax
        jz      .out
        mov     edi, ebx
        call    link_target
        mov     eax, eax
        mov     ecx, r13d
        imul    rax, rcx
        xor     edx, edx
        mov     ecx, 1000
        div     rcx
        lea     rsi, [numbuf]
        mov     rdi, rax
        call    fmt_num
        lea     edi, [r12-4]
        mov     esi, LINKY - 24
        mov     edx, GSTEP - BOXW + 8
        lea     rcx, [numbuf]
        mov     r8d, r14d
        cmp     r13d, 0
        jne     .lc
        mov     r8d, C_DIM
.lc:    lea     r9, [font_s]
        call    draw_text_center
.out:   pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

; draw_component(edi = j)
draw_component:
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15
        mov     ebx, edi
        imul    r12d, edi, GSTEP
        add     r12d, GX0                   ; x
        call    comp_status
        mov     r15d, eax
        mov     r13d, C_DIM                 ; color de borde
        cmp     r15d, 1
        jne     .b2
        mov     r13d, C_YELLOW
.b2:    cmp     r15d, 2
        jne     .b3
        mov     r13d, C_GREEN
.b3:    ROUND   r12d, BOXY, BOXW, BOXH, 7, r13d
        lea     edi, [r12+2]
        mov     esi, BOXY+2
        mov     edx, BOXW-4
        mov     ecx, BOXH-4
        mov     r8d, 5
        mov     r9d, C_BOX
        call    fill_round
        mov     r14d, [comp_color + rbx*4]
        lea     edi, [r12+2]
        mov     esi, BOXY+2
        mov     edx, BOXW-4
        mov     ecx, 24
        mov     r8d, 5
        mov     r9d, r14d
        call    fill_round
        lea     edi, [r12+2]
        RECT    edi, BOXY+14, BOXW-4, 12, r14d
        ; nombre
        lea     edi, [r12+8]
        mov     rdx, [comp_name + rbx*8]
        mov     esi, BOXY+5
        mov     ecx, 0xffffff
        lea     r8, [font_s]
        call    draw_text
        ; luz de estado
        mov     ecx, 0x5a6170
        cmp     r15d, 1
        jne     .l2
        mov     ecx, C_YELLOW
.l2:    cmp     r15d, 2
        jne     .l3
        mov     ecx, C_GREEN
.l3:    lea     edi, [r12 + BOXW - 12]
        mov     esi, BOXY + 39
        mov     edx, 4
        call    fill_circle
        ; linea 1
        lea     edi, [r12+10]
        mov     esi, BOXY+32
        mov     rdx, [comp_l1 + rbx*8]
        mov     ecx, C_TEXT
        lea     r8, [font_s]
        call    draw_text
        cmp     ebx, 1                      ; FILTER: umbral dinamico
        jne     .l1done
        mov     edi, eax
        mov     esi, BOXY+32
        mov     edx, [thr]
        mov     ecx, C_YELLOW
        lea     r8, [font_s]
        call    draw_num
.l1done:
        ; linea 2
        mov     rdx, [comp_l2 + rbx*8]
        test    rdx, rdx
        jz      .dyn2
        lea     edi, [r12+10]
        mov     esi, BOXY+56
        mov     ecx, C_MUTED
        lea     r8, [font_s]
        call    draw_text
        jmp     .done
.dyn2:  cmp     ebx, 0
        jne     .d1
        lea     edi, [r12+10]
        mov     esi, BOXY+56
        mov     edx, NREC
        mov     ecx, C_MUTED
        lea     r8, [font_s]
        call    draw_num
        TEXT    eax, BOXY+56, c_b0, C_MUTED, font_s
        jmp     .done
.d1:    cmp     ebx, 1
        jne     .d4
        lea     edi, [r12+10]
        TEXT    edi, BOXY+56, c_b1, C_MUTED, font_s
        cmp     r15d, 2
        jne     .dash
        mov     edx, NREC
        sub     edx, [n_filter]
        mov     edi, eax
        mov     esi, BOXY+56
        mov     ecx, C_NUM
        lea     r8, [font_s]
        call    draw_num
        jmp     .done
.dash:  TEXT    eax, BOXY+56, c_dash, C_DIM, font_s
        jmp     .done
.d4:    lea     edi, [r12+10]
        cmp     r15d, 2
        jne     .dash4
        mov     esi, BOXY+56
        mov     edx, [n_rows]
        mov     ecx, C_MUTED
        lea     r8, [font_s]
        call    draw_num
        TEXT    eax, BOXY+56, c_b4, C_MUTED, font_s
        jmp     .done
.dash4: TEXT    edi, BOXY+56, c_dash, C_DIM, font_s
.done:  pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

; ---------------------------------------------------------------- panel SQL
%define SQX     32
%define SQY     (324 + 44)
%define SQLH    20
%macro SQ 4     ; columna, linea, texto, color
        TEXT    SQX + (%1)*FONT_S_W, SQY + (%2)*SQLH, %3, %4, font_s
%endmacro

draw_sql:
        mov     edi, 16
        mov     esi, 324
        mov     edx, 440
        mov     ecx, 268
        call    panel
        TEXT    32, 334, t_sqltitle, C_MUTED, font_s
        SQ      0, 0, q_select, C_KW
        SQ      7, 0, q_region_c, C_TEXT
        SQ      7, 1, q_count, C_FN
        SQ      12, 1, q_star, C_TEXT
        SQ      19, 1, q_as, C_KW
        SQ      22, 1, q_registros, C_TEXT
        SQ      7, 2, q_sum, C_FN
        SQ      10, 2, q_monto_p, C_TEXT
        SQ      19, 2, q_as, C_KW
        SQ      22, 2, q_total, C_TEXT
        SQ      7, 3, q_avg, C_FN
        SQ      10, 3, q_monto_p, C_TEXT
        SQ      19, 3, q_as, C_KW
        SQ      22, 3, q_promedio, C_TEXT
        SQ      0, 4, q_from, C_KW
        SQ      7, 4, q_ventas, C_TEXT
        SQ      0, 5, q_where, C_KW
        SQ      7, 5, q_monto_gt, C_TEXT
        mov     edi, SQX + 15*FONT_S_W
        mov     esi, SQY + 5*SQLH
        mov     edx, [thr]
        mov     ecx, C_NUM
        lea     r8, [font_s]
        call    draw_num
        SQ      0, 6, q_groupby, C_KW
        SQ      9, 6, q_region, C_TEXT
        SQ      0, 7, q_orderby, C_KW
        SQ      9, 7, q_region_s, C_TEXT
        SQ      0, 9, q_c1, C_CMT
        SQ      0, 10, q_c2, C_CMT
        ret

; ---------------------------------------------------------- panel resultado
%define RX      472
%define RY      324
%define RROW0   (RY + 74)
%define RROWH   24
%define BARX    (RX + 356)
%define BARW    96

draw_results:
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15
        mov     edi, RX
        mov     esi, RY
        mov     edx, W - 16 - RX
        mov     ecx, 268
        call    panel
        TEXT    RX+16, RY+10, t_restitle, C_MUTED, font_s

        ; factor de aparicion (0..1000)
        movzx   eax, byte [run_state]
        test    eax, eax
        jz      .empty
        mov     r15d, 1000
        cmp     eax, 2
        je      .show
        mov     eax, [anim_t]
        sub     eax, ANIM_LINKS_END
        jle     .processing
        imul    eax, 1000
        xor     edx, edx
        mov     ecx, ANIM_END - ANIM_LINKS_END
        div     ecx
        cmp     eax, 1000
        jbe     .f
        mov     eax, 1000
.f:     mov     r15d, eax
        jmp     .show
.processing:
        TEXT    RX+16, RY+120, t_processing, C_YELLOW, font_s
        jmp     .out
.empty: TEXT    RX+16, RY+110, t_empty1, C_TEXT, font_s
        TEXT    RX+16, RY+132, t_empty2, C_MUTED, font_s
        jmp     .out

.show:  ; encabezados
        TEXT    RX+16, RY+42, t_h_region, C_MUTED, font_s
        TEXT    RX+152, RY+42, t_h_regs, C_MUTED, font_s
        TEXT    RX+232, RY+42, t_h_total, C_MUTED, font_s
        TEXT    RX+304, RY+42, t_h_prom, C_MUTED, font_s
        RECT    RX+12, RY+66, W-16-RX-24, 1, C_BORDER

        ; maximo total para escalar barras
        xor     r14, r14
        xor     ecx, ecx
.mx:    cmp     ecx, [n_rows]
        jae     .mxdone
        mov     rax, [res_sum + rcx*8]
        cmp     rax, r14
        cmovg   r14, rax
        inc     ecx
        jmp     .mx
.mxdone:
        test    r14, r14
        jnz     .rows
        inc     r14

.rows:  xor     ebx, ebx
.row:   cmp     ebx, [n_rows]
        jae     .totals
        imul    r12d, ebx, RROWH
        add     r12d, RROW0                 ; y
        mov     r13d, [res_region + rbx*4]
        ; nombre de region
        mov     edi, RX+16
        mov     esi, r12d
        mov     rdx, [region_name + r13*8]
        mov     ecx, C_TEXT
        lea     r8, [font_s]
        call    draw_text
        ; REGS
        mov     edi, RX+184
        mov     esi, r12d
        mov     edx, [res_count + rbx*4]
        mov     ecx, C_TEXT
        lea     r8, [font_s]
        call    draw_num_right
        ; TOTAL
        mov     edi, RX+288
        mov     esi, r12d
        mov     rdx, [res_sum + rbx*8]
        mov     ecx, C_TEXT
        lea     r8, [font_s]
        call    draw_num_right
        ; PROM = sum / count
        mov     rax, [res_sum + rbx*8]
        mov     ecx, [res_count + rbx*4]
        xor     edx, edx
        div     rcx
        mov     rdx, rax
        mov     edi, RX+336
        mov     esi, r12d
        mov     ecx, C_NUM
        lea     r8, [font_s]
        call    draw_num_right
        ; barra
        RECT    BARX, r12d, BARW, 12, 0x232837
        mov     rax, [res_sum + rbx*8]
        imul    rax, rax, BARW
        xor     edx, edx
        div     r14
        mov     ecx, r15d
        imul    rax, rcx
        xor     edx, edx
        mov     ecx, 1000
        div     rcx
        mov     edx, eax
        test    edx, edx
        jz      .nobar
        mov     edi, BARX
        mov     esi, r12d
        mov     ecx, 12
        mov     r8d, [region_color + r13*4]
        call    fill_rect
.nobar: inc     ebx
        jmp     .row

.totals:
        mov     r12d, RY + 74 + 6*RROWH + 6
        RECT    RX+12, r12d, W-16-RX-24, 1, C_BORDER
        add     r12d, 8
        TEXT    RX+16, r12d, t_total, C_YELLOW, font_s
        mov     edi, RX+184
        mov     esi, r12d
        mov     edx, [n_filter]
        mov     ecx, C_YELLOW
        lea     r8, [font_s]
        call    draw_num_right
        xor     eax, eax
        xor     ecx, ecx
.ts:    cmp     ecx, [n_rows]
        jae     .tsd
        add     rax, [res_sum + rcx*8]
        inc     ecx
        jmp     .ts
.tsd:   mov     rdx, rax
        mov     edi, RX+288
        mov     esi, r12d
        mov     ecx, C_YELLOW
        lea     r8, [font_s]
        call    draw_num_right
.out:   pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

; ================================================================== FUENTES
section .rodata
align 16
font_s_data:    incbin "font_s.bin"
font_l_data:    incbin "font_l.bin"
