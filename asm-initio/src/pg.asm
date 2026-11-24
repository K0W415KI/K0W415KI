; =============================================================================
;  pg.asm -- cliente PostgreSQL nativo (protocolo v3), sin libpq
;
;  Conexion: socket UNIX (PGHOST vacio o directorio) o TCP a una IPv4.
;  Auth: trust, password, md5 y SCRAM-SHA-256 (verifica la firma del server).
;  Datos: COPY (consulta) TO STDOUT WITH (FORMAT csv, HEADER true): el
;  servidor serializa y el parser CSV paralelo hace el resto.
;  Variables: PGHOST PGPORT PGUSER PGPASSWORD PGDATABASE (como libpq).
; =============================================================================
section .text

%define PGBUF_CAP       (8 << 30)           ; 8 GiB virtuales

; ---- escritura de mensajes -------------------------------------------------
; pgw_begin(edi = tipo o 0 para startup)
pgw_begin:
        xor     eax, eax
        test    edi, edi
        jz      .s
        mov     [pgo], dil
        inc     eax
.s:     mov     [pgo_lenpos], eax
        add     eax, 4
        mov     [pgo_len], eax
        ret

; pgw_bytes(rsi = datos, edx = largo)
pgw_bytes:
        mov     ecx, edx
        mov     eax, [pgo_len]
        lea     rdi, [pgo + rax]
        add     [pgo_len], edx
        rep movsb
        ret

; pgw_z(rsi = z-string) -- incluye el terminador
pgw_z:
        mov     rdx, rsi
.l:     cmp     byte [rdx], 0
        je      .e
        inc     rdx
        jmp     .l
.e:     sub     rdx, rsi
        inc     edx
        jmp     pgw_bytes

; pgw_i32(edi = valor) big endian
pgw_i32:
        mov     eax, [pgo_len]
        bswap   edi
        mov     [pgo + rax], edi
        add     dword [pgo_len], 4
        ret

; pgw_send: completa el largo y envia
pgw_send:
        mov     eax, [pgo_len]
        sub     eax, [pgo_lenpos]
        bswap   eax
        mov     ecx, [pgo_lenpos]
        mov     [pgo + rcx], eax
        lea     rsi, [pgo]
        mov     edx, [pgo_len]
        jmp     pg_write

; pg_write(rsi, edx)
pg_write:
        push    rbx
        push    r12
        mov     rbx, rsi
        mov     r12d, edx
.lp:    test    r12d, r12d
        jz      .ok
        mov     eax, SYS_WRITE
        mov     edi, [pg_fd]
        mov     rsi, rbx
        mov     edx, r12d
        syscall
        cmp     rax, -4
        je      .lp
        test    rax, rax
        jle     .err
        add     rbx, rax
        sub     r12d, eax
        jmp     .lp
.ok:    xor     eax, eax
        pop     r12
        pop     rbx
        ret
.err:   mov     eax, -1
        pop     r12
        pop     rbx
        ret

; ---- lectura -----------------------------------------------------------------
; pg_recv(rdi = destino, rdx = n) -> eax 0 ok / -1 error
pg_recv:
        push    rbx
        push    r12
        mov     rbx, rdi
        mov     r12, rdx
.lp:    test    r12, r12
        jz      .ok
        mov     eax, [pg_rlen]
        sub     eax, [pg_rpos]
        jz      .fill
        cmp     rax, r12
        cmova   rax, r12
        mov     rcx, rax
        mov     esi, [pg_rpos]
        add     [pg_rpos], ecx
        lea     rsi, [pg_rbuf + rsi]
        mov     rdi, rbx
        add     rbx, rcx
        sub     r12, rcx
        rep movsb
        jmp     .lp
.fill:  cmp     r12, 32768                  ; lecturas grandes: directo
        jb      .buf
        mov     eax, SYS_READ
        mov     edi, [pg_fd]
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
.buf:   mov     eax, SYS_READ
        mov     edi, [pg_fd]
        lea     rsi, [pg_rbuf]
        mov     edx, 65536
        syscall
        cmp     rax, -4
        je      .lp
        test    rax, rax
        jle     .err
        mov     [pg_rlen], eax
        mov     dword [pg_rpos], 0
        jmp     .lp
.ok:    xor     eax, eax
        pop     r12
        pop     rbx
        ret
.err:   mov     eax, -1
        pop     r12
        pop     rbx
        ret

; pg_msg: lee un mensaje completo (salvo CopyData) -> pg_mtype, pg_mlen, pgmsg
;   para 'd' deja el payload sin leer. -> eax 0 ok / -1 error
pg_msg:
        lea     rdi, [pg_hdr]
        mov     edx, 5
        call    pg_recv
        test    eax, eax
        js      .r
        movzx   eax, byte [pg_hdr]
        mov     [pg_mtype], eax
        mov     eax, [pg_hdr+1]
        bswap   eax
        sub     eax, 4
        mov     [pg_mlen], eax
        cmp     byte [pg_mtype], 'd'
        je      .ok
        mov     edx, eax
        cmp     edx, 65536 - 1
        ja      .big
        lea     rdi, [pgmsg]
        call    pg_recv
        test    eax, eax
        js      .r
        mov     ecx, [pg_mlen]
        mov     byte [pgmsg + rcx], 0
.ok:    xor     eax, eax
.r:     ret
.big:   ; mensaje enorme no esperado: leerlo por partes y descartar
        push    rbx
        mov     ebx, edx
.bl:    test    ebx, ebx
        jz      .bd
        mov     edx, ebx
        cmp     edx, 65536
        jbe     .b1
        mov     edx, 65536
.b1:    sub     ebx, edx
        lea     rdi, [pgmsg]
        call    pg_recv
        test    eax, eax
        js      .be
        jmp     .bl
.bd:    mov     byte [pgmsg], 0
        pop     rbx
        xor     eax, eax
        ret
.be:    pop     rbx
        ret

; pg_error_text: arma "PostgreSQL: <mensaje>" desde un ErrorResponse -> rax
pg_error_text:
        call    sb_reset
        SB_STR  t_pg_prefix
        lea     rsi, [pgmsg]
.f:     movzx   eax, byte [rsi]
        test    eax, eax
        jz      .done
        inc     rsi
        cmp     eax, 'M'
        je      .m
.sk:    cmp     byte [rsi], 0
        je      .n
        inc     rsi
        jmp     .sk
.n:     inc     rsi
        jmp     .f
.m:     call    sb_str
.done:  lea     rax, [sb_buf]
        lea     rdi, [pg_errbuf]
        mov     rsi, rax
        mov     edx, 200
        call    copy_z
        lea     rax, [pg_errbuf]
        ret

; ---- utilidades ---------------------------------------------------------------
; getenv_def(rdi = nombre, rsi = default) -> rax
getenv_def:
        push    rsi
        call    getenv
        pop     rsi
        test    rax, rax
        jz      .d
        cmp     byte [rax], 0
        jne     .r
.d:     mov     rax, rsi
.r:     ret

; parse_ipv4(rsi = texto) -> eax (orden de red), CF=1 si invalida
parse_ipv4:
        xor     edx, edx                    ; resultado
        xor     ecx, ecx                    ; octetos
.oct:   xor     eax, eax
        xor     r8d, r8d                    ; digitos
.dg:    movzx   r9d, byte [rsi]
        sub     r9d, '0'
        cmp     r9d, 9
        ja      .end
        imul    eax, 10
        add     eax, r9d
        inc     rsi
        inc     r8d
        jmp     .dg
.end:   test    r8d, r8d
        jz      .bad
        cmp     eax, 255
        ja      .bad
        shl     eax, cl
        or      edx, eax
        add     ecx, 8
        movzx   r9d, byte [rsi]
        cmp     ecx, 32
        je      .last
        cmp     r9d, '.'
        jne     .bad
        inc     rsi
        jmp     .oct
.last:  test    r9d, r9d
        jnz     .bad
        mov     eax, edx
        clc
        ret
.bad:   stc
        ret

; ---- conexion --------------------------------------------------------------------
; pg_connect -> eax 0 ok, o rax mensaje de error
pg_connect:
        push    rbx
        push    r12
        mov     rsi, [pg_host]
        test    rsi, rsi
        jz      .unix_def
        cmp     byte [rsi], '/'
        je      .unix
        ; TCP: "localhost" o IPv4 literal (sin DNS)
        lea     rdi, [s_localhost]
        mov     rsi, [pg_host]
.cl:    mov     al, [rsi]
        cmp     al, [rdi]
        jne     .ip
        test    al, al
        jz      .lh
        inc     rsi
        inc     rdi
        jmp     .cl
.lh:    lea     rsi, [s_127]
        jmp     .ip2
.ip:    mov     rsi, [pg_host]
.ip2:   call    parse_ipv4
        jc      .badhost
        mov     word [pg_sa], 2             ; AF_INET
        mov     ecx, [pg_port]
        xchg    cl, ch
        mov     [pg_sa+2], cx
        mov     [pg_sa+4], eax
        mov     qword [pg_sa+8], 0
        mov     eax, SYS_SOCKET
        mov     edi, 2
        mov     esi, 1
        xor     edx, edx
        syscall
        test    eax, eax
        js      .fail
        mov     [pg_fd], eax
        mov     eax, SYS_CONNECT
        mov     edi, [pg_fd]
        lea     rsi, [pg_sa]
        mov     edx, 16
        syscall
        test    eax, eax
        js      .failc
        xor     eax, eax
        jmp     .out
.unix_def:
        lea     rsi, [s_pg_sockdir]
.unix:  ; ruta: dir + "/.s.PGSQL." + puerto
        mov     word [pg_sa], 1
        lea     rdi, [pg_sa+2]
.u1:    lodsb
        test    al, al
        jz      .u2
        stosb
        jmp     .u1
.u2:    lea     rsi, [s_pg_sockname]
.u3:    lodsb
        test    al, al
        jz      .u4
        stosb
        jmp     .u3
.u4:    mov     rbx, rdi
        mov     edi, [pg_port]
        lea     rsi, [numbuf]
        xor     edx, edx
        call    fmt_num_sep
        lea     rsi, [numbuf]
        mov     rdi, rbx
        lea     ecx, [rax+1]
        rep movsb
        mov     eax, SYS_SOCKET
        mov     edi, 1
        mov     esi, 1
        xor     edx, edx
        syscall
        test    eax, eax
        js      .fail
        mov     [pg_fd], eax
        mov     eax, SYS_CONNECT
        mov     edi, [pg_fd]
        lea     rsi, [pg_sa]
        mov     edx, 110
        syscall
        test    eax, eax
        js      .failc
        xor     eax, eax
        jmp     .out
.failc: push    rax
        mov     eax, SYS_CLOSE
        mov     edi, [pg_fd]
        syscall
        pop     rax
.fail:  lea     rax, [e_pg_connect]
        jmp     .out
.badhost:
        lea     rax, [e_pg_host]
.out:   pop     r12
        pop     rbx
        ret

; ---- autenticacion ---------------------------------------------------------------
; scram_first: envia SASLInitialResponse
scram_first:
        ; nonce del cliente: 18 bytes aleatorios -> 24 caracteres base64
        mov     eax, 318                    ; getrandom
        lea     rdi, [scram_rand]
        mov     esi, 18
        xor     edx, edx
        syscall
        lea     rsi, [scram_rand]
        mov     edx, 18
        lea     rdi, [scram_cnonce]
        call    b64_encode
        ; client-first-bare = "n=,r=" + cnonce
        call    sb_reset
        SB_STR  s_scram_bare
        SB_STR  scram_cnonce
        lea     rdi, [scram_bare]
        lea     rsi, [sb_buf]
        mov     edx, 128
        call    copy_z
        mov     edi, 'p'
        call    pgw_begin
        lea     rsi, [s_scram_mech]
        call    pgw_z
        mov     edi, [sb_len]
        add     edi, 3
        call    pgw_i32
        lea     rsi, [s_gs2]                ; "n,,"
        mov     edx, 3
        call    pgw_bytes
        lea     rsi, [sb_buf]
        mov     edx, [sb_len]
        call    pgw_bytes
        jmp     pgw_send

; scram_final: pgmsg+4 = server-first. Envia client-final. -> rax 0 o error
scram_final:
        push    rbx
        push    r12
        push    r13
        ; copiar server-first
        mov     ecx, [pg_mlen]
        sub     ecx, 4
        cmp     ecx, 500
        ja      .bad
        mov     [scram_sf_len], ecx
        lea     rsi, [pgmsg+4]
        lea     rdi, [scram_sf]
        rep movsb
        mov     byte [rdi], 0
        ; r=<nonce>,s=<salt>,i=<iter>
        lea     rsi, [scram_sf]
        cmp     word [rsi], 'r='
        jne     .bad
        add     rsi, 2
        mov     [scram_nonce_p], rsi
.n1:    cmp     byte [rsi], 0
        je      .bad
        cmp     byte [rsi], ','
        je      .n2
        inc     rsi
        jmp     .n1
.n2:    mov     rax, rsi
        sub     rax, [scram_nonce_p]
        mov     [scram_nonce_l], eax
        inc     rsi
        cmp     word [rsi], 's='
        jne     .bad
        add     rsi, 2
        mov     r12, rsi                    ; salt base64
.s1:    cmp     byte [rsi], 0
        je      .bad
        cmp     byte [rsi], ','
        je      .s2
        inc     rsi
        jmp     .s1
.s2:    mov     r13, rsi
        sub     r13, r12                    ; largo salt b64
        inc     rsi
        cmp     word [rsi], 'i='
        jne     .bad
        add     rsi, 2
        xor     ebx, ebx
.it:    movzx   eax, byte [rsi]
        sub     eax, '0'
        cmp     eax, 9
        ja      .itd
        imul    ebx, 10
        add     ebx, eax
        inc     rsi
        jmp     .it
.itd:   test    ebx, ebx
        jz      .bad
        cmp     ebx, 1000000
        ja      .bad
        ; el nonce del server debe empezar con el nuestro
        mov     rsi, [scram_nonce_p]
        lea     rdi, [scram_cnonce]
        mov     ecx, 24
        repe cmpsb
        jne     .bad
        ; SaltedPassword = PBKDF2(password, salt, i)
        mov     rsi, r12
        mov     edx, r13d
        lea     rdi, [scram_salt]
        call    b64_decode
        cmp     eax, 128
        ja      .bad
        mov     ecx, eax
        mov     rdi, [pg_pass]
        mov     rsi, rdi
.pl:    cmp     byte [rsi], 0
        je      .pld
        inc     rsi
        jmp     .pl
.pld:   sub     rsi, rdi
        lea     rdx, [scram_salt]
        mov     r8d, ebx
        lea     r9, [scram_salted]
        call    pbkdf2_sha256
        ; client-final-without-proof = "c=biws,r=" + nonce
        call    sb_reset
        SB_STR  s_scram_cbind
        mov     rsi, [scram_nonce_p]
        mov     ecx, [scram_nonce_l]
        lea     rdi, [scram_tmp]
        rep movsb
        mov     byte [rdi], 0
        SB_STR  scram_tmp
        lea     rdi, [scram_cfwp]
        lea     rsi, [sb_buf]
        mov     edx, 256
        call    copy_z
        ; AuthMessage = bare + "," + server-first + "," + cfwp
        call    sb_reset
        SB_STR  scram_bare
        mov     edi, ','
        call    sb_ch
        lea     rdi, [scram_auth]
        lea     rsi, [sb_buf]
        mov     edx, 1024
        call    copy_z
        mov     ebx, [sb_len]
        lea     rdi, [scram_auth + rbx]
        lea     rsi, [scram_sf]
        mov     ecx, [scram_sf_len]
        add     ebx, ecx
        rep movsb
        mov     byte [rdi], ','
        inc     rdi
        inc     ebx
        lea     rsi, [scram_cfwp]
.am:    lodsb
        test    al, al
        jz      .amd
        stosb
        inc     ebx
        jmp     .am
.amd:   mov     [scram_auth_len], ebx
        ; ClientKey, StoredKey, ClientSignature, ClientProof
        lea     rdi, [scram_salted]
        mov     esi, 32
        lea     rdx, [s_client_key]
        mov     ecx, 10
        lea     r8, [scram_ckey]
        call    hmac_sha256
        lea     rsi, [scram_ckey]
        mov     edx, 32
        lea     rdi, [scram_skey]
        call    sha256
        lea     rdi, [scram_skey]
        mov     esi, 32
        lea     rdx, [scram_auth]
        mov     ecx, [scram_auth_len]
        lea     r8, [scram_csig]
        call    hmac_sha256
        xor     ecx, ecx
.xp:    mov     rax, [scram_ckey + rcx*8]
        xor     rax, [scram_csig + rcx*8]
        mov     [scram_proof + rcx*8], rax
        inc     ecx
        cmp     ecx, 4
        jb      .xp
        ; ServerSignature esperada (se verifica en SASLFinal)
        lea     rdi, [scram_salted]
        mov     esi, 32
        lea     rdx, [s_server_key]
        mov     ecx, 10
        lea     r8, [scram_srvkey]
        call    hmac_sha256
        lea     rdi, [scram_srvkey]
        mov     esi, 32
        lea     rdx, [scram_auth]
        mov     ecx, [scram_auth_len]
        lea     r8, [scram_ssig]
        call    hmac_sha256
        lea     rsi, [scram_ssig]
        mov     edx, 32
        lea     rdi, [scram_ssig64]
        call    b64_encode
        ; client-final = cfwp + ",p=" + base64(proof)
        lea     rsi, [scram_proof]
        mov     edx, 32
        lea     rdi, [scram_tmp]
        call    b64_encode
        mov     edi, 'p'
        call    pgw_begin
        lea     rsi, [scram_cfwp]
        call    pgw_z
        dec     dword [pgo_len]             ; sin terminador
        lea     rsi, [s_scram_p]
        mov     edx, 3
        call    pgw_bytes
        lea     rsi, [scram_tmp]
        mov     edx, 44
        call    pgw_bytes
        call    pgw_send
        xor     eax, eax
        jmp     .out
.bad:   lea     rax, [e_pg_scram]
.out:   pop     r13
        pop     r12
        pop     rbx
        ret

; md5_response: "md5" + md5hex(md5hex(password + user) + salt)
md5_response:
        push    rbx
        lea     rdi, [scram_tmp]            ; password + user
        mov     rsi, [pg_pass]
.a:     lodsb
        test    al, al
        jz      .b
        stosb
        jmp     .a
.b:     mov     rsi, [pg_user]
.c:     lodsb
        test    al, al
        jz      .d
        stosb
        jmp     .c
.d:     lea     rsi, [scram_tmp]
        mov     rdx, rdi
        sub     rdx, rsi
        lea     rdi, [scram_ckey]
        call    md5
        lea     rsi, [scram_ckey]
        mov     ecx, 16
        lea     rdi, [scram_tmp]
        call    hex_lower
        mov     eax, [pgmsg+4]              ; salt
        mov     [scram_tmp+32], eax
        lea     rsi, [scram_tmp]
        mov     edx, 36
        lea     rdi, [scram_ckey]
        call    md5
        mov     dword [scram_tmp], 'md5'
        lea     rsi, [scram_ckey]
        mov     ecx, 16
        lea     rdi, [scram_tmp+3]
        call    hex_lower
        mov     byte [scram_tmp+35], 0
        mov     edi, 'p'
        call    pgw_begin
        lea     rsi, [scram_tmp]
        call    pgw_z
        call    pgw_send
        pop     rbx
        ret

; ---- carga -------------------------------------------------------------------
; pg_load -> rax = 0 ok o mensaje de error
pg_load:
        push    rbx
        push    r12
        push    r13
        push    r14
        call    now_ns
        mov     r14, rax
        ; parametros estilo libpq
        lea     rdi, [s_PGHOST]
        xor     esi, esi
        call    getenv_def
        mov     [pg_host], rax
        lea     rdi, [s_USER]
        lea     rsi, [s_postgres]
        call    getenv_def
        mov     rsi, rax
        lea     rdi, [s_PGUSER]
        call    getenv_def
        mov     [pg_user], rax
        mov     rsi, rax
        lea     rdi, [s_PGDATABASE]
        call    getenv_def
        mov     [pg_db], rax
        lea     rdi, [s_PGPASSWORD]
        lea     rsi, [s_emptystr]
        call    getenv_def
        mov     [pg_pass], rax
        mov     dword [pg_port], 5432
        lea     rdi, [s_PGPORT]
        call    getenv
        test    rax, rax
        jz      .port
        xor     ecx, ecx
.pp:    movzx   edx, byte [rax]
        sub     edx, '0'
        cmp     edx, 9
        ja      .ppd
        imul    ecx, 10
        add     ecx, edx
        inc     rax
        jmp     .pp
.ppd:   test    ecx, ecx
        jz      .port
        mov     [pg_port], ecx
.port:  mov     rax, [opt_pgquery]
        test    rax, rax
        jnz     .q
        lea     rax, [s_pg_defquery]
        mov     [opt_pgquery], rax
.q:     mov     dword [pg_rpos], 0
        mov     dword [pg_rlen], 0
        lea     rax, [t_auth_trust]
        mov     [pg_auth_name], rax

        call    pg_connect
        test    rax, rax
        jnz     .ret

        ; StartupMessage
        xor     edi, edi
        call    pgw_begin
        mov     edi, 196608                 ; protocolo 3.0
        call    pgw_i32
        lea     rsi, [s_user_k]
        call    pgw_z
        mov     rsi, [pg_user]
        call    pgw_z
        lea     rsi, [s_db_k]
        call    pgw_z
        mov     rsi, [pg_db]
        call    pgw_z
        lea     rsi, [s_app_k]
        call    pgw_z
        lea     rsi, [s_app_v]
        call    pgw_z
        lea     rsi, [s_enc_k]
        call    pgw_z
        lea     rsi, [s_enc_v]
        call    pgw_z
        lea     rsi, [s_emptystr]
        call    pgw_z
        call    pgw_send

.auth:  call    pg_msg
        test    eax, eax
        js      .eio
        mov     eax, [pg_mtype]
        cmp     eax, 'E'
        je      .err
        cmp     eax, 'Z'
        je      .ready
        cmp     eax, 'R'
        jne     .auth                       ; S, K, N: ignorar
        mov     eax, [pgmsg]
        bswap   eax
        test    eax, eax
        jz      .auth                       ; AuthenticationOk
        cmp     eax, 3
        je      .clear
        cmp     eax, 5
        je      .md5
        cmp     eax, 10
        je      .sasl
        cmp     eax, 11
        je      .sasl_cont
        cmp     eax, 12
        je      .sasl_final
        lea     rax, [e_pg_auth]
        jmp     .close
.clear: lea     rax, [t_auth_clear]
        mov     [pg_auth_name], rax
        mov     edi, 'p'
        call    pgw_begin
        mov     rsi, [pg_pass]
        call    pgw_z
        call    pgw_send
        jmp     .auth
.md5:   lea     rax, [t_auth_md5]
        mov     [pg_auth_name], rax
        call    md5_response
        jmp     .auth
.sasl:  ; lista de mecanismos: buscar SCRAM-SHA-256
        lea     rsi, [pgmsg+4]
.ml:    cmp     byte [rsi], 0
        je      .nomech
        lea     rdi, [s_scram_mech]
        mov     rbx, rsi
.mc:    mov     al, [rsi]
        cmp     al, [rdi]
        jne     .mn
        test    al, al
        jz      .mok
        inc     rsi
        inc     rdi
        jmp     .mc
.mn:    mov     rsi, rbx
.ms:    lodsb
        test    al, al
        jnz     .ms
        jmp     .ml
.nomech:
        lea     rax, [e_pg_auth]
        jmp     .close
.mok:   lea     rax, [t_auth_scram]
        mov     [pg_auth_name], rax
        call    scram_first
        jmp     .auth
.sasl_cont:
        call    scram_final
        test    rax, rax
        jnz     .close
        jmp     .auth
.sasl_final:
        ; "v=<firma>": debe coincidir con la que calculamos
        cmp     word [pgmsg+4], 'v='
        jne     .badsig
        lea     rsi, [pgmsg+6]
        lea     rdi, [scram_ssig64]
        mov     ecx, 44
        repe cmpsb
        jne     .badsig
        jmp     .auth
.badsig:
        lea     rax, [e_pg_sig]
        jmp     .close

.ready: ; Query: COPY (consulta) TO STDOUT WITH (FORMAT csv, HEADER true)
        mov     edi, 'Q'
        call    pgw_begin
        lea     rsi, [s_copy_pre]
        call    pgw_z
        dec     dword [pgo_len]
        mov     rsi, [opt_pgquery]
        call    pgw_z
        dec     dword [pgo_len]
        lea     rsi, [s_copy_post]
        call    pgw_z
        call    pgw_send
        ; buffer de recepcion
        cmp     qword [pgbuf], 0
        jne     .hb
        mov     rsi, PGBUF_CAP
        call    mmap_reserve
        mov     [pgbuf], rax
.hb:    xor     r12d, r12d                  ; bytes recibidos
.copy:  call    pg_msg
        test    eax, eax
        js      .eio
        mov     eax, [pg_mtype]
        cmp     eax, 'd'
        je      .data
        cmp     eax, 'E'
        je      .err
        cmp     eax, 'Z'
        je      .done
        jmp     .copy                       ; H, c, C, N
.data:  mov     edx, [pg_mlen]
        lea     rax, [r12 + rdx]
        mov     rcx, PGBUF_CAP
        cmp     rax, rcx
        ja      .toobig
        mov     rdi, [pgbuf]
        add     rdi, r12
        add     r12, rdx
        call    pg_recv
        test    eax, eax
        js      .eio
        jmp     .copy
.done:  mov     edi, 'X'                    ; Terminate
        call    pgw_begin
        call    pgw_send
        mov     eax, SYS_CLOSE
        mov     edi, [pg_fd]
        syscall
        test    r12, r12
        jz      .noresult
        mov     [load_bytes], r12
        mov     rsi, [pgbuf]
        mov     rdx, r12
        call    parse_csv_buffer
        test    rax, rax
        jnz     .ret
        ; devolver la memoria del buffer (se vuelve a pedir al recargar)
        mov     eax, 28                     ; madvise(MADV_DONTNEED)
        mov     rdi, [pgbuf]
        mov     rsi, r12
        add     rsi, 4095
        and     rsi, -4096
        mov     edx, 4
        syscall
        call    now_ns
        sub     rax, r14
        mov     [load_ns], rax
        mov     byte [src_mode], 2
        call    sb_reset
        SB_STR  t_pg_short
        mov     rsi, [pg_db]
        call    sb_str
        lea     rdi, [src_short]
        lea     rsi, [sb_buf]
        mov     edx, 18
        call    copy_z
        xor     eax, eax
        jmp     .ret
.noresult:
        lea     rax, [e_pg_empty]
        jmp     .ret
.toobig:
        lea     rax, [e_csv_big]
        jmp     .close
.eio:   lea     rax, [e_pg_io]
        jmp     .close
.err:   call    pg_error_text
.close: push    rax
        mov     eax, SYS_CLOSE
        mov     edi, [pg_fd]
        syscall
        pop     rax
.ret:   pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret
