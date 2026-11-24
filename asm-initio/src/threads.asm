; =============================================================================
;  threads.asm -- hilos sin pthreads: clone(2) + futex(2)
;  parallel(fn) ejecuta fn(tid) en nthreads hilos (tid 0 en el hilo actual)
;  y espera a todos usando CLONE_CHILD_CLEARTID como "join".
; =============================================================================
section .text

%define CLONE_FLAGS     0x350F00    ; VM|FS|FILES|SIGHAND|THREAD|SYSVSEM|PARENT_SETTID|CHILD_CLEARTID
%define STACK_SZ        65536

; init_threads: cantidad de CPUs disponibles (sched_getaffinity) o --threads
init_threads:
        mov     eax, 204
        xor     edi, edi
        mov     esi, 128
        lea     rdx, [cpubuf]
        syscall
        test    rax, rax
        jle     .one
        mov     ecx, eax
        xor     edx, edx
        xor     esi, esi
.lp:    cmp     esi, ecx
        jae     .done
        movzx   eax, byte [cpubuf + rsi]
        popcnt  eax, eax
        add     edx, eax
        inc     esi
        jmp     .lp
.done:  mov     eax, edx
        jmp     .set
.one:   mov     eax, 1
.set:   cmp     dword [opt_threads], 0
        je      .c1
        mov     eax, [opt_threads]
.c1:    cmp     eax, 1
        jge     .c2
        mov     eax, 1
.c2:    cmp     eax, MAXT
        jle     .c3
        mov     eax, MAXT
.c3:    mov     [nthreads], eax
        ret

; parallel(rdi = funcion(edi = tid))
parallel:
        push    rbx
        push    r12
        mov     [par_fn], rdi
        mov     ebx, 1
.spawn: cmp     ebx, [nthreads]
        jae     .self
        mov     eax, ebx
        shl     rax, 16
        lea     rsi, [thread_stacks + rax + STACK_SZ - 16]
        mov     [rsi], rbx
        mov     eax, 56                     ; clone
        mov     edi, CLONE_FLAGS
        lea     rdx, [tid_words + rbx*4]
        mov     r10, rdx
        xor     r8d, r8d
        syscall
        test    rax, rax
        jz      .child
        jns     .next
        mov     edi, ebx                    ; clone fallo: correrlo aca
        call    [par_fn]
.next:  inc     ebx
        jmp     .spawn
.self:  xor     edi, edi
        call    [par_fn]
        mov     ebx, 1
.join:  cmp     ebx, [nthreads]
        jae     .done
.w:     mov     edx, [tid_words + rbx*4]
        test    edx, edx
        jz      .nx
        mov     eax, 202                    ; futex(FUTEX_WAIT)
        lea     rdi, [tid_words + rbx*4]
        xor     esi, esi
        xor     r10d, r10d
        syscall
        jmp     .w
.nx:    inc     ebx
        jmp     .join
.done:  pop     r12
        pop     rbx
        ret
.child: mov     rdi, [rsp]
        call    [par_fn]
        mov     eax, SYS_EXIT               ; termina solo este hilo
        xor     edi, edi
        syscall

; chunk(edi = tid, rsi = total) -> rax inicio, rdx fin
chunk:
        mov     r8d, [nthreads]
        mov     ecx, edi
        mov     rax, rsi
        imul    rax, rcx
        xor     edx, edx
        div     r8
        mov     r9, rax
        lea     ecx, [rdi+1]
        mov     rax, rsi
        imul    rax, rcx
        xor     edx, edx
        div     r8
        mov     rdx, rax
        mov     rax, r9
        ret
