; =============================================================================
;  gfx.asm -- render por software sobre el framebuffer (stride = scr_w)
;  alpha blending, rectangulos redondeados con antialias, curvas Bezier
;  con mascara de cobertura, texto con alfa de 8 bits y formateo de numeros.
;  Colores: 0xAARRGGBB, AA = 0 opaco.
; =============================================================================
section .text

; blend_pixel(rdi = ptr, esi = rgb, edx = alfa 0..256) -- clobbers eax, r8, r9
blend_pixel:
        mov     eax, [rdi]
        mov     r8d, eax
        and     eax, 0xFF00FF
        and     r8d, 0x00FF00
        mov     r9d, 256
        sub     r9d, edx
        imul    eax, r9d
        imul    r8d, r9d
        mov     r9d, esi
        and     r9d, 0xFF00FF
        imul    r9d, edx
        add     eax, r9d
        mov     r9d, esi
        and     r9d, 0x00FF00
        imul    r9d, edx
        add     r8d, r9d
        shr     eax, 8
        shr     r8d, 8
        and     eax, 0xFF00FF
        and     r8d, 0x00FF00
        or      eax, r8d
        mov     [rdi], eax
        ret

; plot_a(edi x, esi y, edx alfa 0..256, ecx rgb)
plot_a:
        cmp     edi, [scr_w]
        jae     .r
        cmp     esi, [scr_h]
        jae     .r
        mov     eax, esi
        imul    eax, [scr_w]
        add     eax, edi
        mov     rdi, [fbp]
        lea     rdi, [rdi + rax*4]
        cmp     edx, 256
        jl      .bl
        mov     [rdi], ecx
        ret
.bl:    mov     esi, ecx
        jmp     blend_pixel
.r:     ret

; fill_rect(edi x, esi y, edx w, ecx h, r8d color) -- con recorte y alfa
fill_rect:
        push    rbx
        push    r12
        push    r13
        lea     eax, [rdi+rdx]
        lea     r13d, [rsi+rcx]
        test    edi, edi
        jns     .x0
        xor     edi, edi
.x0:    test    esi, esi
        jns     .y0
        xor     esi, esi
.y0:    cmp     eax, [scr_w]
        jle     .x1
        mov     eax, [scr_w]
.x1:    cmp     r13d, [scr_h]
        jle     .y1
        mov     r13d, [scr_h]
.y1:    sub     eax, edi
        jle     .ret
        sub     r13d, esi
        jle     .ret
        mov     r11d, eax
        mov     r10d, esi
        imul    r10d, [scr_w]
        add     r10d, edi
        shl     r10, 2
        add     r10, [fbp]
        mov     r12d, [scr_w]
        shl     r12d, 2
        mov     ebx, r8d
        shr     ebx, 24
        jnz     .alpha
        mov     eax, r8d
.row:   mov     rdi, r10
        mov     ecx, r11d
        rep stosd
        add     r10, r12
        dec     r13d
        jnz     .row
        jmp     .ret
.alpha: mov     eax, ebx
        shr     eax, 7
        add     ebx, eax
        mov     esi, r8d
        and     esi, 0xFFFFFF
        mov     edx, ebx
.arow:  mov     rdi, r10
        mov     ecx, r11d
.apx:   call    blend_pixel
        add     rdi, 4
        dec     ecx
        jnz     .apx
        add     r10, r12
        dec     r13d
        jnz     .arow
.ret:   pop     r13
        pop     r12
        pop     rbx
        ret

; corner_cov(edi i, esi j, edx r) -> eax cobertura 0..256 del pixel de esquina
corner_cov:
        lea     eax, [rdx*2-1]
        sub     eax, edi
        sub     eax, edi
        lea     ecx, [rdx*2-1]
        sub     ecx, esi
        sub     ecx, esi
        imul    eax, eax
        imul    ecx, ecx
        add     eax, ecx
        cvtsi2ss xmm0, eax
        sqrtss  xmm0, xmm0                  ; 2d
        cvtsi2ss xmm1, edx
        addss   xmm1, xmm1
        addss   xmm1, [f_one]               ; 2(r + 0.5)
        subss   xmm1, xmm0
        mulss   xmm1, [f_128]
        cvttss2si eax, xmm1
        test    eax, eax
        jns     .p
        xor     eax, eax
.p:     cmp     eax, 256
        jle     .r
        mov     eax, 256
.r:     ret

; fill_round(edi x, esi y, edx w, ecx h, r8d radio, r9d color) -- antialias
%define FR_X    dword [rsp]
%define FR_Y    dword [rsp+4]
%define FR_W    dword [rsp+8]
%define FR_H    dword [rsp+12]
%define FR_R    dword [rsp+16]
%define FR_RGB  dword [rsp+20]
%define FR_A    dword [rsp+24]
%define FR_COL  dword [rsp+28]
fill_round:
        push    rbx
        push    rbp
        push    r12
        push    r13
        push    r14
        push    r15
        sub     rsp, 40
        test    edx, edx
        jle     .done
        test    ecx, ecx
        jle     .done
        mov     FR_X, edi
        mov     FR_Y, esi
        mov     FR_W, edx
        mov     FR_H, ecx
        mov     eax, edx
        cmp     eax, ecx
        cmovg   eax, ecx
        shr     eax, 1
        cmp     r8d, eax
        cmovg   r8d, eax
        test    r8d, r8d
        jns     .rok
        xor     r8d, r8d
.rok:   mov     FR_R, r8d
        mov     FR_COL, r9d
        mov     eax, r9d
        and     eax, 0xFFFFFF
        mov     FR_RGB, eax
        mov     eax, r9d
        shr     eax, 24
        jnz     .ha
        mov     eax, 256
        jmp     .sa
.ha:    mov     edx, eax
        shr     edx, 7
        add     eax, edx
.sa:    mov     FR_A, eax
        xor     ebx, ebx
.row:   cmp     ebx, FR_H
        jge     .done
        mov     r12d, FR_Y
        add     r12d, ebx
        cmp     r12d, [scr_h]
        jae     .next
        mov     eax, FR_R
        mov     r13d, -1
        cmp     ebx, eax
        jge     .bot
        mov     r13d, ebx
        jmp     .rr
.bot:   mov     ecx, FR_H
        sub     ecx, eax
        cmp     ebx, ecx
        jl      .rr
        mov     r13d, FR_H
        dec     r13d
        sub     r13d, ebx
.rr:    test    r13d, r13d
        js      .full
        xor     r14d, r14d
.cp:    cmp     r14d, FR_R
        jge     .mid
        mov     edi, r14d
        mov     esi, r13d
        mov     edx, FR_R
        call    corner_cov
        test    eax, eax
        jz      .cpn
        imul    eax, FR_A
        shr     eax, 8
        mov     r15d, eax
        mov     edi, FR_X
        add     edi, r14d
        mov     esi, r12d
        mov     edx, r15d
        mov     ecx, FR_RGB
        call    plot_a
        mov     edi, FR_X
        add     edi, FR_W
        dec     edi
        sub     edi, r14d
        mov     esi, r12d
        mov     edx, r15d
        mov     ecx, FR_RGB
        call    plot_a
.cpn:   inc     r14d
        jmp     .cp
.mid:   mov     edi, FR_X
        add     edi, FR_R
        mov     esi, r12d
        mov     edx, FR_W
        sub     edx, FR_R
        sub     edx, FR_R
        mov     ecx, 1
        mov     r8d, FR_COL
        call    fill_rect
        jmp     .next
.full:  mov     edi, FR_X
        mov     esi, r12d
        mov     edx, FR_W
        mov     ecx, 1
        mov     r8d, FR_COL
        call    fill_rect
.next:  inc     ebx
        jmp     .row
.done:  add     rsp, 40
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbp
        pop     rbx
        ret

; fill_circle(edi cx, esi cy, edx r, ecx color)
fill_circle:
        mov     r8d, edx
        mov     r9d, ecx
        sub     edi, edx
        sub     esi, edx
        lea     edx, [r8*2]
        mov     ecx, edx
        jmp     fill_round

; lerp_color(edi c1, esi c2, edx num, ecx den) -> eax (solo RGB)
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

; tri(edi x, esi y, edx dir (0 arriba, 1 abajo), ecx color) -- triangulito 7x4
tri:
        push    rbx
        push    r12
        push    r13
        push    r14
        mov     r12d, edi
        mov     r13d, esi
        mov     r14d, ecx
        mov     ebx, edx
        xor     ecx, ecx
.lp:    cmp     ecx, 4
        jae     .done
        push    rcx
        mov     edx, ecx                    ; fila k: ancho 2k+1 (arriba) o 7-2k (abajo)
        test    ebx, ebx
        jz      .up
        mov     eax, 3
        sub     eax, ecx
        mov     edx, eax
.up:    mov     edi, r12d
        add     edi, 3
        sub     edi, edx
        lea     esi, [r13+rcx]
        lea     edx, [rdx*2+1]
        mov     ecx, 1
        mov     r8d, r14d
        call    fill_rect
        pop     rcx
        inc     ecx
        jmp     .lp
.done:  pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

; -----------------------------------------------------------------------------
;  Curvas Bezier cubicas con antialias (mascara de cobertura)
; -----------------------------------------------------------------------------

; bez_point(edi t 0..1024, rsi pts[8] en px) -> eax x*16, edx y*16
bez_point:
        push    rbx
        mov     eax, 1024
        sub     eax, edi                    ; u
        mov     ecx, edi                    ; t
        mov     r8, rax
        imul    r8, rax
        imul    r8, rax                     ; u^3
        mov     r9, rax
        imul    r9, rax
        imul    r9, rcx
        imul    r9, r9, 3                   ; 3u^2 t
        mov     r10, rax
        imul    r10, rcx
        imul    r10, rcx
        imul    r10, r10, 3                 ; 3u t^2
        mov     r11, rcx
        imul    r11, rcx
        imul    r11, rcx                    ; t^3
        movsxd  rax, dword [rsi]
        imul    rax, r8
        movsxd  rbx, dword [rsi+8]
        imul    rbx, r9
        add     rax, rbx
        movsxd  rbx, dword [rsi+16]
        imul    rbx, r10
        add     rax, rbx
        movsxd  rbx, dword [rsi+24]
        imul    rbx, r11
        add     rax, rbx
        sar     rax, 26
        mov     rcx, rax
        movsxd  rax, dword [rsi+4]
        imul    rax, r8
        movsxd  rbx, dword [rsi+12]
        imul    rbx, r9
        add     rax, rbx
        movsxd  rbx, dword [rsi+20]
        imul    rbx, r10
        add     rax, rbx
        movsxd  rbx, dword [rsi+28]
        imul    rbx, r11
        add     rax, rbx
        sar     rax, 26
        mov     edx, eax
        mov     eax, ecx
        pop     rbx
        ret

; mask_disk(edi xf, esi yf, edx rf) -- coordenadas en 1/16 de pixel; max()
mask_disk:
        push    rbx
        push    rbp
        push    r12
        push    r13
        push    r14
        push    r15
        mov     r12d, edi
        mov     r13d, esi
        mov     r14d, edx
        lea     eax, [rdx+16]
        imul    eax, eax
        mov     r15d, eax                   ; (rf+16)^2: descarte rapido
        mov     eax, r14d
        add     eax, 8
        cvtsi2ss xmm2, eax                  ; rf + 8
        ; filas
        mov     ebx, r13d
        sub     ebx, r14d
        sub     ebx, 16
        sar     ebx, 4
.py:    mov     eax, r13d
        add     eax, r14d
        add     eax, 16
        sar     eax, 4
        cmp     ebx, eax
        jg      .done
        cmp     ebx, [scr_h]
        jae     .npy
        mov     eax, ebx
        shl     eax, 4
        add     eax, 8
        sub     eax, r13d
        imul    eax, eax
        mov     ebp, eax                    ; dy^2
        mov     ecx, r12d
        sub     ecx, r14d
        sub     ecx, 16
        sar     ecx, 4
.px:    mov     eax, r12d
        add     eax, r14d
        add     eax, 16
        sar     eax, 4
        cmp     ecx, eax
        jg      .npy
        cmp     ecx, [scr_w]
        jae     .npx
        mov     eax, ecx
        shl     eax, 4
        add     eax, 8
        sub     eax, r12d
        imul    eax, eax
        add     eax, ebp
        cmp     eax, r15d
        jg      .npx
        cvtsi2ss xmm0, eax
        sqrtss  xmm0, xmm0
        movaps  xmm1, xmm2
        subss   xmm1, xmm0
        mulss   xmm1, [f_16]
        cvttss2si eax, xmm1
        test    eax, eax
        jle     .npx
        cmp     eax, 255
        jle     .cv
        mov     eax, 255
.cv:    mov     edx, ebx
        imul    edx, [scr_w]
        add     edx, ecx
        mov     rdi, [maskp]
        cmp     [rdi + rdx], al
        jae     .npx
        mov     [rdi + rdx], al
.npx:   inc     ecx
        jmp     .px
.npy:   inc     ebx
        jmp     .py
.done:  pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbp
        pop     rbx
        ret

; draw_curve(rsi pts[8], edx rf (1/16 px), ecx color)
%define DC_X0   dword [rsp]
%define DC_Y0   dword [rsp+4]
%define DC_X1   dword [rsp+8]
%define DC_Y1   dword [rsp+12]
%define DC_COL  dword [rsp+16]
draw_curve:
        push    rbx
        push    rbp
        push    r12
        push    r13
        push    r14
        push    r15
        sub     rsp, 40
        mov     r12, rsi
        mov     r13d, edx
        mov     DC_COL, ecx
        ; bbox de los puntos de control (envolvente convexa)
        mov     eax, [r12]
        mov     ecx, eax
        mov     edx, [r12+4]
        mov     r8d, edx
        mov     r9d, 8
.bb:    cmp     r9d, 32
        jae     .bbd
        mov     r10d, [r12 + r9]
        cmp     r10d, eax
        cmovl   eax, r10d
        cmp     r10d, ecx
        cmovg   ecx, r10d
        mov     r10d, [r12 + r9 + 4]
        cmp     r10d, edx
        cmovl   edx, r10d
        cmp     r10d, r8d
        cmovg   r8d, r10d
        add     r9d, 8
        jmp     .bb
.bbd:   mov     r10d, r13d
        shr     r10d, 4
        add     r10d, 3
        sub     eax, r10d
        sub     edx, r10d
        add     ecx, r10d
        add     r8d, r10d
        test    eax, eax
        jns     .c1
        xor     eax, eax
.c1:    test    edx, edx
        jns     .c2
        xor     edx, edx
.c2:    cmp     ecx, [scr_w]
        jl      .c3
        mov     ecx, [scr_w]
.c3:    cmp     r8d, [scr_h]
        jl      .c4
        mov     r8d, [scr_h]
.c4:    mov     DC_X0, eax
        mov     DC_Y0, edx
        mov     DC_X1, ecx
        mov     DC_Y1, r8d
        cmp     eax, ecx
        jge     .out
        cmp     edx, r8d
        jge     .out
        ; limpiar mascara en el bbox
        mov     ebx, DC_Y0
.clr:   cmp     ebx, DC_Y1
        jge     .stamp
        mov     eax, ebx
        imul    eax, [scr_w]
        add     eax, DC_X0
        mov     rdi, [maskp]
        add     rdi, rax
        mov     ecx, DC_X1
        sub     ecx, DC_X0
        xor     eax, eax
        rep stosb
        inc     ebx
        jmp     .clr
.stamp: xor     ebx, ebx
.st:    cmp     ebx, 1024
        ja      .comp
        mov     edi, ebx
        mov     rsi, r12
        call    bez_point
        mov     edi, eax
        mov     esi, edx
        mov     edx, r13d
        call    mask_disk
        add     ebx, 4
        jmp     .st
        ; componer la mascara con el color
.comp:  mov     ebx, DC_Y0
.cy:    cmp     ebx, DC_Y1
        jge     .out
        mov     eax, ebx
        imul    eax, [scr_w]
        add     eax, DC_X0
        mov     r14d, eax                   ; indice de pixel
        mov     r15d, DC_X0
.cx:    cmp     r15d, DC_X1
        jge     .ny
        mov     rdi, [maskp]
        movzx   edx, byte [rdi + r14]
        test    edx, edx
        jz      .nx
        mov     eax, edx
        shr     eax, 7
        add     edx, eax
        mov     rdi, [fbp]
        lea     rdi, [rdi + r14*4]
        mov     esi, DC_COL
        cmp     edx, 256
        jl      .bl
        mov     [rdi], esi
        jmp     .nx
.bl:    call    blend_pixel
.nx:    inc     r14d
        inc     r15d
        jmp     .cx
.ny:    inc     ebx
        jmp     .cy
.out:   add     rsp, 40
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbp
        pop     rbx
        ret

; -----------------------------------------------------------------------------
;  Texto
; -----------------------------------------------------------------------------

; draw_char(edi x, esi y, edx codepoint, ecx color, r8 fuente)
draw_char:
        push    rbx
        push    rbp
        push    r12
        push    r13
        push    r14
        push    r15
        sub     rsp, 8
        mov     r12d, edi
        mov     r13d, esi
        mov     eax, ecx
        and     eax, 0xFFFFFF
        mov     r14d, eax
        mov     eax, ecx
        shr     eax, 24
        jnz     .ha
        mov     eax, 256
        jmp     .sa
.ha:    mov     ebp, eax
        shr     ebp, 7
        add     eax, ebp
.sa:    mov     ebp, eax
        cmp     edx, 32
        jb      .q
        cmp     edx, 255
        jbe     .ok
.q:     mov     edx, '?'
.ok:    sub     edx, 32
        mov     r10d, [r8]
        mov     r11d, [r8+4]
        mov     eax, r10d
        imul    eax, r11d
        imul    eax, edx
        mov     r15, [r8+8]
        add     r15, rax
        xor     ebx, ebx
.row:   cmp     ebx, r11d
        jge     .done
        lea     eax, [r13+rbx]
        cmp     eax, [scr_h]
        jae     .nextrow
        imul    eax, [scr_w]
        mov     [rsp], eax
        xor     ecx, ecx
.col:   cmp     ecx, r10d
        jge     .nextrow
        movzx   edx, byte [r15+rcx]
        test    edx, edx
        jz      .nc
        lea     eax, [r12+rcx]
        cmp     eax, [scr_w]
        jae     .nc
        add     eax, [rsp]
        mov     rdi, [fbp]
        lea     rdi, [rdi + rax*4]
        mov     eax, edx
        shr     eax, 7
        add     edx, eax
        cmp     ebp, 256
        je      .fa
        imul    edx, ebp
        shr     edx, 8
.fa:    cmp     edx, 256
        jl      .bl
        mov     [rdi], r14d
        jmp     .nc
.bl:    mov     esi, r14d
        call    blend_pixel
.nc:    inc     ecx
        jmp     .col
.nextrow:
        add     r15, r10
        inc     ebx
        jmp     .row
.done:  add     rsp, 8
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbp
        pop     rbx
        ret

; next_cp: UTF-8 (hasta Latin-1) en [rbx], avanza rbx -> edx (0 = fin)
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
.skip:  mov     al, [rbx]
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

; draw_text(edi x, esi y, rdx str, ecx color, r8 fuente) -> eax = x final
draw_text:
        push    rbx
        push    rbp
        push    r12
        push    r13
        push    r14
        push    r15
        mov     r12d, edi
        mov     r13d, esi
        mov     rbx, rdx
        mov     r14d, ecx
        mov     r15, r8
        xor     ebp, ebp                    ; caracteres dibujados
.lp:    mov     eax, [text_max]             ; limite opcional (0 = sin limite)
        test    eax, eax
        jz      .cp
        cmp     ebp, eax
        jae     .done
.cp:    call    next_cp
        test    edx, edx
        jz      .done
        inc     ebp
        cmp     edx, ' '
        je      .adv
        mov     edi, r12d
        mov     esi, r13d
        mov     ecx, r14d
        mov     r8, r15
        call    draw_char
.adv:   add     r12d, [r15]
        jmp     .lp
.done:  mov     eax, r12d
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbp
        pop     rbx
        ret

; text_width(rdx str, r8 fuente) -> eax
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

; draw_text_center(edi x, esi y, edx w, rcx str, r8d color, r9 fuente)
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

; draw_text_right(edi x_der, esi y, rdx str, ecx color, r8 fuente) -> eax x izq
draw_text_right:
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15
        mov     ebx, edi
        mov     r12d, esi
        mov     r13, rdx
        mov     r14d, ecx
        mov     r15, r8
        call    text_width
        sub     ebx, eax
        mov     edi, ebx
        mov     esi, r12d
        mov     rdx, r13
        mov     ecx, r14d
        mov     r8, r15
        call    draw_text
        mov     eax, ebx
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

; fmt_num_sep(rdi valor, rsi destino, edx separador o 0) -> eax largo
fmt_num_sep:
        mov     rax, rdi
        lea     r9, [numtmp]
        mov     r10d, edx
        xor     ecx, ecx
        xor     r11d, r11d
.lp:    xor     edx, edx
        mov     r8d, 10
        div     r8
        add     dl, '0'
        mov     [r9+rcx], dl
        inc     ecx
        inc     r11d
        test    rax, rax
        jz      .rev
        cmp     r11d, 3
        jne     .lp
        test    r10d, r10d
        jz      .lp
        mov     [r9+rcx], r10b
        inc     ecx
        xor     r11d, r11d
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

; fmt_num(rdi valor, rsi destino) -> eax largo (con '.' de miles)
fmt_num:
        mov     edx, '.'
        jmp     fmt_num_sep

; draw_num(edi x, esi y, rdx valor, ecx color, r8 fuente) -> eax x final
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

; draw_num_right(edi x_der, esi y, rdx valor, ecx color, r8 fuente)
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
        mov     edi, ebx
        mov     esi, r12d
        lea     rdx, [numbuf]
        mov     ecx, r13d
        mov     r8, r14
        call    draw_text_right
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

; -----------------------------------------------------------------------------
;  String builder (sb_buf)
; -----------------------------------------------------------------------------
sb_reset:
        mov     dword [sb_len], 0
        mov     byte [sb_buf], 0
        ret

; sb_str(rsi = z-string)
sb_str:
        mov     ecx, [sb_len]
.lp:    cmp     ecx, 250
        jae     .end
        mov     al, [rsi]
        test    al, al
        jz      .end
        mov     [sb_buf + rcx], al
        inc     rsi
        inc     ecx
        jmp     .lp
.end:   mov     byte [sb_buf + rcx], 0
        mov     [sb_len], ecx
        ret

; sb_num(rdi = valor) con separador de miles
sb_num:
        lea     rsi, [sbnum]
        call    fmt_num
        lea     rsi, [sbnum]
        jmp     sb_str

; sb_dec(rdi = valor) sin separador
sb_dec:
        lea     rsi, [sbnum]
        xor     edx, edx
        call    fmt_num_sep
        lea     rsi, [sbnum]
        jmp     sb_str

; sb_ch(edi = caracter)
sb_ch:
        mov     ecx, [sb_len]
        cmp     ecx, 250
        jae     .r
        mov     [sb_buf + rcx], dil
        inc     ecx
        mov     byte [sb_buf + rcx], 0
        mov     [sb_len], ecx
.r:     ret

; sb_hex(edi = valor de 32 bits)
sb_hex:
        push    rbx
        push    r12
        mov     ebx, edi
        mov     r12d, 8
.lp:    rol     ebx, 4
        mov     eax, ebx
        and     eax, 15
        movzx   edi, byte [hexdigits + rax]
        call    sb_ch
        dec     r12d
        jnz     .lp
        pop     r12
        pop     rbx
        ret

; sb_tenths(rdi = valor en decimas) -> "12,3"
sb_tenths:
        push    rbx
        mov     rax, rdi
        xor     edx, edx
        mov     ecx, 10
        div     rcx
        mov     rbx, rdx
        mov     rdi, rax
        call    sb_num
        mov     edi, ','
        call    sb_ch
        lea     edi, [rbx + '0']
        call    sb_ch
        pop     rbx
        ret

; copy_z(rdi destino, rsi origen, edx capacidad)
copy_z:
        dec     edx
.lp:    test    edx, edx
        jz      .end
        mov     al, [rsi]
        test    al, al
        jz      .end
        mov     [rdi], al
        inc     rsi
        inc     rdi
        dec     edx
        jmp     .lp
.end:   mov     byte [rdi], 0
        ret
