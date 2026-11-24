; =============================================================================
;  defs.inc -- constantes, layout, acciones y macros
; =============================================================================

; ------------------------------------------------------------------ ventana
%define DEF_W           1280
%define DEF_H           760
%define MIN_W           1200
%define MIN_H           700
%define MAX_DIM         4096

; ---------------------------------------------------------------- pipeline
%define NMAX            1000000
%define MAXGRP          12
%define STAGE           550                 ; ms por etapa de animacion
%define ANIM_LINKS_END  (4*STAGE)
%define ANIM_END        (ANIM_LINKS_END + 600)
%define THR_STEP        50
%define THR_MAX         2400

; ---------------------------------------------------------------- syscalls
%define SYS_READ        0
%define SYS_WRITE       1
%define SYS_OPEN        2
%define SYS_CLOSE       3
%define SYS_POLL        7
%define SYS_MMAP        9
%define SYS_SHMGET      29
%define SYS_SHMAT       30
%define SYS_SHMCTL      31
%define SYS_SOCKET      41
%define SYS_CONNECT     42
%define SYS_EXIT        60
%define SYS_SHMDT       67
%define SYS_CLOCK_GETTIME 228

; ------------------------------------------------------------------ paleta
; Los colores son 0xAARRGGBB; AA = 0 significa opaco.
%define C_BG            0x0f1117
%define C_PANEL         0x171a23
%define C_BORDER        0x262b38
%define C_TEXT          0xe6e9ef
%define C_MUTED         0x8a93a6
%define C_DIM           0x4b5263
%define C_YELLOW        0xf5c542
%define C_GREEN         0x3ccf7a
%define C_RED           0xef5d6a
%define C_ACCENT        0x8ab4ff
%define C_LINK          0x3a4152
%define C_BOX           0x1d212c
%define C_KW            0xc792ea
%define C_FN            0x82aaff
%define C_NUM           0xf78c6c
%define C_CMT           0x6b8f71
%define C_WHITE         0xffffff

; ------------------------------------------------------------------ layout
%define HDR_H           56
%define TB_Y            66
%define TB_H            36
%define CAN_X           16
%define CAN_Y           112
%define CAN_H           262
%define BOT_Y           (CAN_Y + CAN_H + 12)
%define FOOT_H          28
%define INS_X           16
%define INS_W           330
%define SQL_X           (INS_X + INS_W + 12)
%define SQL_W           360
%define OUT_X           (SQL_X + SQL_W + 12)
%define BOXW            150
%define BOXH            92
%define ROWH            20
%define LINEH           20

; -------------------------------------------------- acciones (hit testing)
%define A_NONE          0
%define A_RUN           1
%define A_NEW           2
%define A_EXPORT        3
%define A_NREC          4
%define A_OP            5
%define A_THR_DEC       6
%define A_THR_INC       7
%define A_THR_FIELD     8
%define A_GROUP         9
%define A_SORTCOL       10
%define A_SORTDIR       11
%define A_COMP          12
%define A_LINK          13
%define A_TAB           14
%define A_CTX           15
%define A_CANVAS        16
%define A_VIEWER        17
%define A_SCROLL        18
%define A_RESET         19
%define A_COUNT         20
%define MAXHITS         160

; ------------------------------------------------------------- estilos UI
%define ST_NORMAL       0
%define ST_GREEN        1
%define ST_SELECTED     2
%define ST_BLUE         3
%define ST_PURPLE       4
%define ST_GHOST        5
%define ST_FIELD        6
%define ST_FOCUS        7

; ------------------------------------------------------------------ macros
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

%macro HIT 6
        mov     edi, %1
        mov     esi, %2
        mov     edx, %3
        mov     ecx, %4
        mov     r8d, %5
        mov     r9d, %6
        call    add_hit
%endmacro

; BUTTON x, y, w, h, label, action, param, style
%macro BUTTON 8
        mov     dword [bt_param], %7
        mov     dword [bt_style], %8
        mov     edi, %1
        mov     esi, %2
        mov     edx, %3
        mov     ecx, %4
        lea     r8, [%5]
        mov     r9d, %6
        call    ui_button
%endmacro

%macro DIE 1
        lea     rsi, [%1]
        call    die
%endmacro

; SB_STR str  /  SB_NUM reg_o_valor  (string builder global)
%macro SB_STR 1
        lea     rsi, [%1]
        call    sb_str
%endmacro
%macro SB_NUM 1
        mov     rdi, %1
        call    sb_num
%endmacro
