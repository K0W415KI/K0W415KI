; =============================================================================
;  ui.asm -- interfaz "modo inmediato": cada frame se dibuja todo y se
;  registran las zonas clickeables; los eventos se resuelven contra la
;  lista del ultimo frame.
; =============================================================================
section .text

; -----------------------------------------------------------------------------
;  Hit testing
; -----------------------------------------------------------------------------
; add_hit(edi x, esi y, edx w, ecx h, r8d accion, r9d parametro)
add_hit:
        mov     eax, [nhits]
        cmp     eax, MAXHITS
        jae     .r
        shl     eax, 5
        lea     rax, [hits + rax]
        mov     [rax], edi
        mov     [rax+4], esi
        mov     [rax+8], edx
        mov     [rax+12], ecx
        mov     [rax+16], r8d
        mov     [rax+20], r9d
        inc     dword [nhits]
.r:     ret

; hit_find(edi x, esi y) -> eax indice (el ultimo registrado gana) o -1
hit_find:
        mov     ecx, [nhits]
.lp:    dec     ecx
        js      .none
        mov     eax, ecx
        shl     eax, 5
        lea     r8, [hits + rax]
        mov     eax, edi
        sub     eax, [r8]
        js      .lp
        cmp     eax, [r8+8]
        jge     .lp
        mov     eax, esi
        sub     eax, [r8+4]
        js      .lp
        cmp     eax, [r8+12]
        jge     .lp
        mov     eax, ecx
        ret
.none:  mov     eax, -1
        ret

; link_hit(edi x, esi y) -> eax flujo bajo el puntero o -1
link_hit:
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15
        mov     r12d, edi
        mov     r13d, esi
        xor     ebx, ebx
.li:    cmp     ebx, 4
        jae     .none
        xor     r14d, r14d
.k:     cmp     r14d, 1024
        ja      .nl
        mov     edi, r14d
        mov     eax, ebx
        shl     eax, 5
        lea     rsi, [link_pts + rax]
        call    bez_point
        sar     eax, 4
        sar     edx, 4
        mov     r15d, edx
        sub     eax, r12d
        cmp     eax, -8
        jl      .nk
        cmp     eax, 8
        jg      .nk
        mov     eax, r15d
        sub     eax, r13d
        cmp     eax, -8
        jl      .nk
        cmp     eax, 8
        jg      .nk
        mov     eax, ebx
        jmp     .out
.nk:    add     r14d, 32
        jmp     .k
.nl:    inc     ebx
        jmp     .li
.none:  mov     eax, -1
.out:   pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

; pick(edi x, esi y) -> eax accion, edx parametro
pick:
        push    rbx
        push    r12
        push    r13
        mov     r12d, edi
        mov     r13d, esi
        call    hit_find
        test    eax, eax
        js      .none
        shl     eax, 5
        mov     ebx, [hits + rax + 16]
        mov     r8d, [hits + rax + 20]
        cmp     ebx, A_CANVAS
        jne     .ret
        mov     edi, r12d
        mov     esi, r13d
        call    link_hit
        test    eax, eax
        js      .canv
        mov     r8d, eax
        mov     ebx, A_LINK
        jmp     .ret
.canv:  xor     r8d, r8d
.ret:   mov     eax, ebx
        mov     edx, r8d
        pop     r13
        pop     r12
        pop     rbx
        ret
.none:  xor     eax, eax
        xor     edx, edx
        pop     r13
        pop     r12
        pop     rbx
        ret

; is_hover(edi accion, esi parametro) -> ZF=1 si es el elemento bajo el mouse
is_hover:
        cmp     edi, [hover_act]
        jne     .r
        cmp     esi, [hover_par]
.r:     ret

; -----------------------------------------------------------------------------
;  Estado de la animacion
; -----------------------------------------------------------------------------
link_prog:                                  ; edi = i -> eax 0..1000
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

comp_status:                                ; edi = j -> 0 inactivo, 1 corre, 2 ok
        movzx   eax, byte [run_state]
        test    eax, eax
        jz      .r
        cmp     eax, 2
        je      .r
        lea     ecx, [rdi+1]
        cmp     ecx, 4
        jbe     .e
        mov     ecx, 4
.e:     imul    ecx, STAGE
        lea     edx, [rdi-1]
        test    edx, edx
        jns     .s
        xor     edx, edx
.s:     imul    edx, STAGE
        mov     r8d, [anim_t]
        mov     eax, 2
        cmp     r8d, ecx
        jge     .r
        mov     eax, 1
        cmp     r8d, edx
        jge     .r
        xor     eax, eax
.r:     ret

link_target:                                ; edi = i -> eax registros del flujo
        mov     eax, [nrec]
        test    edi, edi
        jz      .r
        mov     eax, [n_rows]
        cmp     edi, 3
        je      .r
        mov     eax, [n_filter]
.r:     ret

comp_in:                                    ; edi = j -> eax
        mov     eax, [nrec]
        cmp     edi, 1
        jbe     .r
        mov     eax, [n_filter]
        cmp     edi, 3
        jbe     .r
        mov     eax, [n_rows]
.r:     ret

comp_out:                                   ; edi = j -> eax
        mov     eax, [nrec]
        test    edi, edi
        jz      .r
        mov     eax, [n_filter]
        cmp     edi, 2
        jbe     .r
        mov     eax, [n_rows]
.r:     ret

; -----------------------------------------------------------------------------
;  Acciones
; -----------------------------------------------------------------------------
action_run:
        call    run_pipeline
        mov     rax, [now]
        mov     [anim_start], rax
        mov     dword [anim_t], 0
        mov     byte [run_state], 1
        mov     byte [dirty], 1
        ret

action_new:
        cmp     byte [src_mode], 0
        jne     .reload
        rdtsc
        or      eax, 1
        mov     [seed], eax
        call    gen_data
        jmp     action_run
.reload:
        call    load_source
        test    rax, rax
        jz      action_run
        mov     rsi, rax
        mov     edi, C_RED
        jmp     show_toast

params_changed:
        mov     byte [dirty], 1
        cmp     byte [run_state], 0
        je      .r
        call    run_pipeline
.r:     ret

thr_up:
        mov     eax, [thr]
        add     eax, THR_STEP
        cmp     eax, THR_MAX
        jle     .ok
        mov     eax, THR_MAX
.ok:    mov     [thr], eax
        jmp     params_changed

thr_down:
        mov     eax, [thr]
        sub     eax, THR_STEP
        jns     .ok
        xor     eax, eax
.ok:    mov     [thr], eax
        jmp     params_changed

reset_layout:
        push    rbx
        mov     eax, [scr_w]
        sub     eax, 32 + 56 + BOXW
        xor     edx, edx
        mov     ecx, 4
        div     ecx
        mov     r8d, eax                    ; paso
        xor     ebx, ebx
.lp:    cmp     ebx, 5
        jae     .done
        mov     eax, r8d
        imul    eax, ebx
        add     eax, 28
        mov     [comp_x + rbx*4], eax
        mov     eax, [layout_y + rbx*4]
        mov     [comp_y + rbx*4], eax
        inc     ebx
        jmp     .lp
.done:  mov     byte [dirty], 1
        pop     rbx
        ret

; clamp_comps: mantiene los componentes dentro del lienzo
clamp_comps:
        mov     ecx, [scr_w]
        sub     ecx, 32 + BOXW + 8
        xor     edx, edx
.lp:    cmp     edx, 5
        jae     .r
        mov     eax, [comp_x + rdx*4]
        cmp     eax, ecx
        jle     .a
        mov     eax, ecx
.a:     cmp     eax, 8
        jge     .b
        mov     eax, 8
.b:     mov     [comp_x + rdx*4], eax
        mov     eax, [comp_y + rdx*4]
        cmp     eax, CAN_H - BOXH - 8
        jle     .c
        mov     eax, CAN_H - BOXH - 8
.c:     cmp     eax, 34
        jge     .d
        mov     eax, 34
.d:     mov     [comp_y + rdx*4], eax
        inc     edx
        jmp     .lp
.r:     ret

; open_viewer(edi = flujo)
open_viewer:
        mov     [view_link], edi
        mov     byte [out_tab], 1
        mov     dword [view_scroll], 0
        mov     byte [dirty], 1
        ret

; show_toast(rsi = texto, edi = color)
show_toast:
        mov     [toast_color], edi
        lea     rdi, [toast_buf]
        mov     edx, 120
        call    copy_z
        mov     rax, [now]
        add     rax, 2600
        mov     [toast_until], rax
        mov     byte [dirty], 1
        ret

; focus_field: empieza a editar el umbral
focus_field:
        mov     byte [focus], 1
        mov     byte [input_fresh], 1
        mov     edi, [thr]
        lea     rsi, [input_buf]
        xor     edx, edx
        call    fmt_num_sep
        mov     [input_len], eax
        mov     byte [dirty], 1
        ret

commit_input:
        mov     byte [focus], 0
        xor     eax, eax
        xor     ecx, ecx
.lp:    cmp     ecx, [input_len]
        jae     .done
        imul    eax, 10
        movzx   edx, byte [input_buf + rcx]
        sub     edx, '0'
        add     eax, edx
        inc     ecx
        jmp     .lp
.done:  cmp     eax, THR_MAX
        jle     .ok
        mov     eax, THR_MAX
.ok:    mov     [thr], eax
        jmp     params_changed

; scroll_view(edi = delta en filas)
scroll_view:
        cmp     byte [out_tab], 1
        jne     .res
        mov     eax, [view_scroll]
        add     eax, edi
        mov     edi, [view_link]
        push    rax
        call    view_count
        mov     ecx, eax
        pop     rax
        sub     ecx, [view_rows]
        jns     .c1
        xor     ecx, ecx
.c1:    cmp     eax, ecx
        jle     .c2
        mov     eax, ecx
.c2:    test    eax, eax
        jns     .c3
        xor     eax, eax
.c3:    mov     [view_scroll], eax
        mov     byte [dirty], 1
        ret
.res:   mov     eax, [res_scroll]
        add     eax, edi
        mov     ecx, [n_rows]
        sub     ecx, [res_rows]
        jns     .r1
        xor     ecx, ecx
.r1:    cmp     eax, ecx
        jle     .r2
        mov     eax, ecx
.r2:    test    eax, eax
        jns     .r3
        xor     eax, eax
.r3:    mov     [res_scroll], eax
        mov     byte [dirty], 1
        ret

; view_count(edi = flujo) -> eax registros visibles en el visor
view_count:
        xor     eax, eax
        test    edi, edi
        jz      link_target
        cmp     byte [run_state], 0
        je      .r
        jmp     link_target
.r:     ret

; scroll_to(esi = y del mouse) -- arrastre de la barra de desplazamiento
scroll_to:
        push    rbx
        mov     edi, [view_link]
        call    view_count
        mov     ebx, eax
        sub     ebx, [view_rows]
        jle     .zero
        mov     eax, esi
        sub     eax, [sb_track_y]
        jns     .a
        xor     eax, eax
.a:     cmp     eax, [sb_track_h]
        jle     .b
        mov     eax, [sb_track_h]
.b:     imul    rax, rbx
        mov     ecx, [sb_track_h]
        test    ecx, ecx
        jz      .zero
        xor     edx, edx
        div     rcx
        mov     [view_scroll], eax
        mov     byte [dirty], 1
        pop     rbx
        ret
.zero:  mov     dword [view_scroll], 0
        pop     rbx
        ret

; -----------------------------------------------------------------------------
;  Eventos
; -----------------------------------------------------------------------------
; ui_event(rdi = evento de 32 bytes)
ui_event:
        movzx   eax, byte [rdi]
        and     eax, 0x7f
        mov     ecx, [shm_event]
        test    ecx, ecx
        jz      .noshm
        cmp     eax, ecx
        jne     .noshm
        mov     byte [shm_pending], 0
        ret
.noshm: cmp     eax, 12
        je      .expose
        cmp     eax, 22
        je      .configure
        cmp     eax, 2
        je      .key
        cmp     eax, 4
        je      .press
        cmp     eax, 5
        je      .release
        cmp     eax, 6
        je      .motion
        cmp     eax, 33
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
.configure:
        movzx   eax, word [rdi+20]
        movzx   ecx, word [rdi+22]
        cmp     eax, [max_w]
        jbe     .w
        mov     eax, [max_w]
.w:     cmp     ecx, [max_h]
        jbe     .h
        mov     ecx, [max_h]
.h:     cmp     eax, [scr_w]
        jne     .chg
        cmp     ecx, [scr_h]
        je      .r
.chg:   mov     [scr_w], eax
        mov     [scr_h], ecx
        call    clamp_comps
        mov     byte [dirty], 1
.r:     ret
.key:   movzx   esi, word [rdi+28]
        movzx   edi, byte [rdi+1]
        jmp     on_key
.press: movzx   eax, byte [rdi+1]
        movsx   esi, word [rdi+24]
        movsx   edx, word [rdi+26]
        mov     ecx, [rdi+4]
        mov     edi, eax
        jmp     on_press
.release:
        mov     dword [drag_kind], 0
        movsx   esi, word [rdi+26]
        movsx   edi, word [rdi+24]
        jmp     on_motion
.motion:
        movsx   esi, word [rdi+26]
        movsx   edi, word [rdi+24]
        jmp     on_motion

; on_motion(edi x, esi y)
on_motion:
        push    rbx
        mov     [mouse_x], edi
        mov     [mouse_y], esi
        mov     eax, [drag_kind]
        cmp     eax, 1
        je      .dragcomp
        cmp     eax, 2
        je      .dragscroll
        call    pick
        cmp     eax, [hover_act]
        jne     .chg
        cmp     edx, [hover_par]
        je      .same
.chg:   mov     [hover_act], eax
        mov     [hover_par], edx
        mov     byte [dirty], 1
.same:  ; tooltips siguen al mouse
        cmp     eax, A_COMP
        je      .tt
        cmp     eax, A_LINK
        jne     .cur
.tt:    mov     byte [dirty], 1
.cur:   mov     edi, CUR_ARROW
        cmp     eax, A_CANVAS
        je      .setc
        cmp     eax, A_VIEWER
        je      .setc
        cmp     eax, A_NONE
        je      .setc
        mov     edi, CUR_TEXT
        cmp     eax, A_THR_FIELD
        je      .setc
        mov     edi, CUR_MOVE
        cmp     eax, A_COMP
        je      .setc
        mov     edi, CUR_HAND
.setc:  call    set_cursor
        pop     rbx
        ret
.dragcomp:
        mov     ebx, [drag_comp]
        mov     eax, [mouse_x]
        sub     eax, CAN_X
        sub     eax, [drag_dx]
        mov     [comp_x + rbx*4], eax
        mov     eax, [mouse_y]
        sub     eax, CAN_Y
        sub     eax, [drag_dy]
        mov     [comp_y + rbx*4], eax
        call    clamp_comps
        mov     byte [dirty], 1
        pop     rbx
        ret
.dragscroll:
        call    scroll_to
        pop     rbx
        ret

; on_press(edi boton, esi x, edx y, ecx tiempo)
on_press:
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15
        mov     ebx, edi
        mov     [mouse_x], esi
        mov     [mouse_y], edx
        mov     r14d, ecx
        mov     edi, esi
        mov     esi, edx
        call    pick
        mov     r12d, eax                   ; accion
        mov     r13d, edx                   ; parametro
        mov     byte [dirty], 1

        ; menu contextual abierto: elegir o cerrar
        cmp     byte [ctx_open], 0
        je      .noctx
        mov     byte [ctx_open], 0
        cmp     r12d, A_CTX
        jne     .out
        test    r13d, r13d
        js      .out
        mov     edi, r13d
        call    ctx_do
        jmp     .out
.noctx:
        ; rueda
        cmp     ebx, 4
        je      .wheel_up
        cmp     ebx, 5
        je      .wheel_dn
        ; si se estaba editando y se clickea afuera: confirmar
        cmp     byte [focus], 0
        je      .nofocus
        cmp     r12d, A_THR_FIELD
        je      .nofocus
        call    commit_input
.nofocus:
        cmp     ebx, 3
        je      .right
        cmp     ebx, 1
        jne     .out
        mov     eax, r12d
        cmp     eax, A_COUNT
        jae     .out
        jmp     [.tab + rax*8]
.tab:   dq      .a_none, .a_run, .a_new, .a_export, .a_nrec, .a_op
        dq      .a_thrdec, .a_thrinc, .a_field, .a_group, .a_sortcol
        dq      .a_sortdir, .a_comp, .a_link, .a_tab, .out, .a_none
        dq      .out, .a_scroll, .a_reset, .a_rmode, .a_reload

.a_none:
        mov     dword [sel], -1
        jmp     .out
.a_run: call    action_run
        jmp     .out
.a_new: call    action_new
        jmp     .out
.a_export:
        call    export_csv
        jmp     .out
.a_nrec:
        mov     [nrec_sel], r13d
        mov     eax, [nrec_values + r13*4]
        mov     [nrec], eax
        call    gen_data
        cmp     byte [run_state], 0
        je      .out
        call    action_run
        jmp     .out
.a_op:  mov     [filt_op], r13d
        call    params_changed
        jmp     .out
.a_thrdec:
        call    thr_down
        jmp     .out
.a_thrinc:
        call    thr_up
        jmp     .out
.a_field:
        call    focus_field
        jmp     .out
.a_group:
        mov     [group_key], r13d
        mov     dword [res_scroll], 0
        call    params_changed
        jmp     .out
.a_sortcol:
        cmp     r13d, [sort_col]
        jne     .newcol
        xor     byte [sort_desc], 1
        jmp     .resort
.newcol:
        mov     [sort_col], r13d
        xor     eax, eax
        test    r13d, r13d
        setnz   al                          ; numericas: descendente por defecto
        mov     [sort_desc], al
.resort:
        call    sort_results
        jmp     .out
.a_sortdir:
        xor     byte [sort_desc], 1
        call    sort_results
        jmp     .out
.a_comp:
        mov     [sel], r13d
        ; doble click -> ver datos de salida
        cmp     r13d, [last_click_c]
        jne     .single
        mov     eax, r14d
        sub     eax, [last_click_t]
        cmp     eax, 400
        ja      .single
        mov     dword [last_click_c], -1
        mov     edi, r13d
        cmp     edi, 3
        jbe     .dv
        mov     edi, 3
.dv:    call    open_viewer
        jmp     .out
.single:
        mov     [last_click_c], r13d
        mov     [last_click_t], r14d
        mov     dword [drag_kind], 1
        mov     [drag_comp], r13d
        mov     eax, [mouse_x]
        sub     eax, CAN_X
        sub     eax, [comp_x + r13*4]
        mov     [drag_dx], eax
        mov     eax, [mouse_y]
        sub     eax, CAN_Y
        sub     eax, [comp_y + r13*4]
        mov     [drag_dy], eax
        mov     edi, CUR_MOVE
        call    set_cursor
        jmp     .out
.a_link:
        mov     edi, r13d
        call    open_viewer
        jmp     .out
.a_tab: mov     [out_tab], r13b
        jmp     .out
.a_scroll:
        mov     dword [drag_kind], 2
        mov     esi, [mouse_y]
        call    scroll_to
        jmp     .out
.a_reset:
        call    reset_layout
        jmp     .out
.a_rmode:
        mov     [rmode], r13b
        call    params_changed
        jmp     .out
.a_reload:
        call    action_new
        jmp     .out

.right: cmp     r12d, A_COMP
        jne     .out
        mov     [sel], r13d
        mov     [ctx_comp], r13d
        mov     eax, [mouse_x]
        mov     [ctx_x], eax
        mov     eax, [mouse_y]
        mov     [ctx_y], eax
        mov     byte [ctx_open], 1
        jmp     .out

.wheel_up:
        mov     edi, -3
        jmp     .wheel
.wheel_dn:
        mov     edi, 3
.wheel: cmp     r12d, A_VIEWER
        je      .wscroll
        cmp     r12d, A_SCROLL
        je      .wscroll
        cmp     r12d, A_SORTCOL
        je      .wscroll
        test    edi, edi                    ; resto: umbral
        js      .wu
        call    thr_down
        jmp     .out
.wu:    call    thr_up
        jmp     .out
.wscroll:
        cmp     byte [out_tab], 1
        je      .ws
        sar     edi, 1                      ; resultado: de a 1 fila
        jnz     .ws
        mov     edi, 1
.ws:    call    scroll_view
.out:   pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

; ctx_do(edi = item del menu contextual)
ctx_do:
        cmp     edi, 1
        je      .in
        cmp     edi, 2
        je      .outp
        cmp     edi, 3
        je      reset_layout
        ret                                 ; 0: propiedades (ya seleccionado)
.in:    mov     edi, [ctx_comp]
        dec     edi
        js      .r
        jmp     open_viewer
.outp:  mov     edi, [ctx_comp]
        cmp     edi, 3
        jbe     .o
        mov     edi, 3
.o:     jmp     open_viewer
.r:     ret

; on_key(edi keycode, esi state)
on_key:
        call    keysym_of
        mov     byte [dirty], 1
        cmp     byte [focus], 0
        jne     .edit
        cmp     eax, 'q'
        je      quit
        cmp     eax, 'Q'
        je      quit
        cmp     eax, 0xff1b                 ; Escape
        je      .esc
        cmp     eax, 'r'
        je      action_run
        cmp     eax, 'R'
        je      action_run
        cmp     eax, 0xff0d                 ; Return
        je      action_run
        cmp     eax, 0xff8d                 ; KP_Enter
        je      action_run
        cmp     eax, ' '
        je      action_run
        cmp     eax, 'n'
        je      action_new
        cmp     eax, 'N'
        je      action_new
        cmp     eax, 'e'
        je      export_csv
        cmp     eax, 'E'
        je      export_csv
        cmp     eax, '+'
        je      thr_up
        cmp     eax, '='
        je      thr_up
        cmp     eax, 0xffab                 ; KP_Add
        je      thr_up
        cmp     eax, '-'
        je      thr_down
        cmp     eax, 0xffad                 ; KP_Subtract
        je      thr_down
        cmp     eax, 'g'
        je      .group
        cmp     eax, 'G'
        je      .group
        cmp     eax, 'o'
        je      .op
        cmp     eax, 'O'
        je      .op
        cmp     eax, 'v'
        je      .view
        cmp     eax, 'V'
        je      .view
        cmp     eax, 'f'
        je      focus_field
        cmp     eax, 'F'
        je      focus_field
        cmp     eax, '1'
        jb      .nonum
        cmp     eax, '5'
        jbe     .nrec
.nonum: cmp     eax, 0xff09                 ; Tab
        je      .next
        cmp     eax, 0xff53                 ; Right
        je      .next
        cmp     eax, 0xff51                 ; Left
        je      .prev
        cmp     eax, 0xff52                 ; Up
        je      .up
        cmp     eax, 0xff54                 ; Down
        je      .down
        cmp     eax, 0xff55                 ; Page_Up
        je      .pgup
        cmp     eax, 0xff56                 ; Page_Down
        je      .pgdn
        cmp     eax, 0xff50                 ; Home
        je      .home
        cmp     eax, 0xff57                 ; End
        je      .end
        ret
.esc:   cmp     byte [ctx_open], 0
        je      .e1
        mov     byte [ctx_open], 0
        ret
.e1:    cmp     dword [sel], 0
        jl      .e2
        mov     dword [sel], -1
        ret
.e2:    cmp     byte [out_tab], 0
        je      quit
        mov     byte [out_tab], 0
        ret
.group: mov     eax, [group_key]
        inc     eax
        cmp     eax, 3
        jb      .g
        xor     eax, eax
.g:     mov     [group_key], eax
        mov     dword [res_scroll], 0
        jmp     params_changed
.op:    mov     eax, [filt_op]
        inc     eax
        cmp     eax, 6
        jb      .o
        xor     eax, eax
.o:     mov     [filt_op], eax
        jmp     params_changed
.view:  mov     edi, [sel]
        test    edi, edi
        jns     .v1
        xor     edi, edi
.v1:    cmp     edi, 3
        jbe     .v2
        mov     edi, 3
.v2:    jmp     open_viewer
.nrec:  cmp     byte [src_mode], 0
        jne     .r
        sub     eax, '1'
        mov     [nrec_sel], eax
        mov     eax, [nrec_values + rax*4]
        mov     [nrec], eax
        call    gen_data
        cmp     byte [run_state], 0
        je      .r
        jmp     action_run
.next:  mov     eax, [sel]
        inc     eax
        cmp     eax, 5
        jb      .n1
        xor     eax, eax
.n1:    mov     [sel], eax
        ret
.prev:  mov     eax, [sel]
        dec     eax
        jns     .p1
        mov     eax, 4
.p1:    mov     [sel], eax
        ret
.up:    mov     edi, -1
        jmp     scroll_view
.down:  mov     edi, 1
        jmp     scroll_view
.pgup:  mov     edi, [view_rows]
        neg     edi
        jmp     scroll_view
.pgdn:  mov     edi, [view_rows]
        jmp     scroll_view
.home:  mov     edi, -2000000000
        jmp     scroll_view
.end:   mov     edi, 2000000000
        jmp     scroll_view
.r:     ret

        ; ---- edicion del campo de umbral
.edit:  cmp     eax, 0xff1b
        je      .cancel
        cmp     eax, 0xff0d
        je      commit_input
        cmp     eax, 0xff8d
        je      commit_input
        cmp     eax, 0xff08                 ; BackSpace
        je      .bs
        cmp     eax, 0xffb0                 ; KP_0..KP_9
        jb      .dig
        cmp     eax, 0xffb9
        ja      .dig
        sub     eax, 0xffb0 - '0'
.dig:   cmp     eax, '0'
        jb      .r
        cmp     eax, '9'
        ja      .r
        cmp     byte [input_fresh], 0
        je      .app
        mov     dword [input_len], 0
        mov     byte [input_fresh], 0
.app:   mov     ecx, [input_len]
        cmp     ecx, 4
        jae     .r
        mov     [input_buf + rcx], al
        inc     ecx
        mov     [input_len], ecx
        ret
.bs:    mov     byte [input_fresh], 0
        mov     ecx, [input_len]
        test    ecx, ecx
        jz      .r
        dec     ecx
        mov     [input_len], ecx
        ret
.cancel:
        mov     byte [focus], 0
        ret

; =============================================================================
;  Widgets
; =============================================================================

; ui_button(edi x, esi y, edx w, ecx h, r8 etiqueta, r9d accion)
;   usa [bt_param] y [bt_style]
ui_button:
        push    rbx
        push    rbp
        push    r12
        push    r13
        push    r14
        push    r15
        sub     rsp, 8
        mov     r12d, edi
        mov     r13d, esi
        mov     r14d, edx
        mov     r15d, ecx
        mov     rbx, r8
        mov     ebp, r9d
        mov     r8d, ebp
        mov     r9d, [bt_param]
        call    add_hit
        mov     eax, [bt_style]
        mov     eax, [style_bg + rax*4]
        mov     edi, ebp
        mov     esi, [bt_param]
        call    is_hover
        jne     .nh
        mov     edi, eax
        mov     esi, C_WHITE
        mov     edx, 1
        mov     ecx, 7
        call    lerp_color
.nh:    mov     [rsp], eax
        ROUND   r12d, r13d, r14d, r15d, 7, [rsp]
        mov     eax, [bt_style]
        cmp     eax, ST_FIELD
        jb      .label
        ; campo: borde
        mov     ecx, C_DIM
        cmp     eax, ST_FOCUS
        jne     .fb
        mov     ecx, C_ACCENT
.fb:    mov     [rsp+4], ecx
        ROUND   r12d, r13d, r14d, r15d, 7, [rsp+4]
        lea     edi, [r12+1]
        lea     esi, [r13+1]
        lea     edx, [r14-2]
        lea     ecx, [r15-2]
        mov     r8d, 6
        mov     r9d, [rsp]
        call    fill_round
.label: mov     eax, [bt_style]
        mov     r8d, [style_fg + rax*4]
        mov     edi, r12d
        mov     esi, r15d
        sub     esi, FONT_S_H
        sar     esi, 1
        add     esi, r13d
        mov     edx, r14d
        mov     rcx, rbx
        lea     r9, [font_sb]
        call    draw_text_center
        mov     dword [bt_style], ST_NORMAL
        mov     dword [bt_param], 0
        add     rsp, 8
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbp
        pop     rbx
        ret

; segmented(edi x, esi y, edx ancho item, ecx n, r8 tabla de etiquetas,
;           r9d accion, [seg_sel] seleccionado)
segmented:
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
        mov     rbp, r8
        mov     [seg_action], r9d
        xor     ebx, ebx
.lp:    cmp     ebx, r15d
        jae     .done
        mov     [bt_param], ebx
        mov     dword [bt_style], ST_NORMAL
        cmp     ebx, [seg_sel]
        jne     .ns
        mov     dword [bt_style], ST_SELECTED
.ns:    lea     edi, [r14+4]
        imul    edi, ebx
        add     edi, r12d
        mov     esi, r13d
        mov     edx, r14d
        mov     ecx, 28
        mov     r8, [rbp + rbx*8]
        mov     r9d, [seg_action]
        call    ui_button
        inc     ebx
        jmp     .lp
.done:  pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbp
        pop     rbx
        ret

; panel(edi x, esi y, edx w, ecx h) -- tarjeta con sombra y borde
panel:
        push    rbx
        push    r12
        push    r13
        push    r14
        mov     ebx, edi
        mov     r12d, esi
        mov     r13d, edx
        mov     r14d, ecx
        lea     edi, [rbx-2]
        lea     esi, [r12+2]
        lea     edx, [r13+4]
        lea     ecx, [r14+4]
        mov     r8d, 10
        mov     r9d, 0x38000000
        call    fill_round
        ROUND   ebx, r12d, r13d, r14d, 9, C_BORDER
        lea     edi, [rbx+1]
        lea     esi, [r12+1]
        lea     edx, [r13-2]
        lea     ecx, [r14-2]
        mov     r8d, 8
        mov     r9d, C_PANEL
        call    fill_round
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

; pill_r(edi x_der, esi y, rdx texto, ecx color texto, r8d fondo) -> eax nuevo x_der
pill_r:
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15
        mov     ebx, edi
        mov     r12d, esi
        mov     r13, rdx
        mov     r14d, ecx
        mov     r15d, r8d
        lea     r8, [font_s]
        call    text_width
        add     eax, 20
        sub     ebx, eax
        mov     edi, ebx
        mov     esi, r12d
        mov     edx, eax
        mov     ecx, 24
        mov     r8d, 12
        mov     r9d, r15d
        call    fill_round
        lea     edi, [rbx+10]
        lea     esi, [r12+3]
        mov     rdx, r13
        mov     ecx, r14d
        lea     r8, [font_s]
        call    draw_text
        lea     eax, [rbx-8]
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

; =============================================================================
;  Render
; =============================================================================
layout:
        mov     eax, [scr_w]
        sub     eax, 32
        mov     [can_w], eax
        mov     eax, [scr_h]
        sub     eax, FOOT_H + BOT_Y + 6
        mov     [bot_h], eax
        mov     eax, [scr_w]
        sub     eax, 16 + OUT_X
        mov     [out_w], eax
        ret

render:
        push    rbx
        push    r15
        call    now_ns
        mov     r15, rax
        mov     dword [nhits], 0
        call    layout
        mov     eax, [scr_w]
        mov     ecx, [scr_h]
        RECT    0, 0, eax, ecx, C_BG
        call    draw_header
        call    draw_toolbar
        call    draw_canvas
        call    draw_inspector
        call    draw_sql
        call    draw_output
        call    draw_footer
        call    draw_ctx
        call    draw_tooltip
        call    draw_toast
        call    now_ns
        sub     rax, r15
        mov     [frame_ns], rax
        pop     r15
        pop     rbx
        ret

; ---------------------------------------------------------------- cabecera
draw_header:
        push    rbx
        mov     edx, [scr_w]
        xor     edi, edi
        xor     esi, esi
        mov     ecx, HDR_H
        mov     r8d, 0x1c2b4d
        mov     r9d, 0x121622
        call    fill_vgrad
        mov     eax, [scr_w]
        RECT    0, HDR_H, eax, 1, C_BORDER
        TEXT    22, 8, t_title, C_WHITE, font_l
        TEXT    200, 19, t_subtitle, C_MUTED, font_s
        mov     edi, [scr_w]
        sub     edi, 20
        lea     rdx, [t_putimage]
        mov     ecx, 0xd0d6e0
        mov     r8d, 0x3a4152
        cmp     byte [use_shm], 0
        je      .p
        lea     rdx, [t_mitshm]
        mov     ecx, 0x0f1117
        mov     r8d, C_GREEN
.p:     mov     esi, 16
        call    pill_r
        mov     edi, eax
        mov     esi, 16
        lea     rdx, [t_nolibc]
        mov     ecx, 0xc8d3ea
        mov     r8d, 0x2a3b5e
        call    pill_r
        mov     edi, eax
        mov     esi, 16
        lea     rdx, [t_zerodeps]
        mov     ecx, 0xc8d3ea
        mov     r8d, 0x2a3b5e
        call    pill_r
        mov     ebx, eax
        call    sb_reset
        mov     edi, [nthreads]
        call    sb_num
        SB_STR  t_threads_sfx
        mov     edi, ebx
        mov     esi, 16
        lea     rdx, [sb_buf]
        mov     ecx, 0xc8d3ea
        mov     r8d, 0x2a3b5e
        call    pill_r
        mov     edi, eax
        mov     esi, 16
        lea     rdx, [t_x8664]
        mov     ecx, 0xc8d3ea
        mov     r8d, 0x2a3b5e
        call    pill_r
        pop     rbx
        ret

; ---------------------------------------------------------- barra de botones
draw_toolbar:
        push    rbx
        BUTTON  16, TB_Y, 150, TB_H, t_run, A_RUN, 0, ST_GREEN
        BUTTON  174, TB_Y, 176, TB_H, t_newdata, A_NEW, 0, ST_BLUE
        BUTTON  358, TB_Y, 164, TB_H, t_export, A_EXPORT, 0, ST_PURPLE
        movzx   eax, byte [run_state]
        cmp     eax, 1
        je      .run
        cmp     eax, 2
        je      .ok
        TEXT    540, TB_Y, t_st_idle1, C_TEXT, font_s
        call    sb_reset
        mov     edi, [nrec]
        call    sb_num
        SB_STR  t_st_idle2
        TEXT    540, TB_Y+19, sb_buf, C_MUTED, font_s
        jmp     .r
.run:   TEXT    540, TB_Y, t_st_run1, C_YELLOW, font_sb
        TEXT    540, TB_Y+19, t_st_run2, C_MUTED, font_s
        jmp     .r
.ok:    call    sb_reset
        SB_STR  t_st_ok1
        mov     rdi, [pipe_ns]
        call    sb_time
        TEXT    540, TB_Y, sb_buf, C_GREEN, font_sb
        call    sb_reset
        mov     edi, [nrec]
        call    sb_num
        SB_STR  t_regs_arrow
        mov     edi, [n_rows]
        call    sb_num
        SB_STR  t_groups
        ; throughput global
        mov     rcx, [pipe_ns]
        test    rcx, rcx
        jz      .nt
        mov     eax, [nrec]
        imul    rax, rax, 1000
        xor     edx, edx
        div     rcx
        mov     rdi, rax
        SB_STR  t_dot_sep
        call    sb_num
        SB_STR  t_mregs
.nt:    TEXT    540, TB_Y+19, sb_buf, C_MUTED, font_s
.r:     pop     rbx
        ret

; ------------------------------------------------------------------ lienzo
draw_canvas:
        push    rbx
        push    r12
        push    r13
        mov     edx, [can_w]
        mov     edi, CAN_X
        mov     esi, CAN_Y
        mov     ecx, CAN_H
        call    panel
        mov     edx, [can_w]
        HIT     CAN_X, CAN_Y, edx, CAN_H, A_CANVAS, 0
        ; grilla de puntos
        mov     r12d, CAN_Y + 36
.gy:    cmp     r12d, CAN_Y + CAN_H - 8
        jge     .gdone
        mov     r13d, CAN_X + 20
        mov     ebx, [can_w]
        add     ebx, CAN_X - 8
.gx:    cmp     r13d, ebx
        jge     .gny
        RECT    r13d, r12d, 2, 2, 0x242938
        add     r13d, 20
        jmp     .gx
.gny:   add     r12d, 20
        jmp     .gy
.gdone:
        TEXT    CAN_X+16, CAN_Y+9, t_graph, C_MUTED, font_sb
        TEXT    CAN_X+68, CAN_Y+9, t_graphfile, C_DIM, font_s
        mov     edi, [scr_w]
        sub     edi, CAN_X + 16
        mov     esi, CAN_Y+9
        lea     rdx, [t_canvas_hint]
        mov     ecx, C_DIM
        lea     r8, [font_s]
        call    draw_text_right
        ; flujos
        xor     ebx, ebx
.links: cmp     ebx, 4
        jae     .comps
        mov     edi, ebx
        call    draw_link
        inc     ebx
        jmp     .links
        ; componentes (el seleccionado al final, queda arriba)
.comps: xor     ebx, ebx
.cl:    cmp     ebx, 5
        jae     .selc
        cmp     ebx, [sel]
        je      .skip
        mov     edi, ebx
        call    draw_component
.skip:  inc     ebx
        jmp     .cl
.selc:  mov     edi, [sel]
        test    edi, edi
        js      .r
        call    draw_component
.r:     pop     r13
        pop     r12
        pop     rbx
        ret

; draw_link(edi = i)
draw_link:
        push    rbx
        push    rbp
        push    r12
        push    r13
        push    r14
        push    r15
        sub     rsp, 8
        mov     ebx, edi
        mov     eax, edi
        shl     eax, 5
        lea     r12, [link_pts + rax]
        ; P0: puerto de salida de i ; P3: puerto de entrada de i+1
        mov     eax, [comp_x + rbx*4]
        add     eax, CAN_X + BOXW
        mov     [r12], eax
        mov     eax, [comp_y + rbx*4]
        add     eax, CAN_Y + BOXH/2
        mov     [r12+4], eax
        mov     eax, [comp_x + rbx*4 + 4]
        add     eax, CAN_X
        mov     [r12+24], eax
        mov     eax, [comp_y + rbx*4 + 4]
        add     eax, CAN_Y + BOXH/2
        mov     [r12+28], eax
        ; tirantes horizontales: dx = max(40, |x3-x0|/2)
        mov     eax, [r12+24]
        sub     eax, [r12]
        cdq
        xor     eax, edx
        sub     eax, edx
        shr     eax, 1
        cmp     eax, 40
        jge     .dx
        mov     eax, 40
.dx:    mov     ecx, [r12]
        add     ecx, eax
        mov     [r12+8], ecx
        mov     ecx, [r12+4]
        mov     [r12+12], ecx
        mov     ecx, [r12+24]
        sub     ecx, eax
        mov     [r12+16], ecx
        mov     ecx, [r12+28]
        mov     [r12+20], ecx

        mov     edi, ebx
        call    link_prog
        mov     r13d, eax                   ; progreso 0..1000
        mov     r14d, C_LINK
        test    r13d, r13d
        jz      .col
        mov     r14d, C_YELLOW
        cmp     r13d, 1000
        jb      .col
        mov     r14d, C_GREEN
.col:   mov     ebp, 24                     ; grosor (1/16 px)
        mov     edi, A_LINK
        mov     esi, ebx
        call    is_hover
        jne     .nh
        mov     ebp, 34
        mov     edi, r14d
        mov     esi, C_WHITE
        mov     edx, 1
        mov     ecx, 3
        call    lerp_color
        mov     r14d, eax
.nh:    cmp     byte [out_tab], 1
        jne     .draw
        cmp     ebx, [view_link]
        jne     .draw
        ; flujo inspeccionado: halo
        mov     rsi, r12
        mov     edx, 72
        mov     ecx, 0x2f4a78
        call    draw_curve
        mov     r14d, C_ACCENT
        mov     ebp, 34
.draw:  mov     rsi, r12
        mov     edx, ebp
        mov     ecx, r14d
        call    draw_curve
        ; puertos y flecha
        mov     edi, [r12]
        mov     esi, [r12+4]
        mov     edx, 4
        mov     ecx, r14d
        call    fill_circle
        xor     r15d, r15d
.arrow: cmp     r15d, 6
        jae     .arrowd
        mov     edi, [r12+24]
        sub     edi, 2
        sub     edi, r15d
        mov     esi, [r12+28]
        sub     esi, r15d
        lea     ecx, [r15*2+1]
        mov     edx, 1
        mov     r8d, r14d
        call    fill_rect
        inc     r15d
        jmp     .arrow
.arrowd:
        ; registros en vuelo
        test    r13d, r13d
        jz      .label
        cmp     r13d, 1000
        jae     .label
        xor     r15d, r15d
.dots:  cmp     r15d, 4
        jae     .label
        mov     eax, [anim_t]
        shl     eax, 1
        imul    edx, r15d, 256
        add     eax, edx
        and     eax, 1023
        mov     edi, eax
        mov     rsi, r12
        call    bez_point
        sar     eax, 4
        sar     edx, 4
        mov     edi, eax
        mov     esi, edx
        mov     edx, 3
        mov     ecx, 0xfff3b0
        call    fill_circle
        inc     r15d
        jmp     .dots
.label: cmp     byte [run_state], 0
        je      .out
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
        ; posicion: punto medio de la curva
        mov     edi, 512
        mov     rsi, r12
        call    bez_point
        sar     eax, 4
        sar     edx, 4
        mov     r15d, eax
        mov     ebp, edx
        lea     rdx, [numbuf]
        lea     r8, [font_s]
        call    text_width
        add     eax, 14
        mov     [rsp], eax
        mov     edi, r15d
        mov     ecx, eax
        shr     ecx, 1
        sub     edi, ecx
        lea     esi, [rbp-31]
        mov     edx, eax
        mov     ecx, 21
        mov     r8d, 10
        mov     r9d, 0xd00f1117
        call    fill_round
        mov     edi, r15d
        mov     eax, [rsp]
        shr     eax, 1
        sub     edi, eax
        lea     esi, [rbp-30]
        mov     edx, [rsp]
        lea     rcx, [numbuf]
        mov     r8d, r14d
        test    r13d, r13d
        jnz     .lc
        mov     r8d, C_DIM
.lc:    lea     r9, [font_s]
        call    draw_text_center
.out:   add     rsp, 8
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbp
        pop     rbx
        ret

; draw_component(edi = j)
draw_component:
        push    rbx
        push    rbp
        push    r12
        push    r13
        push    r14
        push    r15
        sub     rsp, 8
        mov     ebx, edi
        mov     r12d, [comp_x + rbx*4]
        add     r12d, CAN_X
        mov     r13d, [comp_y + rbx*4]
        add     r13d, CAN_Y
        call    comp_status
        mov     r15d, eax
        ; sombra
        lea     edi, [r12-3]
        lea     esi, [r13+3]
        mov     edx, BOXW+6
        mov     ecx, BOXH+6
        mov     r8d, 11
        mov     r9d, 0x50000000
        call    fill_round
        ; halo de seleccion
        cmp     ebx, [sel]
        jne     .nosel
        lea     edi, [r12-5]
        lea     esi, [r13-5]
        mov     edx, BOXW+10
        mov     ecx, BOXH+10
        mov     r8d, 12
        mov     r9d, 0x808ab4ff
        call    fill_round
.nosel: ; borde segun estado
        mov     ebp, C_DIM
        mov     edi, A_COMP
        mov     esi, ebx
        call    is_hover
        jne     .b0
        mov     ebp, 0x707a8e
.b0:    cmp     r15d, 2
        jne     .b1
        mov     ebp, C_GREEN
.b1:    cmp     r15d, 1
        jne     .b2
        ; pulso: alfa triangular
        mov     eax, [anim_t]
        shr     eax, 1
        and     eax, 255
        cmp     eax, 128
        jb      .tri
        xor     eax, 255
.tri:   add     eax, 0x7f
        shl     eax, 24
        or      eax, C_YELLOW
        mov     ebp, eax
.b2:    ROUND   r12d, r13d, BOXW, BOXH, 8, ebp
        lea     edi, [r12+2]
        lea     esi, [r13+2]
        mov     edx, BOXW-4
        mov     ecx, BOXH-4
        mov     r8d, 6
        mov     r9d, C_BOX
        call    fill_round
        mov     r14d, [comp_color + rbx*4]
        cmp     ebx, 2
        jne     .hc
        cmp     byte [rmode], 0
        je      .hc
        mov     r14d, 0x4b5263
.hc:    lea     edi, [r12+2]
        lea     esi, [r13+2]
        mov     edx, BOXW-4
        mov     ecx, 24
        mov     r8d, 6
        mov     r9d, r14d
        call    fill_round
        lea     edi, [r12+2]
        lea     esi, [r13+14]
        RECT    edi, esi, BOXW-4, 12, r14d
        lea     edi, [r12+9]
        lea     esi, [r13+5]
        mov     rdx, [comp_name + rbx*8]
        mov     ecx, C_WHITE
        lea     r8, [font_sb]
        call    draw_text
        ; luz de estado
        mov     ecx, 0x9aa3b5
        cmp     r15d, 1
        jne     .l2
        mov     ecx, C_YELLOW
.l2:    cmp     r15d, 2
        jne     .l3
        mov     ecx, 0xb8ffd4
.l3:    lea     edi, [r12 + BOXW - 13]
        lea     esi, [r13 + 14]
        mov     edx, 4
        call    fill_circle

        ; linea 1 y 2 segun componente
        call    sb_reset
        mov     eax, ebx
        jmp     [.l1t + rax*8]
.l1t:   dq      .c0, .c1, .c2, .c2, .c4
.c0:    SB_STR  src_short
        jmp     .l1d
.c1:    SB_STR  t_monto_sp
        mov     eax, [filt_op]
        mov     rsi, [op_names + rax*8]
        call    sb_str
        mov     edi, ' '
        call    sb_ch
        mov     edi, [thr]
        call    sb_num
        jmp     .l1d
.c2:    cmp     ebx, 2
        jne     .c2k
        cmp     byte [rmode], 0
        je      .c2k
        SB_STR  t_bypass
        jmp     .l1d
.c2k:   SB_STR  t_key
        mov     eax, [group_key]
        mov     rsi, [grp_colnames + rax*8]
        call    sb_str
        jmp     .l1d
.c4:    SB_STR  t_order
        mov     eax, [sort_col]
        mov     rsi, [sort_colnames + rax*8]
        call    sb_str
        cmp     byte [sort_desc], 0
        je      .l1d
        SB_STR  t_desc_short
.l1d:   lea     edi, [r12+10]
        lea     esi, [r13+31]
        lea     rdx, [sb_buf]
        mov     ecx, C_TEXT
        lea     r8, [font_s]
        call    draw_text

        call    sb_reset
        mov     eax, ebx
        jmp     [.l2t + rax*8]
.l2t:   dq      .d0, .d1, .d2, .d3, .d4
.d0:    mov     edi, [nrec]
        call    sb_num
        SB_STR  c_b0
        jmp     .l2d
.d1:    SB_STR  c_b1
        cmp     r15d, 2
        jne     .dash
        mov     edi, [nrec]
        sub     edi, [n_filter]
        call    sb_num
        jmp     .l2d
.d2:    cmp     byte [rmode], 0
        je      .d2s
        SB_STR  t_bypass2
        jmp     .l2d
.d2s:   SB_STR  c_b2
        jmp     .l2d
.d3:    SB_STR  c_b3
        jmp     .l2d
.d4:    cmp     r15d, 2
        jne     .dash
        mov     edi, [n_rows]
        call    sb_num
        SB_STR  c_b4
        jmp     .l2d
.dash:  SB_STR  c_dash
.l2d:   lea     edi, [r12+10]
        lea     esi, [r13+50]
        lea     rdx, [sb_buf]
        mov     ecx, C_MUTED
        lea     r8, [font_s]
        call    draw_text
        ; linea 3: tiempo medido
        cmp     r15d, 2
        jne     .hit
        cmp     ebx, 2
        jne     .tm
        cmp     byte [rmode], 0
        jne     .hit
.tm:    call    sb_reset
        mov     rdi, [comp_ns + rbx*8]
        call    sb_time
        lea     edi, [r12+10]
        lea     esi, [r13+69]
        lea     rdx, [sb_buf]
        mov     ecx, 0x7fa88a
        lea     r8, [font_s]
        call    draw_text
.hit:   HIT     r12d, r13d, BOXW, BOXH, A_COMP, ebx
        add     rsp, 8
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbp
        pop     rbx
        ret

; --------------------------------------------------------------- inspector
%define IX      INS_X
%define IY      BOT_Y
; kv(esi y, rdx etiqueta, rcx valor (z-string), r8d color valor)
kv:
        push    rbx
        push    r12
        push    r13
        push    r14
        mov     ebx, esi
        mov     r12, rcx
        mov     r13d, r8d
        mov     edi, IX+16
        mov     ecx, C_MUTED
        lea     r8, [font_s]
        call    draw_text
        mov     edi, IX+120
        mov     esi, ebx
        mov     rdx, r12
        mov     ecx, r13d
        lea     r8, [font_s]
        call    draw_text
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

draw_inspector:
        push    rbx
        push    r12
        push    r13
        mov     ecx, [bot_h]
        mov     edi, IX
        mov     esi, IY
        mov     edx, INS_W
        call    panel
        TEXT    IX+16, IY+10, t_inspector, C_MUTED, font_sb
        mov     ebx, [sel]
        test    ebx, ebx
        js      .help

        ; cabecera del componente
        mov     r12d, [comp_color + rbx*4]
        ROUND   IX+12, IY+34, INS_W-24, 26, 7, r12d
        mov     rdx, [comp_name + rbx*8]
        TEXT    IX+22, IY+38, rdx, C_WHITE, font_sb
        mov     edi, ebx
        call    comp_status
        mov     rdx, [status_names + rax*8]
        mov     edi, IX + INS_W - 22
        mov     esi, IY+38
        mov     ecx, 0xd8ffffff
        lea     r8, [font_s]
        call    draw_text_right

        ; estadisticas
        cmp     byte [run_state], 0
        jne     .stats
        test    ebx, ebx
        jnz     .nostats
.stats: call    sb_reset
        mov     edi, ebx
        call    comp_in
        mov     edi, eax
        call    sb_num
        SB_STR  t_regs
        mov     esi, IY+68
        lea     rdx, [t_k_in]
        lea     rcx, [sb_buf]
        mov     r8d, C_TEXT
        call    kv
        call    sb_reset
        mov     edi, ebx
        call    comp_out
        mov     edi, eax
        call    sb_num
        SB_STR  t_regs
        mov     esi, IY+87
        lea     rdx, [t_k_out]
        lea     rcx, [sb_buf]
        mov     r8d, C_TEXT
        call    kv
        call    sb_reset
        mov     rdi, [comp_ns + rbx*8]
        call    sb_time
        mov     esi, IY+106
        lea     rdx, [t_k_time]
        lea     rcx, [sb_buf]
        mov     r8d, C_GREEN
        call    kv
        call    sb_reset
        mov     rcx, [comp_ns + rbx*8]
        test    rcx, rcx
        jz      .nothr
        mov     edi, ebx
        call    comp_in
        mov     eax, eax
        imul    rax, rax, 1000
        xor     edx, edx
        div     rcx
        mov     rdi, rax
        call    sb_num
        SB_STR  t_mregs
        jmp     .thr
.nothr: SB_STR  c_dash
.thr:   mov     esi, IY+125
        lea     rdx, [t_k_speed]
        lea     rcx, [sb_buf]
        mov     r8d, C_YELLOW
        call    kv
        jmp     .props
.nostats:
        TEXT    IX+16, IY+87, t_not_run, C_DIM, font_s
.props: RECT    IX+12, IY+150, INS_W-24, 1, C_BORDER
        TEXT    IX+16, IY+156, t_props, C_MUTED, font_sb
        mov     eax, ebx
        jmp     [.pt + rax*8]
.pt:    dq      .p0, .p1, .p2, .p3, .p4

%define PY (IY+180)
.p0:    movzx   eax, byte [src_mode]
        cmp     eax, 1
        je      .p0csv
        cmp     eax, 2
        je      .p0pg
        TEXT    IX+16, PY, t_p_nrec, C_TEXT, font_s
        mov     eax, [nrec_sel]
        mov     [seg_sel], eax
        mov     edi, IX+16
        mov     esi, PY+22
        mov     edx, 55
        mov     ecx, 5
        lea     r8, [nrec_labels]
        mov     r9d, A_NREC
        call    segmented
        call    sb_reset
        SB_STR  t_p_seed
        mov     edi, [seed0]
        call    sb_hex
        TEXT    IX+16, PY+60, sb_buf, C_MUTED, font_s
        TEXT    IX+16, PY+79, t_p_gen, C_DIM, font_s
        jmp     .out
.p0csv: call    sb_reset
        SB_STR  t_p_src_file
        SB_STR  src_short
        TEXT    IX+16, PY, sb_buf, C_TEXT, font_s
        call    sb_reset
        SB_STR  t_p_src_size
        mov     rax, [load_bytes]
        xor     edx, edx
        mov     ecx, 100000
        div     rcx
        mov     rdi, rax
        call    sb_tenths
        SB_STR  t_p_src_delim
        lea     rsi, [d_comma]
        cmp     byte [csv_delim], ';'
        jne     .dl1
        lea     rsi, [d_semi]
.dl1:   cmp     byte [csv_delim], 9
        jne     .dl2
        lea     rsi, [d_tab]
.dl2:   call    sb_str
        TEXT    IX+16, PY+19, sb_buf, C_MUTED, font_s
        call    .speed
        TEXT    IX+16, PY+38, sb_buf, C_MUTED, font_s
        BUTTON  IX+16, PY+62, 160, 26, t_reload, A_RELOAD, 0, ST_BLUE
        jmp     .out
.p0pg:  call    sb_reset
        SB_STR  t_p_pg_srv
        mov     rsi, [pg_host]
        test    rsi, rsi
        jnz     .ph
        lea     rsi, [t_unixsock]
.ph:    call    sb_str
        mov     edi, ':'
        call    sb_ch
        mov     edi, [pg_port]
        call    sb_dec
        mov     dword [text_max], 37
        TEXT    IX+16, PY, sb_buf, C_TEXT, font_s
        call    sb_reset
        SB_STR  t_p_pg_db
        mov     rsi, [pg_db]
        call    sb_str
        SB_STR  t_p_pg_user
        mov     rsi, [pg_user]
        call    sb_str
        TEXT    IX+16, PY+19, sb_buf, C_MUTED, font_s
        call    sb_reset
        SB_STR  t_p_pg_auth
        mov     rsi, [pg_auth_name]
        call    sb_str
        SB_STR  t_dot_sep
        call    .speed_short
        TEXT    IX+16, PY+38, sb_buf, C_MUTED, font_s
        mov     dword [text_max], 0
        BUTTON  IX+16, PY+62, 160, 26, t_reload, A_RELOAD, 0, ST_BLUE
        jmp     .out
; "Lectura: N MB/s"
.speed: call    sb_reset
        SB_STR  t_p_src_speed
.speed_short:
        mov     rcx, [load_ns]
        test    rcx, rcx
        jz      .sp0
        mov     rax, [load_bytes]
        imul    rax, rax, 1000
        xor     edx, edx
        div     rcx
        mov     rdi, rax
        call    sb_num
.sp0:   SB_STR  t_p_src_mbs
        ret

.p1:    call    sb_reset
        SB_STR  t_p_expr
        mov     eax, [filt_op]
        mov     rsi, [op_names + rax*8]
        call    sb_str
        mov     edi, ' '
        call    sb_ch
        mov     edi, [thr]
        call    sb_num
        TEXT    IX+16, PY, sb_buf, C_TEXT, font_s
        mov     eax, [filt_op]
        mov     [seg_sel], eax
        mov     edi, IX+16
        mov     esi, PY+22
        mov     edx, 45
        mov     ecx, 6
        lea     r8, [op_names]
        mov     r9d, A_OP
        call    segmented
        BUTTON  IX+16, PY+58, 34, 28, t_minus, A_THR_DEC, 0, ST_NORMAL
        ; campo editable
        mov     eax, ST_FIELD
        cmp     byte [focus], 0
        je      .fs
        mov     eax, ST_FOCUS
.fs:    mov     [bt_style], eax
        mov     dword [bt_param], 0
        cmp     byte [focus], 0
        jne     .fedit
        call    sb_reset
        mov     edi, [thr]
        call    sb_num
        jmp     .fdraw
.fedit: call    sb_reset
        lea     rsi, [input_buf]
        mov     ecx, [input_len]
        mov     byte [rsi + rcx], 0
        call    sb_str
        ; cursor titilante
        mov     rax, [now]
        xor     edx, edx
        mov     ecx, 530
        div     rcx
        test    eax, 1
        jnz     .fdraw
        mov     edi, '|'
        call    sb_ch
.fdraw: mov     edi, IX+56
        mov     esi, PY+58
        mov     edx, 90
        mov     ecx, 28
        lea     r8, [sb_buf]
        mov     r9d, A_THR_FIELD
        call    ui_button
        BUTTON  IX+152, PY+58, 34, 28, t_plus, A_THR_INC, 0, ST_NORMAL
        mov     edx, t_field_hint
        cmp     byte [focus], 0
        je      .fh
        mov     edx, t_field_hint2
.fh:    TEXT    IX+196, PY+63, rdx, C_DIM, font_s
        jmp     .out

.p2:    cmp     byte [rmode], 0
        je      .p2s
        TEXT    IX+16, PY, t_p_bypass1, C_MUTED, font_s
        TEXT    IX+16, PY+19, t_p_bypass2, C_MUTED, font_s
        jmp     .out
.p2s:   TEXT    IX+16, PY, t_p_sortkey, C_TEXT, font_s
        call    .groupseg
        TEXT    IX+16, PY+60, t_p_sortalg, C_MUTED, font_s
        TEXT    IX+16, PY+79, t_p_sortsync, C_DIM, font_s
        jmp     .out

.p3:    TEXT    IX+16, PY, t_p_groupby, C_TEXT, font_s
        call    .groupseg
        movzx   eax, byte [rmode]
        mov     [seg_sel], eax
        mov     edi, IX+16
        mov     esi, PY+58
        mov     edx, 145
        mov     ecx, 2
        lea     r8, [rmode_labels]
        mov     r9d, A_RMODE
        call    segmented
        jmp     .out

.p4:    TEXT    IX+16, PY, t_p_orderby, C_TEXT, font_s
        mov     eax, [sort_col]
        mov     [seg_sel], eax
        mov     edi, IX+16
        mov     esi, PY+22
        mov     edx, 45
        mov     ecx, 6
        lea     r8, [sort_labels]
        mov     r9d, A_SORTCOL
        call    segmented
        lea     r8, [t_asc]
        cmp     byte [sort_desc], 0
        je      .ad
        lea     r8, [t_descl]
.ad:    mov     dword [bt_style], ST_NORMAL
        mov     dword [bt_param], 0
        mov     edi, IX+16
        mov     esi, PY+58
        mov     edx, 130
        mov     ecx, 28
        mov     r9d, A_SORTDIR
        call    ui_button
        BUTTON  IX+154, PY+58, 144, 28, t_export_short, A_EXPORT, 0, ST_PURPLE
        jmp     .out

.groupseg:
        mov     eax, [group_key]
        mov     [seg_sel], eax
        mov     edi, IX+16
        mov     esi, PY+22
        mov     edx, 94
        mov     ecx, 3
        lea     r8, [grp_colnames]
        mov     r9d, A_GROUP
        jmp     segmented

.help:  xor     r12d, r12d
.hl:    cmp     r12d, 9
        jae     .out
        imul    r13d, r12d, 21
        add     r13d, IY+40
        TEXT    IX+16, r13d, t_bullet, C_ACCENT, font_s
        mov     rdx, [help_lines + r12*8]
        mov     ecx, C_TEXT
        test    r12d, r12d
        jnz     .hc
        mov     ecx, C_YELLOW
.hc:    TEXT    IX+30, r13d, rdx, ecx, font_s
        inc     r12d
        jmp     .hl
.out:   pop     r13
        pop     r12
        pop     rbx
        ret

; -------------------------------------------------------------------- SQL
%define SQX     (SQL_X + 16)
%define SQY     (BOT_Y + 40)
%macro SQ 4     ; columna, linea, texto, color
        TEXT    SQX + (%1)*FONT_S_W, SQY + (%2)*LINEH, %3, %4, font_s
%endmacro

; sql_band(edi linea, esi cantidad, edx color)
sql_band:
        mov     r9d, edx
        and     r9d, 0xFFFFFF
        or      r9d, 0x38000000
        imul    eax, edi, LINEH
        imul    esi, esi, LINEH
        add     eax, SQY - 2
        mov     ecx, esi
        mov     esi, eax
        mov     edi, SQL_X + 8
        mov     edx, SQL_W - 16
        mov     r8d, 5
        jmp     fill_round

draw_sql:
        push    rbx
        mov     ecx, [bot_h]
        mov     edi, SQL_X
        mov     esi, BOT_Y
        mov     edx, SQL_W
        call    panel
        TEXT    SQL_X+16, BOT_Y+10, t_sqltitle, C_MUTED, font_sb
        TEXT    SQL_X+148, BOT_Y+10, t_sqldialects, C_DIM, font_s
        ; resaltar la clausula del componente seleccionado
        mov     ebx, [sel]
        test    ebx, ebx
        js      .code
        mov     edx, [comp_color + rbx*4]
        mov     eax, ebx
        mov     edi, [sql_band_line + rax*4]
        mov     esi, [sql_band_n + rax*4]
        call    sql_band
        cmp     ebx, 3                      ; ROLLUP: tambien GROUP BY
        jne     .code
        mov     edi, 8
        mov     esi, 1
        mov     edx, [comp_color + 12]
        call    sql_band
.code:  SQ      0, 0, q_select, C_KW
        mov     eax, [group_key]
        mov     rdx, [grp_colnames + rax*8]
        mov     edi, SQX + 7*FONT_S_W
        mov     esi, SQY
        mov     ecx, C_TEXT
        lea     r8, [font_s]
        call    draw_text
        TEXT    eax, SQY, t_comma, C_TEXT, font_s
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
        SQ      7, 4, q_min, C_FN
        SQ      10, 4, q_monto_p, C_TEXT
        SQ      19, 4, q_as, C_KW
        SQ      22, 4, q_minimo, C_TEXT
        SQ      7, 5, q_max, C_FN
        SQ      10, 5, q_monto_p, C_TEXT
        SQ      19, 5, q_as, C_KW
        SQ      22, 5, q_maximo, C_TEXT
        SQ      0, 6, q_from, C_KW
        SQ      7, 6, q_ventas, C_TEXT
        SQ      0, 7, q_where, C_KW
        SQ      7, 7, q_monto, C_TEXT
        mov     eax, [filt_op]
        mov     rdx, [op_names + rax*8]
        mov     edi, SQX + 13*FONT_S_W
        mov     esi, SQY + 7*LINEH
        mov     ecx, C_KW
        lea     r8, [font_s]
        call    draw_text
        lea     edi, [rax + FONT_S_W]
        mov     esi, SQY + 7*LINEH
        mov     edx, [thr]
        mov     ecx, C_NUM
        lea     r8, [font_s]
        call    draw_num
        SQ      0, 8, q_group, C_KW
        SQ      7, 8, q_by, C_KW
        mov     eax, [group_key]
        mov     rdx, [grp_colnames + rax*8]
        mov     edi, SQX + 10*FONT_S_W
        mov     esi, SQY + 8*LINEH
        mov     ecx, C_TEXT
        lea     r8, [font_s]
        call    draw_text
        SQ      0, 9, q_order, C_KW
        SQ      7, 9, q_by, C_KW
        mov     eax, [sort_col]
        mov     rdx, [sql_ordercols + rax*8]
        test    eax, eax
        jnz     .oc
        mov     eax, [group_key]
        mov     rdx, [grp_colnames + rax*8]
.oc:    mov     edi, SQX + 10*FONT_S_W
        mov     esi, SQY + 9*LINEH
        mov     ecx, C_TEXT
        lea     r8, [font_s]
        call    draw_text
        cmp     byte [sort_desc], 0
        je      .semi
        lea     edi, [rax + FONT_S_W]
        TEXT    edi, SQY + 9*LINEH, q_desc, C_KW, font_s
.semi:  TEXT    eax, SQY + 9*LINEH, t_semicolon, C_TEXT, font_s
        SQ      0, 10, q_comment, C_CMT
        pop     rbx
        ret

; ------------------------------------------------------------------ salida
%define OY      BOT_Y
draw_output:
        push    rbx
        push    r12
        mov     edx, [out_w]
        mov     ecx, [bot_h]
        mov     edi, OUT_X
        mov     esi, OY
        call    panel
        mov     edx, [out_w]
        mov     ecx, [bot_h]
        sub     ecx, 40
        HIT     OUT_X, OY+40, edx, ecx, A_VIEWER, 0
        ; pestanias
        movzx   eax, byte [out_tab]
        mov     ebx, ST_GHOST
        mov     r12d, ST_SELECTED
        test    eax, eax
        jz      .t
        xchg    ebx, r12d
.t:     BUTTON  OUT_X+10, OY+8, 130, 26, t_tab_res, A_TAB, 0, r12d
        BUTTON  OUT_X+144, OY+8, 130, 26, t_tab_view, A_TAB, 1, ebx
        cmp     byte [out_tab], 0
        jne     .view
        call    draw_results
        jmp     .r
.view:  call    draw_viewer
.r:     pop     r12
        pop     rbx
        ret

; col_header(edi x_ref, esi 1 = alineado a derecha, edx columna, rcx texto)
;   encabezado clickeable para ordenar, con indicador de direccion
%define RX      OUT_X
%define RHY     (OY + 46)
col_header:
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15
        mov     ebx, edi
        mov     r12d, esi
        mov     r13d, edx
        mov     r14, rcx
        mov     r15d, C_MUTED
        cmp     r13d, [sort_col]
        jne     .c
        mov     r15d, C_ACCENT
.c:     mov     edi, A_SORTCOL
        mov     esi, r13d
        call    is_hover
        jne     .nh
        mov     r15d, C_WHITE
.nh:    mov     edi, ebx
        mov     esi, RHY
        mov     rdx, r14
        mov     ecx, r15d
        lea     r8, [font_sb]
        test    r12d, r12d
        jz      .left
        call    draw_text_right             ; eax = izquierda
        mov     r14d, eax                   ; r14 = izquierda, ebx = derecha
        jmp     .ind
.left:  call    draw_text                   ; eax = derecha
        mov     r14d, ebx
        mov     ebx, eax
.ind:   cmp     r13d, [sort_col]
        jne     .hit
        lea     edi, [rbx+4]
        test    r12d, r12d
        jz      .t
        lea     edi, [r14-11]
.t:     mov     esi, RHY + 7
        movzx   edx, byte [sort_desc]
        mov     ecx, C_ACCENT
        call    tri
.hit:   mov     edx, ebx
        sub     edx, r14d
        add     edx, 24
        lea     edi, [r14-12]
        HIT     edi, RHY-4, edx, 26, A_SORTCOL, r13d
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

draw_results:
        push    rbx
        push    rbp
        push    r12
        push    r13
        push    r14
        push    r15
        sub     rsp, 24
        movzx   eax, byte [run_state]
        test    eax, eax
        jz      .empty
        mov     r15d, 1000                  ; factor de aparicion
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
        TEXT    RX+20, OY+120, t_processing, C_YELLOW, font_sb
        jmp     .out
.empty: TEXT    RX+20, OY+110, t_empty1, C_TEXT, font_sb
        TEXT    RX+20, OY+132, t_empty2, C_MUTED, font_s
        jmp     .out

.show:  ; encabezados (clickeables para ordenar)
        mov     eax, [group_key]
        mov     rcx, [grp_headers + rax*8]
        mov     edi, RX+16
        xor     esi, esi
        xor     edx, edx
        call    col_header
        mov     edi, RX+176
        mov     esi, 1
        mov     edx, 1
        lea     rcx, [t_h_regs]
        call    col_header
        mov     edi, RX+300
        mov     esi, 1
        mov     edx, 2
        lea     rcx, [t_h_total]
        call    col_header
        mov     edi, RX+346
        mov     esi, 1
        mov     edx, 3
        lea     rcx, [t_h_prom]
        call    col_header
        mov     edi, RX+388
        mov     esi, 1
        mov     edx, 4
        lea     rcx, [t_h_min]
        call    col_header
        mov     edi, RX+434
        mov     esi, 1
        mov     edx, 5
        lea     rcx, [t_h_max]
        call    col_header
        mov     edx, [out_w]
        sub     edx, 24
        RECT    RX+12, OY+68, edx, 1, C_BORDER

        ; filas visibles
        mov     eax, [bot_h]
        sub     eax, 74 + 40
        xor     edx, edx
        mov     ecx, ROWH
        div     ecx
        mov     [res_rows], eax
        ; maximo total para escalar barras
        xor     r14, r14
        xor     ecx, ecx
.mx:    cmp     ecx, [n_rows]
        jae     .mxd
        mov     rax, [res_sum + rcx*8]
        cmp     rax, r14
        cmovg   r14, rax
        inc     ecx
        jmp     .mx
.mxd:   test    r14, r14
        jnz     .bw
        inc     r14
.bw:    mov     eax, [out_w]
        sub     eax, 460
        mov     [rsp+8], eax                ; ancho maximo de barra

        xor     ebx, ebx
.row:   cmp     ebx, [res_rows]
        jae     .totals
        mov     eax, ebx
        add     eax, [res_scroll]
        cmp     eax, [n_rows]
        jae     .totals
        mov     r13d, [res_order + rax*4]   ; fila real
        imul    r12d, ebx, ROWH
        add     r12d, OY + 74
        ; hover de fila
        mov     eax, [mouse_y]
        sub     eax, r12d
        cmp     eax, ROWH
        jae     .nohl
        mov     eax, [mouse_x]
        sub     eax, RX
        cmp     eax, [out_w]
        jae     .nohl
        mov     edx, [out_w]
        sub     edx, 16
        lea     esi, [r12-1]
        mov     edi, RX+8
        mov     ecx, ROWH
        mov     r8d, 4
        mov     r9d, 0x14ffffff
        call    fill_round
.nohl:  mov     edi, [res_key + r13*4]
        call    group_name
        mov     rdx, rax
        mov     edi, RX+16
        mov     esi, r12d
        mov     ecx, C_TEXT
        lea     r8, [font_s]
        mov     dword [text_max], 10
        call    draw_text
        mov     dword [text_max], 0
        mov     edi, RX+176
        mov     esi, r12d
        mov     edx, [res_count + r13*4]
        mov     ecx, C_TEXT
        lea     r8, [font_s]
        call    draw_num_right
        mov     edi, RX+300
        mov     esi, r12d
        mov     rdx, [res_sum + r13*8]
        mov     ecx, C_TEXT
        lea     r8, [font_s]
        call    draw_num_right
        mov     edi, RX+346
        mov     esi, r12d
        mov     edx, [res_avg + r13*4]
        mov     ecx, C_NUM
        lea     r8, [font_s]
        call    draw_num_right
        mov     edi, RX+388
        mov     esi, r12d
        mov     edx, [res_min + r13*4]
        mov     ecx, C_MUTED
        lea     r8, [font_s]
        call    draw_num_right
        mov     edi, RX+434
        mov     esi, r12d
        mov     edx, [res_max + r13*4]
        mov     ecx, C_MUTED
        lea     r8, [font_s]
        call    draw_num_right
        ; barra
        mov     ebp, [rsp+8]
        cmp     ebp, 24
        jl      .nobar
        lea     esi, [r12+4]
        RECT    RX+446, esi, ebp, 11, 0x232837
        mov     rax, [res_sum + r13*8]
        imul    rax, rbp
        xor     edx, edx
        div     r14
        mov     ecx, r15d
        imul    rax, rcx
        xor     edx, edx
        mov     ecx, 1000
        div     rcx
        test    eax, eax
        jz      .nobar
        mov     edx, eax
        mov     eax, [res_key + r13*4]
        and     eax, 7
        mov     r8d, [bar_colors + rax*4]
        mov     edi, RX+446
        lea     esi, [r12+4]
        mov     ecx, 11
        call    fill_rect
.nobar: inc     ebx
        jmp     .row

.totals:
        ; barra de scroll si hay mas filas que lugar
        mov     eax, [n_rows]
        cmp     eax, [res_rows]
        jbe     .tot
        mov     edi, [out_w]
        add     edi, RX - 10
        mov     esi, OY+74
        mov     ecx, [res_rows]
        imul    ecx, ROWH
        mov     edx, 4
        mov     r8d, 0x232837
        call    fill_rect
.tot:   mov     r12d, [bot_h]
        add     r12d, OY - 30
        mov     edx, [out_w]
        sub     edx, 24
        lea     esi, [r12-6]
        RECT    RX+12, esi, edx, 1, C_BORDER
        TEXT    RX+16, r12d, t_total, C_YELLOW, font_sb
        mov     edi, RX+176
        mov     esi, r12d
        mov     edx, [n_filter]
        mov     ecx, C_YELLOW
        lea     r8, [font_sb]
        call    draw_num_right
        xor     eax, eax
        xor     ecx, ecx
.ts:    cmp     ecx, [n_rows]
        jae     .tsd
        add     rax, [res_sum + rcx*8]
        inc     ecx
        jmp     .ts
.tsd:   mov     [rsp], rax
        mov     rdx, rax
        mov     edi, RX+300
        mov     esi, r12d
        mov     ecx, C_YELLOW
        lea     r8, [font_sb]
        call    draw_num_right
        ; promedio global
        mov     ecx, [n_filter]
        test    ecx, ecx
        jz      .out
        mov     rax, [rsp]
        xor     edx, edx
        div     rcx
        mov     rdx, rax
        mov     edi, RX+346
        mov     esi, r12d
        mov     ecx, C_YELLOW
        lea     r8, [font_sb]
        call    draw_num_right
.out:   add     rsp, 24
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbp
        pop     rbx
        ret

; visor de registros de un flujo
draw_viewer:
        push    rbx
        push    rbp
        push    r12
        push    r13
        push    r14
        push    r15
        sub     rsp, 8
        mov     r14d, [view_link]
        ; titulo: FLUJO i: A -> B
        call    sb_reset
        SB_STR  t_flow
        lea     edi, [r14 + '1']
        call    sb_ch
        SB_STR  t_colon_sp
        mov     rsi, [comp_name + r14*8]
        call    sb_str
        SB_STR  t_arrow
        mov     rsi, [comp_name + r14*8 + 8]
        call    sb_str
        TEXT    RX+16, OY+44, sb_buf, C_ACCENT, font_sb
        mov     edi, r14d
        call    view_count
        mov     r15d, eax                   ; total
        cmp     r14d, 0
        je      .ok
        cmp     byte [run_state], 0
        jne     .ok
        TEXT    RX+16, OY+110, t_view_norun, C_MUTED, font_s
        jmp     .out
.ok:    call    sb_reset
        mov     edi, r15d
        call    sb_num
        SB_STR  t_regs
        mov     edi, [out_w]
        add     edi, RX - 20
        mov     esi, OY+44
        lea     rdx, [sb_buf]
        mov     ecx, C_MUTED
        lea     r8, [font_s]
        call    draw_text_right

        ; filas visibles
        mov     eax, [bot_h]
        sub     eax, 92 + 34
        xor     edx, edx
        mov     ecx, ROWH
        div     ecx
        mov     [view_rows], eax
        ; encabezados
        cmp     r14d, 3
        je      .hres
        TEXT    RX+92, OY+68, t_v_idx, C_MUTED, font_sb
        TEXT    RX+112, OY+68, t_v_reg, C_MUTED, font_sb
        TEXT    RX+222, OY+68, t_v_mes, C_MUTED, font_sb
        TEXT    RX+294, OY+68, t_v_canal, C_MUTED, font_sb
        mov     edi, [out_w]
        add     edi, RX - 30
        mov     esi, OY+68
        lea     rdx, [t_v_monto]
        mov     ecx, C_MUTED
        lea     r8, [font_sb]
        call    draw_text_right
        jmp     .rows
.hres:  mov     eax, [group_key]
        mov     rdx, [grp_headers + rax*8]
        TEXT    RX+16, OY+68, rdx, C_MUTED, font_sb
        mov     edi, RX+200
        mov     esi, OY+68
        lea     rdx, [t_h_regs]
        mov     ecx, C_MUTED
        lea     r8, [font_sb]
        call    draw_text_right
        mov     edi, RX+320
        mov     esi, OY+68
        lea     rdx, [t_h_total]
        mov     ecx, C_MUTED
        lea     r8, [font_sb]
        call    draw_text_right

.rows:  xor     ebx, ebx
.row:   cmp     ebx, [view_rows]
        jae     .sbar
        mov     ebp, [view_scroll]
        add     ebp, ebx                    ; indice en el flujo
        cmp     ebp, r15d
        jae     .sbar
        imul    r12d, ebx, ROWH
        add     r12d, OY + 92
        test    ebx, 1
        jz      .nz
        mov     edx, [out_w]
        sub     edx, 36
        lea     esi, [r12-1]
        RECT    RX+10, esi, edx, ROWH, 0x0affffff
.nz:    cmp     r14d, 3
        je      .rres
        ; registro: indice real segun el flujo
        mov     r13d, ebp
        cmp     r14d, 1
        je      .lf
        cmp     r14d, 2
        jne     .l3
        cmp     byte [rmode], 0
        jne     .lf                         ; SORT en bypass: mismo flujo
        mov     rax, [p_sidx]
        mov     r13d, [rax + rbp*4]
        ; separador de grupo en el flujo ordenado
        test    ebp, ebp
        jz      .l3
        mov     edx, [group_key]
        mov     rcx, [col_key + rdx*8]
        mov     eax, [rax + rbp*4 - 4]
        movzx   eax, byte [rcx + rax]
        movzx   edx, byte [rcx + r13]
        cmp     eax, edx
        je      .l3
        mov     edx, [out_w]
        sub     edx, 36
        lea     esi, [r12-2]
        RECT    RX+10, esi, edx, 1, 0x80d9822b
        jmp     .l3
.lf:    mov     rax, [p_fidx]
        mov     r13d, [rax + rbp*4]
.l3:    lea     edx, [rbp+1]
        mov     edi, RX+100
        mov     esi, r12d
        mov     ecx, C_DIM
        lea     r8, [font_s]
        call    draw_num_right
        mov     dword [text_max], 13
        mov     rax, [col_key]
        movzx   edi, byte [rax + r13]
        xor     eax, eax
        call    col_name
        TEXT    RX+112, r12d, rax, C_TEXT, font_s
        mov     dword [text_max], 8
        mov     rax, [col_key+8]
        movzx   edi, byte [rax + r13]
        mov     eax, 1
        call    col_name
        TEXT    RX+222, r12d, rax, C_TEXT, font_s
        mov     dword [text_max], 11
        mov     rax, [col_key+16]
        movzx   edi, byte [rax + r13]
        mov     eax, 2
        call    col_name
        TEXT    RX+294, r12d, rax, C_MUTED, font_s
        mov     dword [text_max], 0
        mov     edi, [out_w]
        add     edi, RX - 30
        mov     esi, r12d
        mov     rax, [p_monto]
        mov     edx, [rax + r13*4]
        mov     ecx, C_NUM
        lea     r8, [font_s]
        call    draw_num_right
        jmp     .nextrow
.rres:  mov     r13d, [res_order + rbp*4]
        mov     edi, [res_key + r13*4]
        call    group_name
        mov     dword [text_max], 16
        TEXT    RX+16, r12d, rax, C_TEXT, font_s
        mov     dword [text_max], 0
        mov     edi, RX+200
        mov     esi, r12d
        mov     edx, [res_count + r13*4]
        mov     ecx, C_TEXT
        lea     r8, [font_s]
        call    draw_num_right
        mov     edi, RX+320
        mov     esi, r12d
        mov     rdx, [res_sum + r13*8]
        mov     ecx, C_NUM
        lea     r8, [font_s]
        call    draw_num_right
.nextrow:
        inc     ebx
        jmp     .row

.sbar:  ; barra de desplazamiento arrastrable
        mov     eax, [view_rows]
        imul    eax, ROWH
        mov     [sb_track_h], eax
        mov     dword [sb_track_y], OY + 92
        mov     edi, [out_w]
        add     edi, RX - 18
        mov     ecx, [sb_track_h]
        mov     [rsp], edi
        HIT     edi, OY+92, 14, ecx, A_SCROLL, 0
        mov     edi, [rsp]
        add     edi, 4
        mov     ecx, [sb_track_h]
        ROUND   edi, OY+92, 6, ecx, 3, 0x232837
        mov     eax, r15d
        cmp     eax, [view_rows]
        jbe     .foot
        ; pulgar
        mov     eax, [view_rows]
        imul    eax, [sb_track_h]
        xor     edx, edx
        div     r15d
        cmp     eax, 18
        jge     .th
        mov     eax, 18
.th:    mov     r12d, eax                   ; alto del pulgar
        mov     eax, [sb_track_h]
        sub     eax, r12d
        mov     ecx, r15d
        sub     ecx, [view_rows]
        mov     r8d, [view_scroll]
        imul    rax, r8
        xor     edx, edx
        div     rcx
        add     eax, OY + 92
        mov     esi, eax
        mov     edi, [rsp]
        add     edi, 4
        mov     r9d, C_MUTED
        cmp     dword [drag_kind], 2
        jne     .tc
        mov     r9d, C_ACCENT
.tc:    mov     edx, 6
        mov     ecx, r12d
        mov     r8d, 3
        call    fill_round
.foot:  ; rango mostrado
        call    sb_reset
        SB_STR  t_rows_lbl
        mov     edi, [view_scroll]
        inc     edi
        call    sb_num
        mov     edi, '-'
        call    sb_ch
        mov     edi, [view_scroll]
        add     edi, [view_rows]
        cmp     edi, r15d
        jbe     .rr
        mov     edi, r15d
.rr:    call    sb_num
        SB_STR  t_of
        mov     edi, r15d
        call    sb_num
        SB_STR  t_scroll_hint
        mov     esi, [bot_h]
        add     esi, OY - 26
        TEXT    RX+16, esi, sb_buf, C_DIM, font_s
.out:   add     rsp, 8
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbp
        pop     rbx
        ret

; --------------------------------------------------------------------- pie
draw_footer:
        push    rbx
        mov     ebx, [scr_h]
        sub     ebx, FOOT_H - 4
        TEXT    16, ebx, t_footer, C_DIM, font_s
        call    sb_reset
        SB_STR  t_frame
        mov     rax, [frame_ns]
        add     rax, 50000
        xor     edx, edx
        mov     ecx, 100000
        div     rcx
        mov     rdi, rax
        call    sb_tenths
        SB_STR  t_ms_sep
        mov     edi, [scr_w]
        call    sb_dec
        mov     edi, 0xd7                   ; ×
        call    sb_utf8_latin1
        mov     edi, [scr_h]
        call    sb_dec
        mov     edi, [scr_w]
        sub     edi, 16
        mov     esi, ebx
        lea     rdx, [sb_buf]
        mov     ecx, C_DIM
        lea     r8, [font_s]
        call    draw_text_right
        pop     rbx
        ret

; sb_utf8_latin1(edi = codepoint 0x80..0xFF)
sb_utf8_latin1:
        push    rbx
        mov     ebx, edi
        shr     edi, 6
        or      edi, 0xC0
        call    sb_ch
        mov     edi, ebx
        and     edi, 0x3F
        or      edi, 0x80
        call    sb_ch
        pop     rbx
        ret

; ------------------------------------------------------- menu contextual
%define CTX_W   212
%define CTX_IH  28
draw_ctx:
        cmp     byte [ctx_open], 0
        je      .r
        push    rbx
        push    r12
        push    r13
        ; atrapa clicks fuera del menu
        mov     edx, [scr_w]
        mov     ecx, [scr_h]
        HIT     0, 0, edx, ecx, A_CTX, -1
        mov     r12d, [ctx_x]
        mov     r13d, [ctx_y]
        mov     eax, [scr_w]
        sub     eax, CTX_W + 8
        cmp     r12d, eax
        jle     .x
        mov     r12d, eax
.x:     mov     eax, [scr_h]
        sub     eax, 4*CTX_IH + 20
        cmp     r13d, eax
        jle     .y
        mov     r13d, eax
.y:     lea     edi, [r12-4]
        lea     esi, [r13+2]
        mov     edx, CTX_W+8
        mov     ecx, 4*CTX_IH+16
        mov     r8d, 12
        mov     r9d, 0x60000000
        call    fill_round
        ROUND   r12d, r13d, CTX_W, 4*CTX_IH+12, 9, 0x3a4152
        lea     edi, [r12+1]
        lea     esi, [r13+1]
        mov     edx, CTX_W-2
        mov     ecx, 4*CTX_IH+10
        mov     r8d, 8
        mov     r9d, 0x1f2330
        call    fill_round
        xor     ebx, ebx
.it:    cmp     ebx, 4
        jae     .done
        imul    esi, ebx, CTX_IH
        lea     esi, [r13 + rsi + 6]
        mov     [ctx_iy], esi
        ; deshabilitado: "ver entrada" sobre INPUT FILE
        mov     ecx, C_TEXT
        mov     r9d, ebx
        cmp     ebx, 1
        jne     .en
        cmp     dword [ctx_comp], 0
        jne     .en
        mov     ecx, C_DIM
        mov     r9d, -1
.en:    mov     [ctx_icol], ecx
        mov     [ctx_ipar], r9d
        mov     edi, A_CTX
        mov     esi, ebx
        call    is_hover
        jne     .nh
        cmp     dword [ctx_ipar], 0
        jl      .nh
        lea     edi, [r12+5]
        mov     esi, [ctx_iy]
        mov     edx, CTX_W-10
        mov     ecx, CTX_IH
        mov     r8d, 6
        mov     r9d, 0x3b5ba8
        call    fill_round
.nh:    lea     edi, [r12+16]
        mov     esi, [ctx_iy]
        add     esi, 5
        mov     rdx, [ctx_items + rbx*8]
        mov     ecx, [ctx_icol]
        lea     r8, [font_s]
        call    draw_text
        mov     esi, [ctx_iy]
        mov     r9d, [ctx_ipar]
        HIT     r12d, esi, CTX_W, CTX_IH, A_CTX, r9d
        inc     ebx
        jmp     .it
.done:  pop     r13
        pop     r12
        pop     rbx
.r:     ret

; --------------------------------------------------------------- tooltip
draw_tooltip:
        cmp     dword [drag_kind], 0
        jne     .r
        cmp     byte [ctx_open], 0
        jne     .r
        mov     eax, [hover_act]
        cmp     eax, A_COMP
        je      .comp
        cmp     eax, A_LINK
        je      .link
.r:     ret
.comp:  push    rbx
        mov     ebx, [hover_par]
        mov     rsi, [comp_desc + rbx*8]
        test    ebx, ebx
        jnz     .cd
        movzx   eax, byte [src_mode]
        mov     rsi, [src_desc + rax*8]
.cd:
        lea     rdi, [tt_l1]
        mov     edx, 96
        call    copy_z
        call    sb_reset
        mov     edi, ebx
        call    comp_in
        mov     edi, eax
        call    sb_num
        SB_STR  t_arrow
        mov     edi, ebx
        call    comp_out
        mov     edi, eax
        call    sb_num
        SB_STR  t_regs
        cmp     byte [run_state], 0
        jne     .c1
        test    ebx, ebx
        jz      .c1
        call    sb_reset
        SB_STR  t_tt_norun
.c1:    lea     rdi, [tt_l2]
        lea     rsi, [sb_buf]
        mov     edx, 96
        call    copy_z
        lea     rsi, [t_tt_comp_hint]
        lea     rdi, [tt_l3]
        mov     edx, 96
        call    copy_z
        pop     rbx
        jmp     tooltip_box
.link:  push    rbx
        mov     ebx, [hover_par]
        call    sb_reset
        SB_STR  t_flow
        lea     edi, [rbx + '1']
        call    sb_ch
        SB_STR  t_colon_sp
        mov     rsi, [comp_name + rbx*8]
        call    sb_str
        SB_STR  t_arrow
        mov     rsi, [comp_name + rbx*8 + 8]
        call    sb_str
        lea     rdi, [tt_l1]
        lea     rsi, [sb_buf]
        mov     edx, 96
        call    copy_z
        call    sb_reset
        cmp     byte [run_state], 0
        jne     .l1
        test    ebx, ebx
        jz      .l1
        SB_STR  t_tt_norun
        jmp     .l2
.l1:    mov     edi, ebx
        call    link_target
        mov     edi, eax
        call    sb_num
        SB_STR  t_regs
.l2:    lea     rdi, [tt_l2]
        lea     rsi, [sb_buf]
        mov     edx, 96
        call    copy_z
        lea     rsi, [t_tt_link_hint]
        lea     rdi, [tt_l3]
        mov     edx, 96
        call    copy_z
        pop     rbx
        ; fallthrough

; tooltip_box: dibuja tt_l1..3 cerca del mouse
tooltip_box:
        push    rbx
        push    r12
        push    r13
        lea     rdx, [tt_l1]
        lea     r8, [font_sb]
        call    text_width
        mov     ebx, eax
        lea     rdx, [tt_l2]
        lea     r8, [font_s]
        call    text_width
        cmp     eax, ebx
        cmovg   ebx, eax
        lea     rdx, [tt_l3]
        lea     r8, [font_s]
        call    text_width
        cmp     eax, ebx
        cmovg   ebx, eax
        add     ebx, 24                     ; ancho
        mov     r12d, [mouse_x]
        add     r12d, 16
        mov     r13d, [mouse_y]
        add     r13d, 20
        mov     eax, [scr_w]
        sub     eax, ebx
        sub     eax, 6
        cmp     r12d, eax
        jle     .x
        mov     r12d, [mouse_x]
        sub     r12d, ebx
        sub     r12d, 8
.x:     mov     eax, [scr_h]
        sub     eax, 80
        cmp     r13d, eax
        jle     .y
        mov     r13d, [mouse_y]
        sub     r13d, 84
.y:     lea     edi, [r12-2]
        lea     esi, [r13+3]
        lea     edx, [rbx+4]
        mov     ecx, 74
        mov     r8d, 10
        mov     r9d, 0x70000000
        call    fill_round
        ROUND   r12d, r13d, ebx, 70, 8, 0x4a5368
        lea     edi, [r12+1]
        lea     esi, [r13+1]
        lea     edx, [rbx-2]
        mov     ecx, 68
        mov     r8d, 7
        mov     r9d, 0x232837
        call    fill_round
        lea     edi, [r12+12]
        lea     esi, [r13+7]
        TEXT    edi, esi, tt_l1, C_WHITE, font_sb
        lea     edi, [r12+12]
        lea     esi, [r13+27]
        TEXT    edi, esi, tt_l2, C_YELLOW, font_s
        lea     edi, [r12+12]
        lea     esi, [r13+46]
        TEXT    edi, esi, tt_l3, C_MUTED, font_s
        pop     r13
        pop     r12
        pop     rbx
        ret

; ------------------------------------------------------------------- toast
draw_toast:
        mov     rax, [toast_until]
        sub     rax, [now]
        jle     .r
        push    rbx
        push    r12
        push    r13
        ; alfa: se desvanece en los ultimos 400 ms
        mov     ebx, 255
        cmp     rax, 400
        jge     .a
        imul    eax, eax, 255
        xor     edx, edx
        mov     ecx, 400
        div     ecx
        mov     ebx, eax
        test    ebx, ebx
        jnz     .a
        inc     ebx
.a:     lea     rdx, [toast_buf]
        lea     r8, [font_sb]
        call    text_width
        add     eax, 40
        mov     r12d, eax
        mov     r13d, [scr_w]
        sub     r13d, eax
        sar     r13d, 1
        mov     esi, [scr_h]
        sub     esi, FOOT_H + 56
        mov     [toast_y], esi
        mov     r9d, [toast_color]
        and     r9d, 0xFFFFFF
        mov     eax, ebx
        imul    eax, 230
        shr     eax, 8
        shl     eax, 24
        or      r9d, eax
        mov     edi, r13d
        mov     edx, r12d
        mov     ecx, 36
        mov     r8d, 18
        call    fill_round
        mov     ecx, ebx
        shl     ecx, 24
        or      ecx, 0x0f1117
        lea     edi, [r13+20]
        mov     esi, [toast_y]
        add     esi, 9
        lea     rdx, [toast_buf]
        lea     r8, [font_sb]
        call    draw_text
        pop     r13
        pop     r12
        pop     rbx
.r:     ret
