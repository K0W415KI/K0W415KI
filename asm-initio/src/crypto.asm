; =============================================================================
;  crypto.asm -- SHA-256, HMAC-SHA-256, PBKDF2, MD5, base64 y hex
;  Lo minimo para autenticar contra PostgreSQL (SCRAM-SHA-256 y md5).
; =============================================================================
section .text

; contexto SHA-256: h[8] (0), buf[64] (32), blen (96), total bytes (104)
%define SHA_CTX 112

; sha256_init(rdi = ctx)
sha256_init:
        lea     rsi, [sha_h0]
        mov     ecx, 8
.lp:    mov     eax, [rsi]
        mov     [rdi], eax
        add     rsi, 4
        add     rdi, 4
        dec     ecx
        jnz     .lp
        mov     dword [rdi-32+96], 0
        mov     qword [rdi-32+104], 0
        ret

; sha256_block(rdi = ctx, rsi = bloque de 64 bytes)
sha256_block:
        push    rbx
        push    rbp
        push    r12
        push    r13
        push    r14
        push    r15
        sub     rsp, 264
        xor     ecx, ecx
.w0:    mov     eax, [rsi + rcx*4]
        bswap   eax
        mov     [rsp + rcx*4], eax
        inc     ecx
        cmp     ecx, 16
        jb      .w0
.w1:    mov     eax, [rsp + rcx*4 - 60]     ; W[i-15]
        mov     ebx, eax
        ror     ebx, 7
        mov     edx, eax
        ror     edx, 18
        xor     ebx, edx
        shr     eax, 3
        xor     ebx, eax                    ; s0
        mov     eax, [rsp + rcx*4 - 8]      ; W[i-2]
        mov     ebp, eax
        ror     ebp, 17
        mov     edx, eax
        ror     edx, 19
        xor     ebp, edx
        shr     eax, 10
        xor     ebp, eax                    ; s1
        mov     eax, [rsp + rcx*4 - 64]     ; W[i-16]
        add     eax, ebx
        add     eax, [rsp + rcx*4 - 28]     ; W[i-7]
        add     eax, ebp
        mov     [rsp + rcx*4], eax
        inc     ecx
        cmp     ecx, 64
        jb      .w1
        mov     r8d, [rdi]
        mov     r9d, [rdi+4]
        mov     r10d, [rdi+8]
        mov     r11d, [rdi+12]
        mov     r12d, [rdi+16]
        mov     r13d, [rdi+20]
        mov     r14d, [rdi+24]
        mov     r15d, [rdi+28]
        xor     ebp, ebp
.r:     mov     eax, r12d
        ror     eax, 6
        mov     ebx, r12d
        ror     ebx, 11
        xor     eax, ebx
        mov     ebx, r12d
        ror     ebx, 25
        xor     eax, ebx                    ; S1
        mov     ebx, r12d
        and     ebx, r13d
        mov     ecx, r12d
        not     ecx
        and     ecx, r14d
        xor     ebx, ecx                    ; ch
        add     eax, ebx
        add     eax, r15d
        add     eax, [sha_k + rbp*4]
        add     eax, [rsp + rbp*4]          ; t1
        mov     ebx, r8d
        ror     ebx, 2
        mov     ecx, r8d
        ror     ecx, 13
        xor     ebx, ecx
        mov     ecx, r8d
        ror     ecx, 22
        xor     ebx, ecx                    ; S0
        mov     ecx, r8d
        and     ecx, r9d
        mov     edx, r8d
        and     edx, r10d
        xor     ecx, edx
        mov     edx, r9d
        and     edx, r10d
        xor     ecx, edx                    ; maj
        add     ebx, ecx                    ; t2
        mov     r15d, r14d
        mov     r14d, r13d
        mov     r13d, r12d
        lea     r12d, [r11 + rax]
        mov     r11d, r10d
        mov     r10d, r9d
        mov     r9d, r8d
        lea     r8d, [rax + rbx]
        inc     ebp
        cmp     ebp, 64
        jb      .r
        add     [rdi], r8d
        add     [rdi+4], r9d
        add     [rdi+8], r10d
        add     [rdi+12], r11d
        add     [rdi+16], r12d
        add     [rdi+20], r13d
        add     [rdi+24], r14d
        add     [rdi+28], r15d
        add     rsp, 264
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbp
        pop     rbx
        ret

; sha256_update(rdi = ctx, rsi = datos, rdx = largo)
sha256_update:
        push    rbx
        push    r12
        push    r13
        mov     rbx, rdi
        mov     r12, rsi
        mov     r13, rdx
        add     [rbx+104], r13
.lp:    test    r13, r13
        jz      .done
        mov     eax, [rbx+96]
        mov     ecx, 64
        sub     ecx, eax
        cmp     r13, rcx
        cmovb   rcx, r13
        lea     rdi, [rbx + 32 + rax]
        mov     rsi, r12
        add     r12, rcx
        sub     r13, rcx
        add     [rbx+96], ecx
        rep movsb
        cmp     dword [rbx+96], 64
        jne     .lp
        mov     rdi, rbx
        lea     rsi, [rbx+32]
        call    sha256_block
        mov     dword [rbx+96], 0
        jmp     .lp
.done:  pop     r13
        pop     r12
        pop     rbx
        ret

; sha256_final(rdi = ctx, rsi = salida de 32 bytes)
sha256_final:
        push    rbx
        push    r12
        sub     rsp, 24
        mov     rbx, rdi
        mov     r12, rsi
        mov     rax, [rbx+104]
        shl     rax, 3
        bswap   rax
        mov     [rsp], rax
        mov     rdi, rbx
        lea     rsi, [sha_pad80]
        mov     edx, 1
        call    sha256_update
.pad:   cmp     dword [rbx+96], 56
        je      .len
        mov     rdi, rbx
        lea     rsi, [sha_zero]
        mov     edx, 1
        call    sha256_update
        jmp     .pad
.len:   mov     rdi, rbx
        mov     rsi, rsp
        mov     edx, 8
        call    sha256_update
        xor     ecx, ecx
.out:   mov     eax, [rbx + rcx*4]
        bswap   eax
        mov     [r12 + rcx*4], eax
        inc     ecx
        cmp     ecx, 8
        jb      .out
        add     rsp, 24
        pop     r12
        pop     rbx
        ret

; sha256(rsi = datos, rdx = largo, rdi = salida)
sha256:
        push    rbx
        push    r12
        push    r13
        sub     rsp, SHA_CTX + 8
        mov     rbx, rdi
        mov     r12, rsi
        mov     r13, rdx
        mov     rdi, rsp
        call    sha256_init
        mov     rdi, rsp
        mov     rsi, r12
        mov     rdx, r13
        call    sha256_update
        mov     rdi, rsp
        mov     rsi, rbx
        call    sha256_final
        add     rsp, SHA_CTX + 8
        pop     r13
        pop     r12
        pop     rbx
        ret

; hmac_sha256(rdi = clave, esi = largo clave, rdx = msg, ecx = largo msg, r8 = salida)
;   la salida puede coincidir con msg
hmac_sha256:
        push    rbx
        push    rbp
        push    r12
        push    r13
        push    r14
        sub     rsp, 64 + 32 + SHA_CTX + 8  ; kb[64], inner[32], ctx
        mov     r12, rdx
        mov     r13d, ecx
        mov     r14, r8
        ; bloque de clave
        lea     rbx, [rsp]
        xor     eax, eax
        mov     ecx, 8
        push    rdi
        mov     rdi, rbx
        rep stosq
        pop     rdi
        cmp     esi, 64
        jbe     .copy
        mov     rsi, rdi
        mov     edx, esi
        mov     rdi, rbx
        call    sha256
        jmp     .kdone
.copy:  mov     ecx, esi
        mov     rsi, rdi
        mov     rdi, rbx
        rep movsb
.kdone: lea     rbp, [rsp + 96]             ; ctx
        ; inner = H((K ^ ipad) || msg)
        xor     ecx, ecx
.ip:    xor     byte [rbx + rcx], 0x36
        inc     ecx
        cmp     ecx, 64
        jb      .ip
        mov     rdi, rbp
        call    sha256_init
        mov     rdi, rbp
        mov     rsi, rbx
        mov     edx, 64
        call    sha256_update
        mov     rdi, rbp
        mov     rsi, r12
        mov     edx, r13d
        call    sha256_update
        mov     rdi, rbp
        lea     rsi, [rsp + 64]
        call    sha256_final
        ; outer = H((K ^ opad) || inner)
        xor     ecx, ecx
.op:    xor     byte [rbx + rcx], 0x36 ^ 0x5c
        inc     ecx
        cmp     ecx, 64
        jb      .op
        mov     rdi, rbp
        call    sha256_init
        mov     rdi, rbp
        mov     rsi, rbx
        mov     edx, 64
        call    sha256_update
        mov     rdi, rbp
        lea     rsi, [rsp + 64]
        mov     edx, 32
        call    sha256_update
        mov     rdi, rbp
        mov     rsi, r14
        call    sha256_final
        add     rsp, 64 + 32 + SHA_CTX + 8
        pop     r14
        pop     r13
        pop     r12
        pop     rbp
        pop     rbx
        ret

; pbkdf2_sha256(rdi = pass, esi = largo, rdx = salt, ecx = largo salt (<=128),
;               r8d = iteraciones, r9 = salida de 32 bytes)
pbkdf2_sha256:
        push    rbx
        push    rbp
        push    r12
        push    r13
        push    r14
        push    r15
        sub     rsp, 136 + 32 + 8           ; salt||INT(1), U
        mov     r12, rdi
        mov     r13d, esi
        mov     r14d, r8d
        mov     r15, r9
        ; salt || 00 00 00 01
        mov     ebx, ecx
        mov     rsi, rdx
        mov     rdi, rsp
        rep movsb
        mov     dword [rsp + rbx], 0x01000000
        lea     ecx, [rbx + 4]
        mov     rdi, r12
        mov     esi, r13d
        mov     rdx, rsp
        lea     r8, [rsp + 136]             ; U
        call    hmac_sha256
        ; T = U
        lea     rsi, [rsp + 136]
        mov     rdi, r15
        mov     ecx, 32
        rep movsb
        mov     ebp, 1
.it:    cmp     ebp, r14d
        jae     .done
        mov     rdi, r12
        mov     esi, r13d
        lea     rdx, [rsp + 136]
        mov     ecx, 32
        lea     r8, [rsp + 136]
        call    hmac_sha256
        xor     ecx, ecx
.x:     mov     rax, [rsp + 136 + rcx*8]
        xor     [r15 + rcx*8], rax
        inc     ecx
        cmp     ecx, 4
        jb      .x
        inc     ebp
        jmp     .it
.done:  add     rsp, 136 + 32 + 8
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbp
        pop     rbx
        ret

; -----------------------------------------------------------------------------
; md5_block(rdi = estado[4], rsi = bloque de 64 bytes)
md5_block:
        push    rbx
        push    rbp
        push    r12
        push    r13
        push    r14
        push    r15
        mov     r8d, [rdi]                  ; a
        mov     r9d, [rdi+4]                ; b
        mov     r10d, [rdi+8]               ; c
        mov     r11d, [rdi+12]              ; d
        xor     ebp, ebp
.r:     cmp     ebp, 16
        jb      .f0
        cmp     ebp, 32
        jb      .f1
        cmp     ebp, 48
        jb      .f2
        mov     eax, r11d                   ; I: c ^ (b | ~d)
        not     eax
        or      eax, r9d
        xor     eax, r10d
        jmp     .f
.f0:    mov     eax, r9d                    ; F: (b & c) | (~b & d)
        and     eax, r10d
        mov     ebx, r9d
        not     ebx
        and     ebx, r11d
        or      eax, ebx
        jmp     .f
.f1:    mov     eax, r11d                   ; G: (d & b) | (~d & c)
        and     eax, r9d
        mov     ebx, r11d
        not     ebx
        and     ebx, r10d
        or      eax, ebx
        jmp     .f
.f2:    mov     eax, r9d                    ; H: b ^ c ^ d
        xor     eax, r10d
        xor     eax, r11d
.f:     add     eax, r8d
        add     eax, [md5_k + rbp*4]
        movzx   ebx, byte [md5_g + rbp]
        add     eax, [rsi + rbx*4]
        movzx   ecx, byte [md5_s + rbp]
        rol     eax, cl
        add     eax, r9d
        mov     r8d, r11d
        mov     r11d, r10d
        mov     r10d, r9d
        mov     r9d, eax
        inc     ebp
        cmp     ebp, 64
        jb      .r
        add     [rdi], r8d
        add     [rdi+4], r9d
        add     [rdi+8], r10d
        add     [rdi+12], r11d
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbp
        pop     rbx
        ret

; md5(rsi = datos, rdx = largo, rdi = salida de 16 bytes)
md5:
        push    rbx
        push    r12
        push    r13
        push    r14
        sub     rsp, 16 + 128 + 8           ; estado, cola
        mov     r12, rsi
        mov     r13, rdx
        mov     r14, rdi
        mov     dword [rsp], 0x67452301
        mov     dword [rsp+4], 0xefcdab89
        mov     dword [rsp+8], 0x98badcfe
        mov     dword [rsp+12], 0x10325476
        mov     rbx, r13
.full:  cmp     rbx, 64
        jb      .tail
        mov     rdi, rsp
        mov     rsi, r12
        call    md5_block
        add     r12, 64
        sub     rbx, 64
        jmp     .full
.tail:  lea     rdi, [rsp+16]
        xor     eax, eax
        mov     ecx, 16
        rep stosq
        lea     rdi, [rsp+16]
        mov     rsi, r12
        mov     ecx, ebx
        rep movsb
        mov     byte [rsp + 16 + rbx], 0x80
        mov     rax, r13
        shl     rax, 3
        mov     ecx, 56
        cmp     ebx, 56
        jb      .one
        add     ecx, 64
.one:   mov     [rsp + 16 + rcx], rax
        lea     rsi, [rsp+16]
        mov     rdi, rsp
        call    md5_block
        cmp     ebx, 56
        jb      .out
        lea     rsi, [rsp+80]
        mov     rdi, rsp
        call    md5_block
.out:   mov     rax, [rsp]
        mov     [r14], rax
        mov     rax, [rsp+8]
        mov     [r14+8], rax
        add     rsp, 16 + 128 + 8
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

; hex_lower(rsi = bytes, ecx = largo, rdi = destino) -- sin terminador
hex_lower:
.lp:    test    ecx, ecx
        jz      .r
        movzx   eax, byte [rsi]
        mov     edx, eax
        shr     eax, 4
        movzx   eax, byte [hexlower + rax]
        mov     [rdi], al
        and     edx, 15
        movzx   edx, byte [hexlower + rdx]
        mov     [rdi+1], dl
        inc     rsi
        add     rdi, 2
        dec     ecx
        jmp     .lp
.r:     ret

; b64_encode(rsi = src, edx = largo, rdi = dst) -> eax largo (con terminador 0)
b64_encode:
        push    rbx
        mov     r8, rdi
.lp:    cmp     edx, 3
        jb      .tail
        movzx   eax, byte [rsi]
        shl     eax, 16
        movzx   ebx, byte [rsi+1]
        shl     ebx, 8
        or      eax, ebx
        movzx   ebx, byte [rsi+2]
        or      eax, ebx
        call    .emit4
        add     rsi, 3
        sub     edx, 3
        jmp     .lp
.tail:  test    edx, edx
        jz      .end
        movzx   eax, byte [rsi]
        shl     eax, 16
        cmp     edx, 2
        jb      .t1
        movzx   ebx, byte [rsi+1]
        shl     ebx, 8
        or      eax, ebx
.t1:    call    .emit4
        mov     byte [rdi-1], '='
        cmp     edx, 2
        je      .end
        mov     byte [rdi-2], '='
.end:   mov     byte [rdi], 0
        mov     rax, rdi
        sub     rax, r8
        pop     rbx
        ret
.emit4: mov     ecx, 18
.e:     mov     ebx, eax
        shr     ebx, cl
        and     ebx, 63
        movzx   ebx, byte [b64chars + rbx]
        mov     [rdi], bl
        inc     rdi
        sub     ecx, 6
        jns     .e
        ret

; b64_decode(rsi = src, edx = largo, rdi = dst) -> eax bytes
b64_decode:
        push    rbx
        push    r12
        mov     r8, rdi
        xor     eax, eax                    ; acumulador
        xor     r12d, r12d                  ; bits
.lp:    test    edx, edx
        jz      .end
        movzx   ebx, byte [rsi]
        inc     rsi
        dec     edx
        cmp     bl, '='
        je      .end
        ; valor del caracter
        lea     ecx, [rbx - 'A']
        cmp     ecx, 26
        jb      .v
        lea     ecx, [rbx - 'a' + 26]
        cmp     ebx, 'a'
        jb      .n1
        cmp     ebx, 'z'
        jbe     .v
.n1:    lea     ecx, [rbx - '0' + 52]
        cmp     ebx, '0'
        jb      .n2
        cmp     ebx, '9'
        jbe     .v
.n2:    mov     ecx, 62
        cmp     ebx, '+'
        je      .v
        mov     ecx, 63
        cmp     ebx, '/'
        jne     .lp
.v:     shl     eax, 6
        or      eax, ecx
        add     r12d, 6
        cmp     r12d, 8
        jb      .lp
        sub     r12d, 8
        mov     ecx, r12d
        mov     ebx, eax
        shr     ebx, cl
        mov     [rdi], bl
        inc     rdi
        jmp     .lp
.end:   mov     rax, rdi
        sub     rax, r8
        pop     r12
        pop     rbx
        ret
