; =============================================================================
;  x11.asm -- protocolo X11 implementado a mano sobre un socket UNIX
;  conexion, auth MIT-MAGIC-COOKIE-1, setup, mapa de teclado, MIT-SHM,
;  ventana, cursores, presentacion del framebuffer y lectura de eventos.
; =============================================================================
section .text

; die(rsi = mensaje) -> stderr, exit(1)
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
        cmp     rax, -11                    ; EAGAIN
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

; try_connect(rdi = sockaddr, esi = largo) -> eax = fd o -1
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

; x_roundtrip(rsi = pedido, edx = largo, rdi = destino, ecx = capacidad)
;   envia el pedido y espera la respuesta (descarta eventos en el medio).
;   -> eax = 0 respuesta en destino, -1 si llego un error.
;   Solo se usa antes de mapear la ventana.
x_roundtrip:
        push    rbx
        push    r12
        mov     rbx, rdi
        mov     r12d, ecx
        call    write_full
.wait:  mov     rsi, rbx
        mov     edx, 32
        call    read_full
        movzx   eax, byte [rbx]
        test    eax, eax
        jz      .err
        cmp     eax, 1
        jne     .wait
        mov     edx, [rbx+4]
        shl     edx, 2
        jz      .ok
        lea     eax, [r12-32]
        cmp     edx, eax
        ja      .big
        lea     rsi, [rbx+32]
        call    read_full
.ok:    xor     eax, eax
        pop     r12
        pop     rbx
        ret
.err:   mov     eax, -1
        pop     r12
        pop     rbx
        ret
.big:   DIE     e_io

; =============================================================================
x11_init:
        call    x11_connect
        call    x11_keymap
        call    x11_framebuffer
        call    x11_create_window
        call    x11_cursors
        ; MapWindow
        lea     rdi, [req]
        mov     dword [rdi], 8 | (2 << 16)
        mov     eax, [wid]
        mov     [rdi+4], eax
        lea     rsi, [req]
        mov     edx, 8
        call    write_full
        ret

; -----------------------------------------------------------------------------
x11_connect:
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15

        ; DISPLAY=[host]:N[.S] -> N
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

        ; sockaddr_un "/tmp/.X11-unix/X<N>"
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
        ; reintento con socket abstracto "\0/tmp/.X11-unix/X<N>"
        mov     ecx, [dispnum_len]
        add     ecx, 16
        lea     rsi, [sockaddr+2]
        add     rsi, rcx
        dec     rsi
        lea     rdi, [rsi+1]
        std
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

        ; pedido de conexion (little endian, X11.0)
        lea     rdi, [req]
        xor     eax, eax
        mov     ecx, 6
        rep stosq
        mov     byte [req], 'l'
        mov     word [req+2], 11
        mov     edx, 12
        cmp     qword [auth_ptr], 0
        je      .send
        mov     word [req+6], 18
        mov     word [req+8], 16
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
        movzx   eax, byte [rsi+34]
        mov     [min_kc], eax
        movzx   eax, byte [rsi+35]
        mov     [max_kc], eax
        cmp     byte [rsi+30], 0            ; image-byte-order LSBFirst
        jne     .badvis
        movzx   r12d, byte [rsi+29]         ; formatos
        movzx   eax, word [rsi+24]          ; vendor
        add     eax, 3
        and     eax, ~3
        lea     r13, [rsi + 40 + rax]
        lea     r14, [r13 + r12*8]          ; primera pantalla
        mov     eax, [r14]
        mov     [root], eax
        movzx   eax, word [r14+20]
        mov     [root_w], eax
        movzx   eax, word [r14+22]
        mov     [root_h], eax
        movzx   r15d, byte [r14+38]
        mov     [depth], r15d
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
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret
.badvis:
        DIE     e_visual

; -----------------------------------------------------------------------------
; load_xauth: MIT-MAGIC-COOKIE-1 de $XAUTHORITY o ~/.Xauthority
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
        xor     r12d, r12d
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
        lea     r13, [authbuf + r12]
        lea     r12, [authbuf]
.entry: lea     rax, [r12+2]
        cmp     rax, r13
        ja      .none
        add     r12, 2
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
; x11_keymap: GetKeyboardMapping -> tabla keycode -> keysym
x11_keymap:
        lea     rdi, [req]
        mov     byte [rdi], 101
        mov     byte [rdi+1], 0
        mov     word [rdi+2], 2
        mov     eax, [min_kc]
        mov     [rdi+4], al
        mov     ecx, [max_kc]
        sub     ecx, eax
        inc     ecx
        mov     [rdi+5], cl
        mov     word [rdi+6], 0
        lea     rsi, [req]
        mov     edx, 8
        lea     rdi, [kmbuf]
        mov     ecx, 65536
        call    x_roundtrip
        test    eax, eax
        js      .fail
        movzx   eax, byte [kmbuf+1]
        mov     [kpk], eax
        ret
.fail:  mov     dword [kpk], 0
        ret

; keysym_of(edi = keycode, esi = state) -> eax = keysym (0 si no hay)
keysym_of:
        mov     eax, [kpk]
        test    eax, eax
        jz      .zero
        sub     edi, [min_kc]
        js      .zero
        mov     ecx, [max_kc]
        sub     ecx, [min_kc]
        cmp     edi, ecx
        ja      .zero
        imul    edi, eax
        lea     rcx, [kmbuf + 32 + rdi*4]
        test    esi, 1                      ; Shift
        jz      .base
        cmp     dword [kpk], 2
        jb      .base
        mov     eax, [rcx+4]
        test    eax, eax
        jnz     .r
.base:  mov     eax, [rcx]
.r:     ret
.zero:  xor     eax, eax
        ret

; -----------------------------------------------------------------------------
; x11_framebuffer: segmento MIT-SHM compartido con el servidor (si se puede),
; si no, memoria anonima + PutImage. Ademas, la mascara de cobertura (1 B/px).
x11_framebuffer:
        push    rbx
        push    r12
        ; dimensiones maximas
        mov     eax, [root_w]
        cmp     eax, DEF_W
        jge     .w1
        mov     eax, DEF_W
.w1:    cmp     eax, MAX_DIM
        jle     .w2
        mov     eax, MAX_DIM
.w2:    mov     [max_w], eax
        mov     eax, [root_h]
        cmp     eax, DEF_H
        jge     .h1
        mov     eax, DEF_H
.h1:    cmp     eax, MAX_DIM
        jle     .h2
        mov     eax, MAX_DIM
.h2:    mov     [max_h], eax
        mov     dword [scr_w], DEF_W
        mov     dword [scr_h], DEF_H
        mov     eax, [max_w]
        imul    eax, [max_h]
        mov     r12d, eax                   ; pixeles
        shl     rax, 2
        mov     rbx, rax                    ; bytes del framebuffer

        ; ---- QueryExtension "MIT-SHM"
        lea     rdi, [req]
        mov     byte [rdi], 98
        mov     byte [rdi+1], 0
        mov     word [rdi+2], 4
        mov     word [rdi+4], 7
        mov     word [rdi+6], 0
        mov     rax, [s_mitshm]
        mov     [rdi+8], rax
        lea     rsi, [req]
        mov     edx, 16
        lea     rdi, [rep32]
        mov     ecx, 64
        call    x_roundtrip
        test    eax, eax
        js      .noshm
        cmp     byte [rep32+8], 0
        je      .noshm
        movzx   eax, byte [rep32+9]
        mov     [shm_major], eax
        movzx   eax, byte [rep32+10]
        mov     [shm_event], eax

        ; ---- shmget + shmat
        mov     eax, SYS_SHMGET
        xor     edi, edi                    ; IPC_PRIVATE
        mov     rsi, rbx
        mov     edx, 0x380                  ; IPC_CREAT | 0600
        syscall
        test    eax, eax
        js      .noshm
        mov     [shmid], eax
        mov     eax, SYS_SHMAT
        mov     edi, [shmid]
        xor     esi, esi
        xor     edx, edx
        syscall
        cmp     rax, -4096
        ja      .rmid
        mov     [fbp], rax

        ; ---- ShmAttach + GetInputFocus como sincronizacion
        mov     eax, [id_base]
        or      eax, 3
        mov     [shmseg], eax
        lea     rdi, [req]
        mov     eax, [shm_major]
        mov     [rdi], al
        mov     byte [rdi+1], 1             ; ShmAttach
        mov     word [rdi+2], 4
        mov     eax, [shmseg]
        mov     [rdi+4], eax
        mov     eax, [shmid]
        mov     [rdi+8], eax
        mov     dword [rdi+12], 0           ; read-only = false
        mov     dword [rdi+16], 43 | (1 << 16)  ; GetInputFocus
        lea     rsi, [req]
        mov     edx, 20
        lea     rdi, [rep32]
        mov     ecx, 64
        call    x_roundtrip
        test    eax, eax
        js      .detach                     ; el servidor no pudo adjuntarlo
        ; marcar para borrar: se libera solo cuando ambos procesos se desconectan
        mov     eax, SYS_SHMCTL
        mov     edi, [shmid]
        xor     esi, esi                    ; IPC_RMID
        xor     edx, edx
        syscall
        mov     byte [use_shm], 1
        jmp     .mask
.detach:
        mov     eax, SYS_SHMDT
        mov     rdi, [fbp]
        syscall
.rmid:  mov     eax, SYS_SHMCTL
        mov     edi, [shmid]
        xor     esi, esi
        xor     edx, edx
        syscall
.noshm: mov     byte [use_shm], 0
        mov     dword [shm_event], 0
        mov     rsi, rbx
        call    mmap_anon
        mov     [fbp], rax
.mask:  mov     esi, r12d
        call    mmap_anon
        mov     [maskp], rax
        pop     r12
        pop     rbx
        ret

; mmap_anon(rsi = bytes) -> rax
mmap_anon:
        mov     eax, SYS_MMAP
        xor     edi, edi
        mov     edx, 3                      ; PROT_READ | PROT_WRITE
        mov     r10d, 0x22                  ; MAP_PRIVATE | MAP_ANONYMOUS
        mov     r8, -1
        xor     r9d, r9d
        syscall
        cmp     rax, -4096
        ja      .fail
        ret
.fail:  DIE     e_mem

; -----------------------------------------------------------------------------
; change_property(esi = property, edx = type, ecx = format, r8 = datos, r9d = n)
change_property:
        push    rbx
        push    r12
        mov     ebx, ecx
        mov     r12d, r9d
        lea     rdi, [req]
        mov     byte [rdi], 18
        mov     byte [rdi+1], 0
        mov     eax, [wid]
        mov     [rdi+4], eax
        mov     [rdi+8], esi
        mov     [rdi+12], edx
        mov     [rdi+16], bl
        mov     byte [rdi+17], 0
        mov     word [rdi+18], 0
        mov     [rdi+20], r12d
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

; intern_atom(rsi = nombre, edx = largo) -> eax
intern_atom:
        push    rbx
        mov     ebx, edx
        lea     rdi, [req]
        mov     byte [rdi], 16
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
        mov     dword [rdi], 0
        lea     edx, [rbx+3]
        and     edx, ~3
        add     edx, 8
        lea     rsi, [req]
        lea     rdi, [rep32]
        mov     ecx, 64
        call    x_roundtrip
        test    eax, eax
        js      .err
        mov     eax, [rep32+8]
        pop     rbx
        ret
.err:   DIE     e_atom

; -----------------------------------------------------------------------------
x11_create_window:
        mov     eax, [id_base]
        or      eax, 1
        mov     [wid], eax
        mov     eax, [id_base]
        or      eax, 2
        mov     [gc], eax

        lea     rdi, [req]
        mov     byte [rdi], 1               ; CreateWindow
        mov     byte [rdi+1], 0
        mov     word [rdi+2], 10
        mov     eax, [wid]
        mov     [rdi+4], eax
        mov     eax, [root]
        mov     [rdi+8], eax
        mov     dword [rdi+12], 0
        mov     eax, [scr_w]
        mov     [rdi+16], ax
        mov     eax, [scr_h]
        mov     [rdi+18], ax
        mov     word [rdi+20], 0
        mov     word [rdi+22], 1
        mov     dword [rdi+24], 0
        mov     dword [rdi+28], 0x802       ; BackPixel | EventMask
        mov     dword [rdi+32], C_BG
        ; KeyPress|ButtonPress|ButtonRelease|PointerMotion|Exposure|StructureNotify
        mov     dword [rdi+36], 0x1 | 0x4 | 0x8 | 0x40 | 0x8000 | 0x20000
        lea     rsi, [req]
        mov     edx, 40
        call    write_full

        lea     rsi, [s_wm_protocols]
        mov     edx, 12
        call    intern_atom
        mov     [atom_protocols], eax
        lea     rsi, [s_wm_delete]
        mov     edx, 16
        call    intern_atom
        mov     [atom_delete], eax
        lea     rsi, [s_net_wm_name]
        mov     edx, 12
        call    intern_atom
        mov     [atom_net_name], eax
        lea     rsi, [s_utf8_string]
        mov     edx, 11
        call    intern_atom
        mov     [atom_utf8], eax

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

        mov     esi, [atom_net_name]        ; _NET_WM_NAME (UTF-8)
        mov     edx, [atom_utf8]
        mov     ecx, 8
        lea     r8, [s_net_title]
        mov     r9d, s_net_title_len
        call    change_property

        mov     esi, 67                     ; WM_CLASS
        mov     edx, 31
        mov     ecx, 8
        lea     r8, [s_wm_class]
        mov     r9d, s_wm_class_len
        call    change_property

        ; WM_NORMAL_HINTS: tamanio minimo y maximo
        lea     rdi, [pathbuf]
        xor     eax, eax
        mov     ecx, 18
        rep stosd
        mov     dword [pathbuf], 16 | 32
        mov     dword [pathbuf+20], MIN_W
        mov     dword [pathbuf+24], MIN_H
        mov     eax, [max_w]
        mov     [pathbuf+28], eax
        mov     eax, [max_h]
        mov     [pathbuf+32], eax
        mov     esi, 40
        mov     edx, 41
        mov     ecx, 32
        lea     r8, [pathbuf]
        mov     r9d, 18
        call    change_property

        ; CreateGC
        lea     rdi, [req]
        mov     dword [rdi], 55 | (4 << 16)
        mov     eax, [gc]
        mov     [rdi+4], eax
        mov     eax, [wid]
        mov     [rdi+8], eax
        mov     dword [rdi+12], 0
        lea     rsi, [req]
        mov     edx, 16
        call    write_full
        ret

; -----------------------------------------------------------------------------
; x11_cursors: fuente de cursores del servidor (no es una dependencia nuestra)
%define CUR_ARROW       0
%define CUR_HAND        1
%define CUR_MOVE        2
%define CUR_TEXT        3
x11_cursors:
        push    rbx
        ; OpenFont "cursor"
        mov     eax, [id_base]
        or      eax, 4
        mov     [cursor_font], eax
        lea     rdi, [req]
        mov     byte [rdi], 45
        mov     byte [rdi+1], 0
        mov     word [rdi+2], 5
        mov     [rdi+4], eax
        mov     word [rdi+8], 6
        mov     word [rdi+10], 0
        mov     dword [rdi+12], 'curs'
        mov     dword [rdi+16], 'or'
        lea     rsi, [req]
        mov     edx, 20
        call    write_full
        xor     ebx, ebx
.lp:    cmp     ebx, 4
        jae     .done
        mov     eax, [id_base]
        lea     ecx, [rbx+5]
        or      eax, ecx
        mov     [cursors + rbx*4], eax
        lea     rdi, [req]
        mov     byte [rdi], 94              ; CreateGlyphCursor
        mov     byte [rdi+1], 0
        mov     word [rdi+2], 8
        mov     [rdi+4], eax
        mov     eax, [cursor_font]
        mov     [rdi+8], eax
        mov     [rdi+12], eax
        movzx   eax, word [cursor_glyphs + rbx*2]
        mov     [rdi+16], ax
        inc     eax
        mov     [rdi+18], ax
        mov     dword [rdi+20], 0           ; fore = negro
        mov     word [rdi+24], 0
        mov     word [rdi+26], 0xffff       ; back = blanco
        mov     dword [rdi+28], 0xffffffff
        lea     rsi, [req]
        mov     edx, 32
        call    write_full
        inc     ebx
        jmp     .lp
.done:  mov     dword [cur_cursor], -1
        mov     edi, CUR_ARROW
        call    set_cursor
        pop     rbx
        ret

; set_cursor(edi = indice)
set_cursor:
        cmp     edi, [cur_cursor]
        je      .r
        mov     [cur_cursor], edi
        lea     rsi, [req]
        mov     dword [rsi], 2 | (4 << 16)  ; ChangeWindowAttributes
        mov     eax, [wid]
        mov     [rsi+4], eax
        mov     dword [rsi+8], 0x4000       ; CWCursor
        mov     eax, [cursors + rdi*4]
        mov     [rsi+12], eax
        mov     edx, 16
        call    write_full
.r:     ret

; -----------------------------------------------------------------------------
; present: framebuffer -> ventana (ShmPutImage o PutImage por franjas)
present:
        push    rbx
        push    r12
        push    r13
        cmp     byte [use_shm], 0
        je      .putimage
        lea     rdi, [req]
        mov     eax, [shm_major]
        mov     [rdi], al
        mov     byte [rdi+1], 3             ; ShmPutImage
        mov     word [rdi+2], 10
        mov     eax, [wid]
        mov     [rdi+4], eax
        mov     eax, [gc]
        mov     [rdi+8], eax
        mov     eax, [scr_w]
        mov     [rdi+12], ax                ; total-width
        mov     [rdi+20], ax                ; src-width
        mov     eax, [scr_h]
        mov     [rdi+14], ax
        mov     [rdi+22], ax
        mov     dword [rdi+16], 0           ; src-x, src-y
        mov     dword [rdi+24], 0           ; dst-x, dst-y
        mov     eax, [depth]
        mov     [rdi+28], al
        mov     byte [rdi+29], 2            ; ZPixmap
        mov     byte [rdi+30], 1            ; send-event: ShmCompletion
        mov     byte [rdi+31], 0
        mov     eax, [shmseg]
        mov     [rdi+32], eax
        mov     dword [rdi+36], 0
        lea     rsi, [req]
        mov     edx, 40
        call    write_full
        mov     byte [shm_pending], 1
        mov     rax, [now]
        mov     [pend_since], rax
        jmp     .done

.putimage:
        ; filas por franja: largo maximo de pedido y limite de 16 bits
        mov     eax, [maxreq]
        cmp     eax, 65535
        jbe     .m
        mov     eax, 65535
.m:     sub     eax, 6
        xor     edx, edx
        div     dword [scr_w]
        mov     r13d, eax
        xor     ebx, ebx
.lp:    cmp     ebx, [scr_h]
        jge     .done
        mov     r12d, r13d
        mov     eax, [scr_h]
        sub     eax, ebx
        cmp     r12d, eax
        cmovg   r12d, eax
        lea     rdi, [req]
        mov     byte [rdi], 72
        mov     byte [rdi+1], 2
        mov     eax, r12d
        imul    eax, [scr_w]
        add     eax, 6
        mov     [rdi+2], ax
        mov     eax, [wid]
        mov     [rdi+4], eax
        mov     eax, [gc]
        mov     [rdi+8], eax
        mov     eax, [scr_w]
        mov     [rdi+12], ax
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
        imul    eax, [scr_w]
        mov     rsi, [fbp]
        lea     rsi, [rsi + rax*4]
        mov     edx, r12d
        imul    edx, [scr_w]
        shl     edx, 2
        call    write_full
        add     ebx, r12d
        jmp     .lp
.done:  pop     r13
        pop     r12
        pop     rbx
        ret

; -----------------------------------------------------------------------------
; read_events: lee del socket y despacha bloques de 32 bytes a ui_event
read_events:
        push    rbx
        push    r12
        mov     eax, SYS_READ
        mov     edi, [xfd]
        mov     ecx, [evlen]
        lea     rsi, [evbuf + rcx]
        mov     edx, 16384
        sub     edx, ecx
        syscall
        cmp     rax, -4
        je      .out
        cmp     rax, -11
        je      .out
        test    rax, rax
        jle     quit
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
        call    ui_event
        pop     rcx
.adv:   add     rbx, rcx
        sub     r12d, ecx
        jmp     .lp
.keep:  lea     rdi, [evbuf]
        mov     rsi, rbx
        mov     ecx, r12d
        rep movsb
        mov     [evlen], r12d
.out:   pop     r12
        pop     rbx
        ret
