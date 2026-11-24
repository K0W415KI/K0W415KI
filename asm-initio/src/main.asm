; =============================================================================
;  ASM INITIO v2 -- un GDE de flujo de datos en x86-64 puro
; -----------------------------------------------------------------------------
;  * Cero dependencias: ni libc, ni Xlib, ni loader dinamico.
;  * Protocolo X11 a mano (auth, MIT-SHM, cursores, mapa de teclado).
;  * Render por software: antialias, curvas Bezier, alfa, sombras.
;  * Pipeline real de hasta 1.000.000 de registros:
;      INPUT -> FILTER -> SORT (counting) -> ROLLUP -> OUTPUT
;
;  nasm -f elf64 -I src/ src/main.asm -o build/asminitio.o
;  ld -s -o build/asminitio build/asminitio.o
; =============================================================================
bits 64

%include "fonts.inc"
%include "defs.inc"

section .text
global _start

_start:
        mov     rax, [rsp]
        lea     rbx, [rsp + rax*8 + 16]
        mov     [envp], rbx

        call    x11_init
        call    reset_layout
        call    gen_data
        call    now_ms
        mov     [now], rax
        mov     byte [dirty], 1

main_loop:
        call    now_ms
        mov     [now], rax

        ; animacion del grafo
        cmp     byte [run_state], 1
        jne     .noanim
        sub     rax, [anim_start]
        mov     [anim_t], eax
        mov     byte [dirty], 1
        cmp     eax, ANIM_END
        jb      .noanim
        mov     byte [run_state], 2
.noanim:
        ; toast con desvanecimiento
        mov     rax, [toast_until]
        cmp     rax, [now]
        jbe     .notoast
        mov     byte [dirty], 1
.notoast:
        ; cursor titilante del campo de texto
        cmp     byte [focus], 0
        je      .nocaret
        mov     rax, [now]
        xor     edx, edx
        mov     ecx, 530
        div     rcx
        and     eax, 1
        cmp     al, [caret_phase]
        je      .nocaret
        mov     [caret_phase], al
        mov     byte [dirty], 1
.nocaret:
        ; MIT-SHM: no pisar el buffer mientras el servidor lo lee
        cmp     byte [shm_pending], 0
        je      .draw
        mov     rax, [now]
        sub     rax, [pend_since]
        cmp     rax, 250
        jb      .poll                       ; esperar ShmCompletion
        mov     byte [shm_pending], 0
.draw:  cmp     byte [dirty], 0
        je      .poll
        mov     byte [dirty], 0
        call    render
        call    present

.poll:  mov     eax, [xfd]
        mov     [pollfd], eax
        mov     dword [pollfd+4], 1
        mov     edx, -1
        cmp     byte [focus], 0
        je      .t1
        mov     edx, 100
.t1:    cmp     byte [run_state], 1
        je      .fast
        cmp     byte [shm_pending], 0
        jne     .fast
        cmp     byte [dirty], 0
        jne     .fast
        mov     rax, [toast_until]
        cmp     rax, [now]
        jbe     .wait
.fast:  mov     edx, 16
.wait:  mov     eax, SYS_POLL
        lea     rdi, [pollfd]
        mov     esi, 1
        syscall
        test    eax, eax
        jle     main_loop
        movzx   eax, word [pollfd+6]
        test    eax, 1
        jnz     .readable
        test    eax, 0x18
        jnz     quit
        jmp     main_loop
.readable:
        call    read_events
        jmp     main_loop

quit:
        mov     eax, SYS_EXIT
        xor     edi, edi
        syscall

%include "x11.asm"
%include "gfx.asm"
%include "data.asm"
%include "ui.asm"

; ===================================================================== DATA
section .data

font_s:         dd FONT_S_W, FONT_S_H
                dq font_s_data
font_sb:        dd FONT_SB_W, FONT_SB_H
                dq font_sb_data
font_l:         dd FONT_L_W, FONT_L_H
                dq font_l_data

f_one:          dd 1.0
f_128:          dd 128.0
f_16:           dd 16.0
hexdigits:      db "0123456789ABCDEF"

; ---- X11
s_DISPLAY:      db "DISPLAY", 0
s_XAUTHORITY:   db "XAUTHORITY", 0
s_HOME:         db "HOME", 0
s_xauthfile:    db "/.Xauthority", 0
s_x11path:      db "/tmp/.X11-unix/X"
s_cookie:       db "MIT-MAGIC-COOKIE-1"
s_mitshm:       db "MIT-SHM", 0
s_wm_protocols: db "WM_PROTOCOLS"
s_wm_delete:    db "WM_DELETE_WINDOW"
s_net_wm_name:  db "_NET_WM_NAME"
s_utf8_string:  db "UTF8_STRING"
s_wm_name:      db "ASM Initio"
s_wm_name_len   equ $ - s_wm_name
s_net_title:    db "ASM Initio · grafo de datos en x86-64"
s_net_title_len equ $ - s_net_title
s_wm_class:     db "asminitio", 0, "AsmInitio", 0
s_wm_class_len  equ $ - s_wm_class
cursor_glyphs:  dw 68, 60, 52, 152          ; left_ptr, hand2, fleur, xterm

e_connect:      db "asminitio: no pude conectar al servidor X (DISPLAY?)", 10, 0
e_refused:      db "asminitio: el servidor X rechazo la conexion: ", 0
e_auth:         db "asminitio: el servidor X pide autenticacion adicional", 10, 0
e_io:           db "asminitio: error de E/S con el servidor X", 10, 0
e_visual:       db "asminitio: se necesita un visual TrueColor de 24/32 bits LSB", 10, 0
e_atom:         db "asminitio: error en InternAtom", 10, 0
e_mem:          db "asminitio: no pude reservar memoria", 10, 0
s_nl:           db 10, 0

; ---- dataset
r_0:    db "AMBA", 0
r_1:    db "PAMPEANA", 0
r_2:    db "CUYO", 0
r_3:    db "NOA", 0
r_4:    db "NEA", 0
r_5:    db "PATAGONIA", 0
region_name:    dq r_0, r_1, r_2, r_3, r_4, r_5
m_0:    db "ENE", 0
m_1:    db "FEB", 0
m_2:    db "MAR", 0
m_3:    db "ABR", 0
m_4:    db "MAY", 0
m_5:    db "JUN", 0
m_6:    db "JUL", 0
m_7:    db "AGO", 0
m_8:    db "SEP", 0
m_9:    db "OCT", 0
m_10:   db "NOV", 0
m_11:   db "DIC", 0
month_name:     dq m_0, m_1, m_2, m_3, m_4, m_5, m_6, m_7, m_8, m_9, m_10, m_11
k_0:    db "ONLINE", 0
k_1:    db "SUCURSAL", 0
k_2:    db "MAYORISTA", 0
canal_name:     dq k_0, k_1, k_2
region_weights: db 0,0,0,0,0, 1,1,1, 2,2, 3,3, 4,4, 5,5
canal_weights:  db 0,0,0,0,0,0,0,0, 1,1,1,1,1, 2,2,2
region_max:     dd 900, 800, 600, 450, 400, 1000
month_factor:   dd 70, 75, 90, 95, 100, 105, 115, 95, 100, 105, 120, 160
key_base:       dq rec_region, rec_mes, rec_canal
grp_tables:     dq region_name, month_name, canal_name
g_c0:   db "region", 0
g_c1:   db "mes", 0
g_c2:   db "canal", 0
grp_colnames:   dq g_c0, g_c1, g_c2
g_h0:   db "REGIÓN", 0
g_h1:   db "MES", 0
g_h2:   db "CANAL", 0
grp_headers:    dq g_h0, g_h1, g_h2
n_10k:  db "10K", 0
n_100k: db "100K", 0
n_1m:   db "1M", 0
nrec_labels:    dq n_10k, n_100k, n_1m
nrec_values:    dd 10000, 100000, 1000000
o_0:    db ">", 0
o_1:    db ">=", 0
o_2:    db "<", 0
o_3:    db "<=", 0
o_4:    db "=", 0
o_5:    db "!=", 0
op_names:       dq o_0, o_1, o_2, o_3, o_4, o_5
sc_0:   db "grupo", 0
sc_1:   db "registros", 0
sc_2:   db "total", 0
sc_3:   db "promedio", 0
sc_4:   db "minimo", 0
sc_5:   db "maximo", 0
sort_colnames:  dq sc_0, sc_1, sc_2, sc_3, sc_4, sc_5
sql_ordercols:  dq sc_0, sc_1, sc_2, sc_3, sc_4, sc_5
sl_0:   db "grupo", 0
sl_1:   db "regs", 0
sl_2:   db "total", 0
sl_3:   db "prom", 0
sl_4:   db "min", 0
sl_5:   db "max", 0
sort_labels:    dq sl_0, sl_1, sl_2, sl_3, sl_4, sl_5

csv_file:       db "resultado.csv", 0
csv_header:     db ",registros,total,promedio,minimo,maximo", 10, 0

; ---- componentes
c_n0:   db "INPUT FILE", 0
c_n1:   db "FILTER BY EXPR", 0
c_n2:   db "SORT", 0
c_n3:   db "ROLLUP", 0
c_n4:   db "OUTPUT TABLE", 0
comp_name:      dq c_n0, c_n1, c_n2, c_n3, c_n4, c_n4
comp_color:     dd 0x2f6fde, 0xb0569e, 0xd9822b, 0x2a9d8f, 0x5b6ee0
cd_0:   db "INPUT FILE · genera ventas.dat", 0
cd_1:   db "FILTER BY EXPRESSION · sin saltos", 0
cd_2:   db "SORT · counting sort por clave", 0
cd_3:   db "ROLLUP · agrega por grupo", 0
cd_4:   db "OUTPUT TABLE · ordena el resultado", 0
comp_desc:      dq cd_0, cd_1, cd_2, cd_3, cd_4
layout_y:       dd 60, 140, 60, 140, 60
c_a0:   db "ventas.dat", 0
c_b0:   db " regs", 0
c_b1:   db "reject: ", 0
c_b2:   db "counting sort", 0
c_b3:   db "5 agregados", 0
c_b4:   db " filas", 0
c_dash: db "-", 0
st_0:   db "inactivo", 0
st_1:   db "ejecutando", 0
st_2:   db "OK", 0
status_names:   dq st_0, st_1, st_2
sql_band_line:  dd 6, 7, 8, 0, 9
sql_band_n:     dd 1, 1, 1, 6, 1

; ---- estilos de botones
style_bg:       dd 0x2a3040, 0x2f9e5c, 0x3b5ba8, 0x34548f, 0x7a4fb0, 0x1d212c, 0x0b0d12, 0x0b0d12
style_fg:       dd C_TEXT, C_WHITE, C_WHITE, C_WHITE, C_WHITE, C_MUTED, C_YELLOW, C_WHITE
bar_colors:     dd 0x4e9af1, 0xf1a34e, 0x5bd18b, 0xe0607e, 0xb38cf0, 0x4fd1d9, 0xe8d56b, 0x9aa6bd

; ---- textos
t_title:        db "ASM INITIO", 0
t_subtitle:     db "grafo de datos en x86-64 puro", 0
t_putimage:     db "PutImage", 0
t_mitshm:       db "MIT-SHM", 0
t_nolibc:       db "sin libc", 0
t_zerodeps:     db "0 dependencias", 0
t_x8664:        db "x86-64", 0
t_run:          db "EJECUTAR (R)", 0
t_newdata:      db "DATOS NUEVOS (N)", 0
t_export:       db "EXPORTAR CSV (E)", 0
t_export_short: db "EXPORTAR CSV", 0
t_st_idle1:     db "Listo. Presioná EJECUTAR.", 0
t_st_idle2:     db " registros en memoria", 0
t_st_run1:      db "Ejecutando grafo...", 0
t_st_run2:      db "registros fluyendo por los flujos", 0
t_st_ok1:       db "OK · pipeline real: ", 0
t_us:           db " µs", 0
t_regs_arrow:   db " regs -> ", 0
t_groups:       db " grupos", 0
t_dot_sep:      db "  ·  ", 0
t_mregs:        db " M regs/s", 0
t_graph:        db "GRAFO", 0
t_graphfile:    db "ventas_por_region.mp", 0
t_canvas_hint:  db "arrastrá componentes · click en un flujo: ver datos · click derecho: menú", 0
t_inspector:    db "INSPECTOR", 0
t_regs:         db " regs", 0
t_k_in:         db "Entrada", 0
t_k_out:        db "Salida", 0
t_k_time:       db "Tiempo", 0
t_k_speed:      db "Velocidad", 0
t_not_run:      db "Ejecutá el grafo para ver métricas.", 0
t_props:        db "PROPIEDADES", 0
t_p_nrec:       db "Registros a generar", 0
t_p_seed:       db "seed xorshift32: 0x", 0
t_p_gen:        db "campos: region, mes, canal, monto", 0
t_p_expr:       db "Expresión: monto ", 0
t_minus:        db "-", 0
t_plus:         db "+", 0
t_field_hint:   db "click: tipear", 0
t_field_hint2:  db "Enter / Esc", 0
t_p_sortkey:    db "Clave de orden", 0
t_p_sortalg:    db "counting sort estable · O(n)", 0
t_p_sortsync:   db "clave sincronizada con ROLLUP", 0
t_p_groupby:    db "Agrupar por", 0
t_p_aggs:       db "COUNT · SUM · AVG · MIN · MAX", 0
t_p_sorted_ok:  db "entrada ordenada por clave: OK", 0
t_p_orderby:    db "Ordenar resultado por", 0
t_asc:          db "ASCENDENTE", 0
t_descl:        db "DESCENDENTE", 0
t_monto_sp:     db "monto ", 0
t_key:          db "key: ", 0
t_order:        db "order: ", 0
t_desc_short:   db " desc", 0
t_bullet:       db "·", 0
h_0:    db "Click en un componente: propiedades", 0
h_1:    db "Arrastrá componentes para moverlos", 0
h_2:    db "Click en un flujo: ver sus registros", 0
h_3:    db "Doble click: datos de salida", 0
h_4:    db "Click derecho: menú contextual", 0
h_5:    db "Rueda: umbral o scroll de tablas", 0
h_6:    db "Click en encabezados: ordenar", 0
h_7:    db "Tab / flechas: recorrer componentes", 0
h_8:    db "G clave · O operador · F umbral", 0
help_lines:     dq h_0, h_1, h_2, h_3, h_4, h_5, h_6, h_7, h_8
t_sqltitle:     db "SQL EQUIVALENTE", 0
t_sqldialects:  db "Oracle · BigQuery · MSSQL", 0
t_comma:        db ",", 0
t_semicolon:    db ";", 0
q_select:       db "SELECT", 0
q_count:        db "COUNT", 0
q_star:         db "(*)", 0
q_as:           db "AS", 0
q_registros:    db "registros,", 0
q_sum:          db "SUM", 0
q_avg:          db "AVG", 0
q_min:          db "MIN", 0
q_max:          db "MAX", 0
q_monto_p:      db "(monto)", 0
q_total:        db "total,", 0
q_promedio:     db "promedio,", 0
q_minimo:       db "minimo,", 0
q_maximo:       db "maximo", 0
q_from:         db "FROM", 0
q_ventas:       db "ventas", 0
q_where:        db "WHERE", 0
q_monto:        db "monto", 0
q_group:        db "GROUP", 0
q_order:        db "ORDER", 0
q_by:           db "BY", 0
q_desc:         db "DESC", 0
q_comment:      db "-- 0 motores SQL: todo corre en x86-64", 0
t_tab_res:      db "RESULTADO", 0
t_tab_view:     db "VER DATOS", 0
t_h_regs:       db "REGS", 0
t_h_total:      db "TOTAL $", 0
t_h_prom:       db "PROM", 0
t_h_min:        db "MIN", 0
t_h_max:        db "MAX", 0
t_total:        db "TOTAL", 0
t_empty1:       db "Sin resultados todavía.", 0
t_empty2:       db "Ejecutá el grafo con R o con el botón.", 0
t_processing:   db "procesando...", 0
t_flow:         db "FLUJO ", 0
t_colon_sp:     db ": ", 0
t_arrow:        db " -> ", 0
t_view_norun:   db "Ejecutá el grafo para ver este flujo.", 0
t_v_idx:        db "#", 0
t_v_reg:        db "REGIÓN", 0
t_v_mes:        db "MES", 0
t_v_canal:      db "CANAL", 0
t_v_monto:      db "MONTO", 0
t_rows_lbl:     db "filas ", 0
t_of:           db " de ", 0
t_scroll_hint:  db "  ·  rueda / PgUp / PgDn", 0
t_footer:       db "R ejecutar · N datos · E exportar · G clave · O operador · F umbral · V ver datos · Tab · Esc/Q salir", 0
t_frame:        db "frame ", 0
t_ms_sep:       db " ms · ", 0
t_tt_norun:     db "sin ejecutar todavía", 0
t_tt_comp_hint: db "click: propiedades · arrastrar: mover", 0
t_tt_link_hint: db "click: ver los registros del flujo", 0
t_exported:     db "Exportado resultado.csv · ", 0
t_rows_suffix:  db " filas", 0
t_export_fail:  db "No pude escribir resultado.csv", 0
ci_0:   db "Propiedades", 0
ci_1:   db "Ver datos de entrada", 0
ci_2:   db "Ver datos de salida", 0
ci_3:   db "Reiniciar diseño del grafo", 0
ctx_items:      dq ci_0, ci_1, ci_2, ci_3

; ---- estado inicial
seed:           dd 0x2545F491
nrec:           dd 100000
nrec_sel:       dd 1
thr:            dd 300
filt_op:        dd 0
group_key:      dd 0
sort_col:       dd 0
sel:            dd -1
last_click_c:   dd -1
sort_desc:      db 0

; ====================================================================== BSS
section .bss
alignb 8
envp:           resq 1
now:            resq 1
frame_ns:       resq 1
anim_start:     resq 1
pipe_ns:        resq 1
gen_ns:         resq 1
comp_ns:        resq 5
toast_until:    resq 1
pend_since:     resq 1
auth_ptr:       resq 1
fbp:            resq 1
maskp:          resq 1
timespec:       resq 2
xfd:            resd 1
id_base:        resd 1
root:           resd 1
root_w:         resd 1
root_h:         resd 1
depth:          resd 1
maxreq:         resd 1
min_kc:         resd 1
max_kc:         resd 1
kpk:            resd 1
wid:            resd 1
gc:             resd 1
atom_protocols: resd 1
atom_delete:    resd 1
atom_net_name:  resd 1
atom_utf8:      resd 1
dispnum_len:    resd 1
max_w:          resd 1
max_h:          resd 1
scr_w:          resd 1
scr_h:          resd 1
shm_major:      resd 1
shm_event:      resd 1
shmid:          resd 1
shmseg:         resd 1
cursor_font:    resd 1
cursors:        resd 4
cur_cursor:     resd 1
evlen:          resd 1
sb_len:         resd 1
anim_t:         resd 1
can_w:          resd 1
bot_h:          resd 1
out_w:          resd 1
nhits:          resd 1
hover_act:      resd 1
hover_par:      resd 1
mouse_x:        resd 1
mouse_y:        resd 1
drag_kind:      resd 1
drag_comp:      resd 1
drag_dx:        resd 1
drag_dy:        resd 1
last_click_t:   resd 1
ctx_x:          resd 1
ctx_y:          resd 1
ctx_comp:       resd 1
ctx_iy:         resd 1
ctx_icol:       resd 1
ctx_ipar:       resd 1
input_len:      resd 1
view_link:      resd 1
view_scroll:    resd 1
view_rows:      resd 1
res_scroll:     resd 1
res_rows:       resd 1
sb_track_y:     resd 1
sb_track_h:     resd 1
toast_color:    resd 1
toast_y:        resd 1
bt_param:       resd 1
bt_style:       resd 1
seg_sel:        resd 1
seg_action:     resd 1
seed0:          resd 1
n_filter:       resd 1
n_rows:         resd 1
comp_x:         resd 5
comp_y:         resd 5
cnt:            resd 16
pos:            resd 16
res_key:        resd MAXGRP
res_count:      resd MAXGRP
res_min:        resd MAXGRP
res_max:        resd MAXGRP
res_avg:        resd MAXGRP
res_order:      resd MAXGRP
alignb 8
res_sum:        resq MAXGRP
link_pts:       resd 4*8
pollfd:         resb 8
dirty:          resb 1
run_state:      resb 1
use_shm:        resb 1
shm_pending:    resb 1
ctx_open:       resb 1
focus:          resb 1
input_fresh:    resb 1
out_tab:        resb 1
caret_phase:    resb 1
input_buf:      resb 16
dispnum:        resb 16
numbuf:         resb 32
numtmp:         resb 32
sbnum:          resb 32
sb_buf:         resb 256
toast_buf:      resb 128
tt_l1:          resb 96
tt_l2:          resb 96
tt_l3:          resb 96
sockaddr:       resb 112
pathbuf:        resb 512
req:            resb 512
rep32:          resb 64
alignb 64
hits:           resb 32*MAXHITS
evbuf:          resb 16384
csvbuf:         resb 4096
authbuf:        resb 65536
kmbuf:          resb 65536
setupbuf:       resb 262144
rec_region:     resb NMAX
rec_mes:        resb NMAX
rec_canal:      resb NMAX
alignb 64
rec_monto:      resd NMAX
f_idx:          resd NMAX + 1
s_idx:          resd NMAX

; ================================================================== FUENTES
section .rodata
align 16
font_s_data:    incbin "font_s.bin"
font_sb_data:   incbin "font_sb.bin"
font_l_data:    incbin "font_l.bin"
