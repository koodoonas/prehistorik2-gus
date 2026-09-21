; PRE2GUS - native GF1 audio launcher for the Old-Games.ru Prehistorik 2 build
;
; Target executable:
;   PRE2.EXE, 52190 bytes
;   SHA-256 e1a7f875b2806551e3f1a8e393b5dfedd5825c402528a24ed90f21e08a2a1142
;
; The launcher leaves PRE2.EXE unchanged.  It identifies the materialized game
; code in memory, replaces three exact entry sequences, and restores every
; interrupt vector when the child exits.  Music and SFX are played directly by
; the GF1; the GUS MAX CS4231 codec is never addressed.  The analog line input
; remains open for the protected intro and is muted at the game handoff.
;
; Build with NASM 2.x: nasm -f bin -o PRE2GUS.COM pre2gus.asm

bits 16
org 100h

%define MOD_HEADER_BYTES    1084
%define MOD_PATTERN_LIMIT   22528
%define MUSIC_DRAM_LOW      0000h
%define MUSIC_DRAM_HIGH     0001h       ; 0x10000
%define SFX_BANK_BYTES      60768
%define IO_BUFFER_BYTES     512
%define SELFTEST_TICKS      250
%define SELFTEST_BIOS_TICKS 128

%define PATCH_SFX_OFF       0276h
%define PATCH_SONG_OFF      02C0h
%define PATCH_INIT_OFF      07F6h
%define PATCH_SIG_OFF       0008h

    jmp start

; ---------------------------------------------------------------------------
; Startup and DOS launcher

start:
    cli
    mov ax, cs
    mov ss, ax
    mov sp, stack_top
    sti
    mov ds, ax
    mov es, ax
    cld
    mov [psp_segment], ax

    mov dx, msg_banner
    call print_dos
    call parse_command_line
    jc fatal_args
    call show_music_pan
    call parse_ultrasnd
    jc fatal_config
    call setup_gus_ports

    ; Put our stack inside the retained block, then return unused DOS memory.
    mov bx, RESIDENT_PARAS
    mov ah, 4Ah
    int 21h
    jc fatal_memory

    mov ax, [psp_segment]
    add ax, RESIDENT_PARAS
    mov [patch_scan_start], ax
    add ax, 1000h                ; child PSP/code must be in the next 64 KiB
    cmp ax, 0A000h
    jbe .scan_limit_ready
    mov ax, 0A000h
.scan_limit_ready:
    mov [patch_scan_limit], ax

    call gus_reset
    call gus_probe
    jc fatal_gus
    call gus_set_interface
    call load_sfx_bank
    jc fatal_sfx
    call install_vectors

    cmp byte [test_mode], 0
    jne run_selftest

    call exec_game
    mov [exec_error], ax
    mov byte [exec_failed], 0
    jnc .child_returned
    mov byte [exec_failed], 1
    jmp .after_child
.child_returned:
    mov ah, 4Dh
    int 21h
    mov [child_exit_code], al
.after_child:
    call cleanup
%ifdef DUMP_CODE
    call write_code_dump
%endif

    cmp byte [exec_failed], 0
    je .report_patch
    mov dx, msg_exec_failed
    call print_dos
    mov ax, [exec_error]
    call print_hex_word
    mov dx, msg_crlf
    call print_dos
    mov al, 1
    jmp exit_dos

.report_patch:
    cmp byte [patch_installed], 1
    jne .not_patched
    mov dx, msg_patch_ok
    call print_dos
    jmp .report_song
.not_patched:
    mov dx, msg_patch_missing
    call print_dos
.report_song:
%ifdef DUMP_CODE
    mov dx, msg_patch_trigger
    call print_dos
    mov ax, [patch_trigger_ax]
    call print_hex_word
    mov dx, msg_patch_trigger_ip
    call print_dos
    mov ax, [patch_trigger_ip]
    call print_hex_word
    mov dx, msg_crlf
    call print_dos
%endif
    cmp byte [song_error], 0
    je .report_counts
    mov dx, msg_song_error
    call print_dos
.report_counts:
    mov dx, msg_audio_counts
    call print_dos
    mov ax, [songs_loaded]
    call print_hex_word
    mov dx, msg_audio_sfx
    call print_dos
    mov ax, [sfx_played]
    call print_hex_word
    mov dx, msg_crlf
    call print_dos
    mov al, [child_exit_code]
    jmp exit_dos

run_selftest:
    mov dx, msg_test_start
    call print_dos
    pushf
    cli
    mov word [total_ticks], 0
    popf
    mov ax, 3                    ; PRESENTA.MOD
    int 65h
    mov dl, 0
    int 66h

    xor ax, ax
    mov es, ax
    mov ax, [es:046Ch]
    mov [bios_tick_start], ax
.wait:
    cmp word [total_ticks], SELFTEST_TICKS
    jae .test_ok
    mov ah, 01h
    int 16h
    jnz .test_key
    mov ax, [es:046Ch]
    sub ax, [bios_tick_start]
    cmp ax, SELFTEST_BIOS_TICKS
    jae .test_timeout
    sti
    hlt
    jmp .wait
.test_key:
    mov ah, 00h
    int 16h
    cmp word [total_ticks], 0
    je .test_timeout
.test_ok:
    push cs
    pop ds
    call cleanup
    mov dx, msg_test_ok
    call print_dos
    xor al, al
    jmp exit_dos
.test_timeout:
    push cs
    pop ds
    call cleanup
    mov dx, msg_test_fail
    call print_dos
    mov al, 2
    jmp exit_dos

fatal_config:
    mov dx, msg_bad_config
    jmp fatal_plain
fatal_args:
    mov dx, msg_bad_args
    jmp fatal_plain
fatal_memory:
    mov dx, msg_no_memory
    jmp fatal_plain
fatal_gus:
    call gus_quiet
    mov dx, msg_no_gus
    call print_dos
    mov dx, msg_probe_detail
    call print_dos
    mov ax, [gus_base]
    call print_hex_word
    mov dx, msg_probe_values
    call print_dos
    xor ax, ax
    mov al, [probe_value0]
    call print_hex_word
    mov dl, '/'
    mov ah, 02h
    int 21h
    xor ax, ax
    mov al, [probe_value1]
    call print_hex_word
    mov dx, msg_crlf
    call print_dos
    mov al, 1
    jmp exit_dos
fatal_sfx:
    mov dx, msg_no_sfx
fatal_quiet:
    push dx
    call gus_quiet
    pop dx
fatal_plain:
    call print_dos
    mov al, 1

exit_dos:
    mov ah, 4Ch
    int 21h

print_dos:
    mov ah, 09h
    int 21h
    ret

print_hex_word:
    push ax
    push bx
    push cx
    push dx
    mov bx, ax
    mov cx, 4
.digit:
    rol bx, 4
    mov dl, bl
    and dl, 0Fh
    add dl, '0'
    cmp dl, '9'
    jbe .emit
    add dl, 7
.emit:
    mov ah, 02h
    int 21h
    loop .digit
    pop dx
    pop cx
    pop bx
    pop ax
    ret

%ifdef DUMP_CODE
write_code_dump:
    cmp byte [code_dumped], 1
    jne .done
    mov dx, code_dump_filename
    xor cx, cx
    mov ah, 3Ch
    int 21h
    jc .done
    mov bx, ax
    mov dx, code_dump
    mov cx, 1000h
    mov ah, 40h
    int 21h
    mov ah, 3Eh
    int 21h
.done:
    ret
%endif

; The PSP tail belongs to the launcher, not to PRE2.EXE.  Parse switches in
; either order, and reject typos before touching the GF1.  OCP's -vp spelling
; is accepted as an alias; negative percentages reverse L/R music channels.
parse_command_line:
    mov byte [test_mode], 0
    mov byte [pan_percent], 60    ; v1.1's fixed GF1 positions were 3/12
    mov byte [pan_reverse], 0
    mov byte [pan_seen], 0
    xor cx, cx
    mov cl, [80h]
    mov si, 81h
.next:
    or cx, cx
    jz .success
    mov al, [si]
    dec cx
    inc si
    cmp al, ' '
    je .next
    cmp al, 9
    je .next
    cmp al, '/'
    je .switch
    cmp al, '-'
    jne .fail
.switch:
    or cx, cx
    jz .fail
    mov al, [si]
    inc si
    dec cx
    and al, 0DFh
    xor bh, bh
    cmp al, 'V'
    jne .kind
    mov bh, 1
    or cx, cx
    jz .fail
    mov al, [si]
    inc si
    dec cx
    and al, 0DFh
.kind:
    cmp al, 'T'
    je .test
    cmp al, 'P'
    je .pan
    jmp .fail
.test:
    or bh, bh
    jnz .fail
    cmp byte [test_mode], 0
    jne .fail
    mov byte [test_mode], 1
    jmp .token_end
.pan:
    cmp byte [pan_seen], 0
    jne .fail
    mov byte [pan_seen], 1
    jcxz .fail
    mov al, [si]
    cmp al, '='
    je .separator
    cmp al, ':'
    jne .sign
.separator:
    inc si
    dec cx
    jcxz .fail
.sign:
    mov al, [si]
    cmp al, '-'
    jne .plus
    mov byte [pan_reverse], 1
    jmp .skip_sign
.plus:
    cmp al, '+'
    jne .first_digit
.skip_sign:
    inc si
    dec cx
    jcxz .fail
.first_digit:
    mov di, si
    xor bx, bx
.digits:
    jcxz .number_done
    mov al, [si]
    cmp al, '0'
    jb .number_done
    cmp al, '9'
    ja .number_done
    sub al, '0'
    mov dl, al
    mov ax, bx
    shl bx, 1
    shl ax, 3
    add bx, ax
    xor dh, dh
    add bx, dx
    cmp bx, 100
    ja .fail
    inc si
    dec cx
    jmp .digits
.number_done:
    cmp si, di
    je .fail
    mov [pan_percent], bl
.token_end:
    jcxz .success
    mov al, [si]
    cmp al, ' '
    je .next
    cmp al, 9
    je .next
    jmp .fail
.success:
    call set_music_pan
    clc
    ret
.fail:
    stc
    ret

; Map a signed 0..100 percent width to GF1's discrete 0..15 pan register.
; Zero uses 7/7 (both channels centered).  +60 gives 3/12, exactly v1.1.
set_music_pan:
    mov al, [pan_percent]
    or al, al
    jnz .scale
    mov bl, 7
    mov bh, 7
    jmp .store
.scale:
    mov bl, 100
    sub bl, al
    mov al, bl
    mov bl, 15
    mul bl                      ; (100 - width) * 15
    add ax, 100                 ; rounded to nearest GF1 pan step
    xor dx, dx
    mov bx, 200
    div bx
    mov bl, al
    mov bh, 15
    sub bh, bl
    cmp byte [pan_reverse], 0
    je .store
    xchg bl, bh
.store:
    mov [music_pan], bl
    mov [music_pan+1], bh
    mov [music_pan+2], bh
    mov [music_pan+3], bl
    ret

show_music_pan:
    mov dx, msg_pan
    call print_dos
    mov dl, '+'
    cmp byte [pan_reverse], 0
    je .sign_ready
    mov dl, '-'
.sign_ready:
    mov ah, 02h
    int 21h
    mov al, [pan_percent]
    call print_decimal_byte
    mov dx, msg_pan_end
    call print_dos
    ret

print_decimal_byte:
    xor ah, ah
    mov bl, 10
    div bl
    mov bl, ah                   ; ones digit
    xor ah, ah
    mov dl, 10
    div dl
    mov bh, ah                   ; tens digit
    or al, al
    jz .tens
    add al, '0'
    mov dl, al
    mov ah, 02h
    int 21h
.tens:
    cmp bh, 0
    jne .print_tens
    cmp byte [pan_percent], 100
    jne .ones
.print_tens:
    mov dl, bh
    add dl, '0'
    mov ah, 02h
    int 21h
.ones:
    mov dl, bl
    add dl, '0'
    mov ah, 02h
    int 21h
    ret

exec_game:
    push cs
    pop ds
    push cs
    pop es
    mov word [exec_params], 0
    mov ax, [psp_segment]
    mov word [exec_params+2], exec_tail
    mov word [exec_params+4], ax
    mov word [exec_params+6], 5Ch
    mov word [exec_params+8], ax
    mov word [exec_params+10], 6Ch
    mov word [exec_params+12], ax
    mov dx, game_filename
    mov bx, exec_params
    mov ax, 4B00h
    int 21h
    ret

; ---------------------------------------------------------------------------
; ULTRASND parsing

parse_ultrasnd:
    push es
    mov ax, [2Ch]
    or ax, ax
    jz .fail
    mov es, ax
    xor di, di
.next_string:
    cmp byte [es:di], 0
    jne .compare
    cmp byte [es:di+1], 0
    je .fail
    inc di
    jmp .next_string
.compare:
    push di
    mov si, ultrasnd_key
    mov cx, 9
.compare_char:
    mov al, [es:di]
    cmp al, 'a'
    jb .already_upper
    cmp al, 'z'
    ja .already_upper
    sub al, 20h
.already_upper:
    cmp al, [si]
    jne .not_this
    inc di
    inc si
    loop .compare_char
    pop bx                       ; discard original string offset

    call parse_hex_component
    jc .fail
    mov [gus_base], ax
    call require_comma
    jc .fail
    call parse_dec_component
    jc .fail
    mov [gus_dma1], ax
    call require_comma
    jc .fail
    call parse_dec_component
    jc .fail
    mov [gus_dma2], ax
    call require_comma
    jc .fail
    call parse_dec_component
    jc .fail
    mov [gus_irq], ax
    call require_comma
    jc .fail
    call parse_dec_component
    jc .fail
    mov [gus_midi_irq], ax
    cmp byte [es:di], 0
    jne .fail

    mov ax, [gus_base]
    cmp ax, 210h
    jb .fail
    cmp ax, 260h
    ja .fail
    test al, 0Fh
    jnz .fail

    mov bx, [gus_dma1]
    cmp bx, 7
    ja .fail
    cmp byte [dma_lut+bx], 0
    je .fail
    mov bx, [gus_dma2]
    cmp bx, 7
    ja .fail
    cmp byte [dma_lut+bx], 0
    je .fail
    mov bx, [gus_irq]
    cmp bx, 15
    ja .fail
    cmp byte [irq_lut+bx], 0
    je .fail
    mov bx, [gus_midi_irq]
    cmp bx, 15
    ja .fail
    cmp byte [irq_lut+bx], 0
    je .fail
    pop es
    clc
    ret

.not_this:
    pop di
.skip_string:
    cmp byte [es:di], 0
    je .past_string
    inc di
    jmp .skip_string
.past_string:
    inc di
    jmp .next_string
.fail:
    pop es
    stc
    ret

require_comma:
    cmp byte [es:di], ','
    jne .bad
    inc di
    clc
    ret
.bad:
    stc
    ret

parse_hex_component:
    xor bx, bx
    xor cx, cx
.loop:
    mov al, [es:di]
    cmp al, ','
    je .end
    or al, al
    jz .end
    cmp al, '0'
    jb .bad
    cmp al, '9'
    jbe .number
    and al, 0DFh
    cmp al, 'A'
    jb .bad
    cmp al, 'F'
    ja .bad
    sub al, 'A'-10
    jmp .add
.number:
    sub al, '0'
.add:
    shl bx, 4
    xor ah, ah
    add bx, ax
    inc di
    inc cx
    jmp .loop
.end:
    jcxz .bad
    mov ax, bx
    clc
    ret
.bad:
    stc
    ret

parse_dec_component:
    xor bx, bx
    xor cx, cx
.loop:
    mov al, [es:di]
    cmp al, ','
    je .end
    or al, al
    jz .end
    cmp al, '0'
    jb .bad
    cmp al, '9'
    ja .bad
    sub al, '0'
    xor ah, ah
    push ax
    mov ax, bx
    mov dx, 10
    mul dx
    mov bx, ax
    pop ax
    add bx, ax
    inc di
    inc cx
    jmp .loop
.end:
    jcxz .bad
    mov ax, bx
    clc
    ret
.bad:
    stc
    ret

; ---------------------------------------------------------------------------
; GF1 low-level setup

setup_gus_ports:
    mov ax, [gus_base]
    mov dx, ax
    add dx, 102h
    mov [gus_voice_port], dx
    inc dx
    mov [gus_command_port], dx
    inc dx
    mov [gus_data_low_port], dx
    inc dx
    mov [gus_data_high_port], dx
    mov dx, ax
    add dx, 006h
    mov [gus_status_port], dx
    add dx, 2
    mov [gus_timer_control_port], dx
    inc dx
    mov [gus_timer_data_port], dx
    mov dx, ax
    add dx, 107h
    mov [gus_dram_port], dx
    ret

gus_set_interface:
    pushf
    cli
    xor cx, cx
    mov bx, [gus_irq]
    mov cl, [irq_lut+bx]
    mov bx, [gus_midi_irq]
    mov al, [irq_lut+bx]
    shl al, 3
    or cl, al
    mov ax, [gus_irq]
    cmp ax, [gus_midi_irq]
    jne .irq_ready
    or cl, 40h
.irq_ready:
    mov [irq_latch], cl

    xor cx, cx
    mov bx, [gus_dma1]
    mov cl, [dma_lut+bx]
    mov bx, [gus_dma2]
    mov al, [dma_lut+bx]
    shl al, 3
    or cl, al
    mov ax, [gus_dma1]
    cmp ax, [gus_dma2]
    jne .dma_ready
    or cl, 40h
.dma_ready:
    mov [dma_latch], cl

    ; Unlock and reset the original GF1 digital ASIC interface.
    mov dx, [gus_base]
    add dx, 0Fh
    mov al, 05h
    out dx, al
    mov dx, [gus_base]
    mov al, 0Bh                  ; line/mic/output off, GF1 IRQ enabled
    out dx, al
    add dx, 0Bh
    xor al, al
    out dx, al
    mov dx, [gus_base]
    add dx, 0Fh
    xor al, al
    out dx, al

    ; Program the DRAM/ADC DMA and GF1/MIDI IRQ latches twice, as
    ; prescribed by the GF1 hardware interface sequence.
    mov dx, [gus_base]
    mov al, 0Bh
    out dx, al
    add dx, 0Bh
    mov al, [dma_latch]
    or al, 80h
    out dx, al
    mov dx, [gus_base]
    mov al, 4Bh
    out dx, al
    add dx, 0Bh
    mov al, [irq_latch]
    out dx, al
    mov dx, [gus_base]
    mov al, 0Bh
    out dx, al
    add dx, 0Bh
    mov al, [dma_latch]
    out dx, al
    mov dx, [gus_base]
    mov al, 4Bh
    out dx, al
    add dx, 0Bh
    mov al, [irq_latch]
    out dx, al
    mov dx, [gus_voice_port]
    xor al, al
    out dx, al
    mov dx, [gus_base]
    mov al, 08h                  ; line input, output and GF1 IRQ on; mic off
    out dx, al
    mov dx, [gus_voice_port]
    xor al, al
    out dx, al
    popf
    ret

gus_reset:
    pushf
    cli
    mov dx, [gus_command_port]
    mov al, 4Ch
    out dx, al
    mov dx, [gus_data_high_port]
    xor al, al
    out dx, al
    call gf1_delay
    call gf1_delay
    mov dx, [gus_command_port]
    mov al, 4Ch
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 01h
    out dx, al
    call gf1_delay
    call gf1_delay

    mov dx, [gus_base]
    add dx, 100h
    mov al, 03h
    out dx, al
    call gf1_delay
    xor al, al
    out dx, al

    mov dx, [gus_command_port]
    mov al, 41h
    out dx, al
    mov dx, [gus_data_high_port]
    xor al, al
    out dx, al
    mov dx, [gus_command_port]
    mov al, 45h
    out dx, al
    mov dx, [gus_data_high_port]
    xor al, al
    out dx, al
    mov dx, [gus_command_port]
    mov al, 49h
    out dx, al
    mov dx, [gus_data_high_port]
    xor al, al
    out dx, al

    mov dx, [gus_command_port]
    mov al, 0Eh
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 0CDh                  ; 14 active voices: (14-1) | C0
    out dx, al

    call gus_clear_pending
    xor si, si
.voice_loop:
    mov dx, [gus_voice_port]
    mov ax, si
    out dx, al
    mov dx, [gus_command_port]
    xor al, al
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 03h
    out dx, al
    mov dx, [gus_command_port]
    mov al, 0Dh
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 03h
    out dx, al
    call gf1_delay

    mov dx, [gus_command_port]
    mov al, 01h
    out dx, al
    mov dx, [gus_data_low_port]
    mov ax, 0400h
    out dx, ax
    mov dx, [gus_command_port]
    mov al, 09h
    out dx, al
    mov dx, [gus_data_low_port]
    xor ax, ax
    out dx, ax
    mov dx, [gus_command_port]
    mov al, 0Ch
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 07h
    out dx, al
    inc si
    cmp si, 14
    jb .voice_loop

    call gus_clear_pending
    mov dx, [gus_command_port]
    mov al, 4Ch
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 07h                  ; reset released, DAC and master IRQ enabled
    out dx, al
    popf
    ret

gus_clear_pending:
    push ax
    push dx
    mov dx, [gus_status_port]
    in al, dx
    mov dx, [gus_command_port]
    mov al, 41h
    out dx, al
    mov dx, [gus_data_high_port]
    in al, dx
    mov dx, [gus_command_port]
    mov al, 49h
    out dx, al
    mov dx, [gus_data_high_port]
    in al, dx
    mov dx, [gus_command_port]
    mov al, 8Fh
    out dx, al
    mov dx, [gus_data_high_port]
    in al, dx
    pop dx
    pop ax
    ret

gf1_delay:
    push ax
    push cx
    push dx
    mov dx, [gus_dram_port]
    mov cx, 7
.wait:
    in al, dx
    loop .wait
    pop dx
    pop cx
    pop ax
    ret

gus_probe:
    mov word [dram_addr_low], 0
    mov word [dram_addr_high], 0
    mov bl, 0AAh
    call gus_poke
    mov word [dram_addr_low], 1
    mov bl, 055h
    call gus_poke
    mov word [dram_addr_low], 0
    call gus_peek
    mov [probe_value0], al
    cmp al, 0AAh
    jne .fail
    mov word [dram_addr_low], 1
    call gus_peek
    mov [probe_value1], al
    cmp al, 055h
    jne .fail
    clc
    ret
.fail:
    stc
    ret

gus_poke:
    push ax
    push dx
    pushf
    cli
    mov dx, [gus_command_port]
    mov al, 43h
    out dx, al
    mov dx, [gus_data_low_port]
    mov ax, [dram_addr_low]
    out dx, ax
    mov dx, [gus_command_port]
    mov al, 44h
    out dx, al
    mov dx, [gus_data_high_port]
    mov ax, [dram_addr_high]
    out dx, al
    mov dx, [gus_dram_port]
    mov al, bl
    out dx, al
    popf
    pop dx
    pop ax
    ret

gus_peek:
    push dx
    pushf
    cli
    mov dx, [gus_command_port]
    mov al, 43h
    out dx, al
    mov dx, [gus_data_low_port]
    mov ax, [dram_addr_low]
    out dx, ax
    mov dx, [gus_command_port]
    mov al, 44h
    out dx, al
    mov dx, [gus_data_high_port]
    mov ax, [dram_addr_high]
    out dx, al
    mov dx, [gus_dram_port]
    in al, dx
    mov [peek_value], al
    popf
    pop dx
    mov al, [peek_value]
    ret

; DS:SI = bytes, CX = count.  dram_addr_* is advanced by count.
gus_upload:
    push ax
    push bx
    push cx
    push dx
    push si
    pushf
    cli
    mov dx, [gus_command_port]
    mov al, 44h
    out dx, al
    mov dx, [gus_data_high_port]
    mov ax, [dram_addr_high]
    out dx, al
.byte:
    mov dx, [gus_command_port]
    mov al, 43h
    out dx, al
    mov dx, [gus_data_low_port]
    mov ax, [dram_addr_low]
    out dx, ax
    mov dx, [gus_dram_port]
    lodsb
    out dx, al
    inc word [dram_addr_low]
    jnz .next
    inc word [dram_addr_high]
    mov dx, [gus_command_port]
    mov al, 44h
    out dx, al
    mov dx, [gus_data_high_port]
    mov ax, [dram_addr_high]
    out dx, al
.next:
    loop .byte
    popf
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
; Initial SFX bank upload

load_sfx_bank:
    mov dx, sfx_filename
    mov ax, 3D00h
    int 21h
    jc .fail
    mov [file_handle], ax
    mov bx, ax
    mov word [dram_addr_low], 0
    mov word [dram_addr_high], 0
    mov word [bytes_remaining], SFX_BANK_BYTES
.read:
    mov cx, [bytes_remaining]
    cmp cx, IO_BUFFER_BYTES
    jbe .size_ready
    mov cx, IO_BUFFER_BYTES
.size_ready:
    mov dx, io_buffer
    mov ah, 3Fh
    int 21h
    jc .close_fail
    or ax, ax
    jz .close_fail
    cmp ax, cx
    jne .close_fail
    push cx
    mov si, io_buffer
    call gus_upload
    pop cx
    sub [bytes_remaining], cx
    jnz .read
    mov bx, [file_handle]
    mov ah, 3Eh
    int 21h
    mov word [file_handle], 0FFFFh
    clc
    ret
.close_fail:
    mov bx, [file_handle]
    mov ah, 3Eh
    int 21h
    mov word [file_handle], 0FFFFh
.fail:
    stc
    ret

; ---------------------------------------------------------------------------
; Interrupt vector management and in-memory PRE2 patch

install_vectors:
    mov ax, 3521h
    int 21h
    mov [old_int21], bx
    mov [old_int21+2], es
    mov ax, 3565h
    int 21h
    mov [old_int65], bx
    mov [old_int65+2], es
    mov ax, 3566h
    int 21h
    mov [old_int66], bx
    mov [old_int66+2], es

    mov ax, [gus_irq]
    cmp ax, 7
    jbe .master_vector
    add ax, 68h
    jmp .vector_ready
.master_vector:
    add ax, 08h
.vector_ready:
    mov [irq_vector], al
    mov ah, 35h
    int 21h
    mov [old_irq], bx
    mov [old_irq+2], es

    in al, 21h
    mov [old_pic_master], al
    in al, 0A1h
    mov [old_pic_slave], al

    push ds
    push cs
    pop ds
    mov dx, int65_handler
    mov ax, 2565h
    int 21h
    mov dx, int66_handler
    mov ax, 2566h
    int 21h
    mov dx, gus_irq_handler
    mov ah, 25h
    mov al, [irq_vector]
    int 21h
    mov dx, int21_handler
    mov ax, 2521h
    int 21h
    pop ds

    pushf
    cli
    mov ax, [gus_irq]
    cmp ax, 7
    ja .unmask_slave
    mov cl, al
    mov bl, 1
    shl bl, cl
    not bl
    in al, 21h
    and al, bl
    out 21h, al
    jmp .unmask_done
.unmask_slave:
    sub al, 8
    mov cl, al
    mov bl, 1
    shl bl, cl
    not bl
    in al, 0A1h
    and al, bl
    out 0A1h, al
    in al, 21h
    and al, 0FBh
    out 21h, al
.unmask_done:
    popf
    mov byte [vectors_installed], 1
    ret

restore_vectors:
    cmp byte [vectors_installed], 1
    jne .done
    call gus_timer_stop

    pushf
    cli
    mov al, [old_pic_master]
    out 21h, al
    mov al, [old_pic_slave]
    out 0A1h, al
    popf

    mov dx, [old_irq]
    mov ax, [old_irq+2]
    mov ds, ax
    mov ah, 25h
    mov al, [cs:irq_vector]
    int 21h
    mov dx, [cs:old_int65]
    mov ax, [cs:old_int65+2]
    mov ds, ax
    mov ax, 2565h
    int 21h
    mov dx, [cs:old_int66]
    mov ax, [cs:old_int66+2]
    mov ds, ax
    mov ax, 2566h
    int 21h
    mov dx, [cs:old_int21]
    mov ax, [cs:old_int21+2]
    mov ds, ax
    mov ax, 2521h
    int 21h
    push cs
    pop ds
    mov byte [vectors_installed], 0
.done:
    ret

cleanup:
    mov byte [music_active], 0
    call gus_quiet
    call restore_vectors
    ; Return the SB16-to-GUS analog pass-through to its launcher-time state.
    mov dx, [gus_base]
    mov al, 08h
    out dx, al
    ret

; Called before the previous DOS INT 21 handler.  PRE2's loader reaches DOS
; through more than one code segment, so search the child's conventional-memory
; allocation until the exact materialized code image appears.  Once found, the
; known segment is checked and refreshed on later DOS calls.
int21_handler:
    push bp
    mov bp, sp
    pushf
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push ds
    push es
    push cs
    pop ds
    cld

    cmp byte [patch_installed], 1
    jne .scan_start
    mov ax, [patch_segment]
    jmp .candidate
.scan_start:
    mov ax, [patch_scan_start]
.scan_loop:
    cmp ax, [patch_scan_limit]
    jae .chain
.candidate:
    mov es, ax

    mov si, patch_signature
    mov di, PATCH_SIG_OFF
    mov cx, patch_signature_len
    repe cmpsb
    jne .candidate_fail
    cmp word [es:PATCH_SFX_OFF], 802Eh
    jne .sfx_maybe_patched
    cmp word [es:PATCH_SFX_OFF+2], 473Eh
    jne .candidate_fail
    cmp word [es:PATCH_SFX_OFF+4], 011Dh
    jne .candidate_fail
    jmp .sfx_ok
.sfx_maybe_patched:
    cmp word [es:PATCH_SFX_OFF], 66CDh
    jne .candidate_fail
    cmp byte [es:PATCH_SFX_OFF+2], 0C3h
    jne .candidate_fail
.sfx_ok:
    cmp word [es:PATCH_SONG_OFF], 5350h
    jne .song_maybe_patched
    cmp word [es:PATCH_SONG_OFF+2], 5251h
    jne .candidate_fail
    cmp word [es:PATCH_SONG_OFF+4], 5657h
    jne .candidate_fail
    cmp word [es:PATCH_SONG_OFF+6], 061Eh
    jne .candidate_fail
    cmp byte [es:PATCH_SONG_OFF+8], 55h
    jne .candidate_fail
    jmp .song_ok
.song_maybe_patched:
    cmp word [es:PATCH_SONG_OFF], 65CDh
    jne .candidate_fail
    cmp byte [es:PATCH_SONG_OFF+2], 0C3h
    jne .candidate_fail
.song_ok:
    cmp word [es:PATCH_INIT_OFF], 51E8h
    jne .init_maybe_patched
    cmp byte [es:PATCH_INIT_OFF+2], 15h
    jne .candidate_fail
    jmp .init_ok
.init_maybe_patched:
    cmp byte [es:PATCH_INIT_OFF], 0E9h
    jne .candidate_fail
    cmp word [es:PATCH_INIT_OFF+1], 0038h
    jne .candidate_fail
.init_ok:
%ifdef DUMP_CODE
    cmp byte [code_dumped], 1
    je .dump_done
    mov bx, [ss:bp-4]
    mov [patch_trigger_ax], bx
    mov bx, [ss:bp+2]
    mov [patch_trigger_ip], bx
    xor si, si
    mov di, code_dump
    mov cx, 1000h
.dump_loop:
    mov al, [es:si]
    mov [cs:di], al
    inc si
    inc di
    loop .dump_loop
    mov byte [code_dumped], 1
.dump_done:
%endif

    mov byte [es:PATCH_SFX_OFF], 0CDh
    mov byte [es:PATCH_SFX_OFF+1], 66h
    mov byte [es:PATCH_SFX_OFF+2], 0C3h
    mov byte [es:PATCH_SONG_OFF], 0CDh
    mov byte [es:PATCH_SONG_OFF+1], 65h
    mov byte [es:PATCH_SONG_OFF+2], 0C3h
    mov byte [es:PATCH_INIT_OFF], 0E9h
    mov word [es:PATCH_INIT_OFF+1], 0038h
    mov [patch_segment], ax
    ; The protected HybriD intro has handed off.  Mute the analog line input
    ; now so Prehistorik 2 proper is heard from the GF1 alone.
    cmp byte [game_line_muted], 1
    je .line_done
    mov dx, [gus_base]
    mov al, 09h
    out dx, al
    mov byte [game_line_muted], 1
.line_done:
    mov byte [patch_installed], 1
    jmp .chain
.candidate_fail:
    cmp byte [patch_installed], 1
    je .chain
    inc ax
    jmp .scan_loop
.chain:
    pop es
    pop ds
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    popf
    pop bp
    jmp far [cs:old_int21]

; ---------------------------------------------------------------------------
; Song/SFX software interrupt entry points

int65_handler:
    mov [cs:requested_song], al
    pusha
    push ds
    push es
    push cs
    pop ds
    push cs
    pop es
    sti
    call load_requested_song
%ifdef INTEGRATION_TEST
    ; Test-only build: let the first game-requested song run for five seconds,
    ; then terminate the child so the parent can report counters and clean up.
    cmp word [songs_loaded], 0
    je .integration_done
    mov bx, [total_ticks]
    add bx, SELFTEST_TICKS
.integration_wait:
    cmp word [total_ticks], bx
    jae .integration_exit
    sti
    hlt
    jmp .integration_wait
.integration_exit:
    mov ax, 4C00h
    int 21h
.integration_done:
%endif
    cli
    pop es
    pop ds
    popa
    iret

int66_handler:
    mov [cs:requested_sfx], dl
    pusha
    push ds
    push es
    push cs
    pop ds
    push cs
    pop es
    call play_requested_sfx
    pop es
    pop ds
    popa
    iret

; ---------------------------------------------------------------------------
; Module loading

load_requested_song:
    xor bx, bx
    mov bl, [requested_song]
    cmp bx, 17
    ja .done
    shl bx, 1
    mov dx, [song_filename_table+bx]
    or dx, dx
    jz .done
    mov al, [requested_song]
    cmp al, [current_song]
    je .done

    mov byte [music_active], 0
    call mute_music_voices
    mov word [file_handle], 0FFFFh
    mov ax, 3D00h
    int 21h
    jc .open_error
    mov [file_handle], ax
    mov bx, ax
    mov cx, MOD_HEADER_BYTES
    mov dx, module_buffer
    call dos_read_exact
    jc .load_error
    cmp word [module_buffer+1080], 2E4Dh
    jne .format_error
    cmp word [module_buffer+1082], 2E4Bh
    jne .format_error

    xor ax, ax
    mov al, [module_buffer+950]
    or al, al
    jz .format_error
    cmp al, 128
    ja .format_error
    mov [mod_song_length], al
    mov cl, al
    xor ch, ch
    mov si, module_buffer+952
    xor ax, ax
.max_pattern:
    cmp al, [si]
    jae .not_larger
    mov al, [si]
.not_larger:
    inc si
    loop .max_pattern
    inc ax
    cmp ax, 22
    ja .format_error
    mov [mod_num_patterns], al
    mov cl, 10
    shl ax, cl
    mov [mod_pattern_bytes], ax
    mov cx, ax
    mov dx, module_buffer+MOD_HEADER_BYTES
    mov bx, [file_handle]
    call dos_read_exact
    jc .load_error

    ; Decode the 31 standard MOD sample headers.
    mov si, module_buffer+20
    xor di, di
    mov cx, 31
.header_loop:
    mov ax, [si+22]
    xchg al, ah
    shl ax, 1
    mov [sample_length+di], ax
    mov al, [si+25]
    cmp al, 64
    jbe .volume_ok
    mov al, 64
.volume_ok:
    mov bx, di
    shr bx, 1
    mov [sample_volume+bx], al
    mov ax, [si+26]
    xchg al, ah
    shl ax, 1
    mov [sample_loop_start+di], ax
    mov ax, [si+28]
    xchg al, ah
    shl ax, 1
    mov [sample_loop_length+di], ax
    add si, 30
    add di, 2
    loop .header_loop

    mov word [dram_addr_low], MUSIC_DRAM_LOW
    mov word [dram_addr_high], MUSIC_DRAM_HIGH
    xor di, di
.sample_loop:
    mov ax, [dram_addr_low]
    mov [sample_start_low+di], ax
    mov ax, [dram_addr_high]
    mov [sample_start_high+di], ax
    mov ax, [sample_length+di]
    mov [bytes_remaining], ax
.sample_read:
    mov cx, [bytes_remaining]
    jcxz .sample_done
    cmp cx, IO_BUFFER_BYTES
    jbe .sample_size_ready
    mov cx, IO_BUFFER_BYTES
.sample_size_ready:
    mov bx, [file_handle]
    mov dx, io_buffer
    mov ah, 3Fh
    int 21h
    jc .load_error
    cmp ax, cx
    jne .load_error
    push cx
    mov si, io_buffer
    call gus_upload
    pop cx
    sub [bytes_remaining], cx
    jmp .sample_read
.sample_done:
    add di, 2
    cmp di, 62
    jb .sample_loop

    mov bx, [file_handle]
    mov ah, 3Eh
    int 21h
    mov word [file_handle], 0FFFFh
    mov al, [requested_song]
    mov [current_song], al
    inc word [songs_loaded]
    call tracker_reset
    mov byte [music_active], 1
    call gus_timer_start
    jmp .done

.format_error:
    mov byte [song_error], 2
    jmp .close_error
.load_error:
    mov byte [song_error], 3
.close_error:
    cmp word [file_handle], 0FFFFh
    je .mark_none
    mov bx, [file_handle]
    mov ah, 3Eh
    int 21h
    mov word [file_handle], 0FFFFh
.mark_none:
    mov byte [current_song], 0FFh
    jmp .done
.open_error:
    mov byte [song_error], 1
    mov byte [current_song], 0FFh
.done:
    ret

dos_read_exact:
    mov ah, 3Fh
    int 21h
    jc .fail
    cmp ax, cx
    jne .fail
    clc
    ret
.fail:
    stc
    ret

tracker_reset:
    mov byte [tracker_tick_count], 1
    mov byte [tracker_speed], 6
    mov byte [tracker_order], 0
    mov word [tracker_row], 0
    mov byte [channel_sample+0], 0FFh
    mov byte [channel_sample+1], 0FFh
    mov byte [channel_sample+2], 0FFh
    mov byte [channel_sample+3], 0FFh
    xor ax, ax
    mov di, channel_period
    mov cx, 4
    rep stosw
    mov di, channel_volume
    mov cx, 4
    rep stosb
    mov di, channel_slide
    mov cx, 4
    rep stosb
    call mute_music_voices
    ret

; ---------------------------------------------------------------------------
; GF1 timer IRQ and PRE2-faithful tracker subset (A/B/C/D/F effects)

gus_timer_start:
    cmp byte [timer_started], 1
    je .done
    pushf
    cli
    mov dx, [gus_command_port]
    mov al, 46h
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 6                    ; (256-6) * 80 us = 20 ms
    out dx, al
    mov dx, [gus_command_port]
    mov al, 45h
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 04h
    out dx, al
    mov byte [timer_control_shadow], 04h
    mov dx, [gus_timer_control_port]
    mov al, 04h
    out dx, al
    mov dx, [gus_timer_data_port]
    mov al, 01h
    out dx, al
    mov byte [timer_started], 1
    popf
.done:
    ret

gus_timer_stop:
    cmp byte [timer_started], 1
    jne .done
    pushf
    cli
    mov dx, [gus_command_port]
    mov al, 45h
    out dx, al
    mov dx, [gus_data_high_port]
    xor al, al
    out dx, al
    mov byte [timer_control_shadow], 0
    mov dx, [gus_timer_control_port]
    mov al, 04h
    out dx, al
    mov dx, [gus_timer_data_port]
    xor al, al
    out dx, al
    mov byte [timer_started], 0
    popf
.done:
    ret

gus_irq_handler:
    pushf
    push ax
    push dx
    mov dx, [cs:gus_status_port]
    in al, dx
    test al, 04h
    jnz .ours
    pop dx
    pop ax
    popf
    jmp far [cs:old_irq]
.ours:
    push bx
    push cx
    push si
    push di
    push bp
    push ds
    push es
    push cs
    pop ds

    mov dx, [gus_command_port]
    mov al, 45h
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, [timer_control_shadow]
    and al, 0FBh
    out dx, al
    or al, 04h
    out dx, al

    inc word [total_ticks]
    cmp byte [music_active], 1
    jne .clear_voice_irq
    call tracker_tick
.clear_voice_irq:
    mov dx, [gus_command_port]
    mov al, 8Fh
    out dx, al
    mov dx, [gus_data_high_port]
    in al, dx

    cmp word [gus_irq], 7
    jbe .master_eoi
    mov al, 20h
    out 0A0h, al
.master_eoi:
    mov al, 20h
    out 20h, al
    pop es
    pop ds
    pop bp
    pop di
    pop si
    pop cx
    pop bx
    pop dx
    pop ax
    popf
    iret

tracker_tick:
    ; Apply Axy volume slides on every tick before the row countdown.
    xor si, si
.slide_loop:
    mov al, [channel_slide+si]
    cbw
    or ax, ax
    jz .slide_next
    xor bx, bx
    mov bl, [channel_volume+si]
    add ax, bx
    jns .slide_nonnegative
    xor ax, ax
.slide_nonnegative:
    cmp ax, 64
    jbe .slide_clamped
    mov ax, 64
.slide_clamped:
    mov [channel_volume+si], al
    push si
    call music_volume_word
    mov bx, ax
    pop si
    mov ax, si
    call gf1_voice_volume
.slide_next:
    inc si
    cmp si, 4
    jb .slide_loop

    dec byte [tracker_tick_count]
    jnz .done
    mov al, [tracker_speed]
    mov [tracker_tick_count], al

    xor bx, bx
    mov bl, [tracker_order]
    cmp bl, [mod_song_length]
    jb .order_valid
    mov byte [tracker_order], 0
    xor bx, bx
.order_valid:
    mov al, [module_buffer+952+bx]
    cmp al, [mod_num_patterns]
    jae .advance
    xor ah, ah
    mov cl, 10
    shl ax, cl
    mov si, module_buffer+MOD_HEADER_BYTES
    add si, ax
    mov ax, [tracker_row]
    cmp ax, 63
    ja .advance
    shl ax, 4
    add si, ax
    xor di, di
.channel_loop:
    call tracker_process_cell
    add si, 4
    inc di
    cmp di, 4
    jb .channel_loop

.advance:
    inc word [tracker_row]
    cmp word [tracker_row], 64
    jne .done
    mov word [tracker_row], 0
    inc byte [tracker_order]
    mov al, [tracker_order]
    cmp al, [mod_song_length]
    jb .done
    mov byte [tracker_order], 0
.done:
    ret

; SI points to a standard four-byte MOD cell, DI is channel 0..3.
tracker_process_cell:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov byte [channel_slide+di], 0
    mov byte [temp_trigger], 0
    mov byte [temp_freq_changed], 0
    mov byte [temp_volume_changed], 0

    mov al, [si]
    and al, 0F0h
    mov ah, [si+2]
    shr ah, 4
    or al, ah
    mov [temp_sample], al

    mov ah, [si]
    and ah, 0Fh
    mov al, [si+1]
    mov [temp_period], ax
    mov al, [si+2]
    and al, 0Fh
    mov [temp_effect], al
    mov al, [si+3]
    mov [temp_param], al

    mov al, [temp_sample]
    or al, al
    jz .no_sample
    dec al
    cmp al, 30
    ja .no_sample
    mov [channel_sample+di], al
    xor bx, bx
    mov bl, al
    mov al, [sample_volume+bx]
    mov [channel_volume+di], al
    mov byte [temp_trigger], 1
    mov byte [temp_volume_changed], 1
.no_sample:
    mov ax, [temp_period]
    or ax, ax
    jz .no_period
    mov bx, di
    shl bx, 1
    mov [channel_period+bx], ax
    mov byte [temp_freq_changed], 1
.no_period:

    mov al, [temp_effect]
    cmp al, 0Ah
    je .effect_a
    cmp al, 0Bh
    je .effect_b
    cmp al, 0Ch
    je .effect_c
    cmp al, 0Dh
    je .effect_d
    cmp al, 0Fh
    je .effect_f
    jmp .apply_hardware
.effect_a:
    mov al, [temp_param]
    mov ah, al
    shr al, 4
    or al, al
    jnz .slide_store
    and ah, 0Fh
    mov al, ah
    neg al
.slide_store:
    mov [channel_slide+di], al
    jmp .apply_hardware
.effect_b:
    mov al, [temp_param]
    mov [tracker_order], al
    mov word [tracker_row], 0FFFFh
    jmp .apply_hardware
.effect_c:
    mov al, [temp_param]
    cmp al, 64
    jbe .c_ready
    mov al, 64
.c_ready:
    mov [channel_volume+di], al
    mov byte [temp_volume_changed], 1
    jmp .apply_hardware
.effect_d:
    xor ax, ax
    mov al, [temp_param]
    dec ax
    mov [tracker_row], ax
    inc byte [tracker_order]
    jmp .apply_hardware
.effect_f:
    mov al, [temp_param]
    mov [tracker_speed], al

.apply_hardware:
    cmp byte [temp_trigger], 1
    jne .not_trigger
    call trigger_music_channel
    jmp .done
.not_trigger:
    cmp byte [temp_freq_changed], 1
    jne .volume_only
    call update_music_frequency
.volume_only:
    cmp byte [temp_volume_changed], 1
    jne .done
    call update_music_volume
.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

trigger_music_channel:
    push ax
    push bx
    push cx
    push dx
    push si
    xor bx, bx
    mov bl, [channel_sample+di]
    cmp bl, 30
    ja .stop
    shl bx, 1
    mov ax, [sample_length+bx]
    or ax, ax
    jz .stop
    mov [voice_sample_length], ax
    mov ax, [sample_start_low+bx]
    mov [voice_begin_low], ax
    mov [voice_loop_low], ax
    mov ax, [sample_start_high+bx]
    mov [voice_begin_high], ax
    mov [voice_loop_high], ax

    mov ax, [sample_loop_length+bx]
    cmp ax, 2
    jbe .no_loop
    mov [voice_loop_length], ax
    mov ax, [sample_loop_start+bx]
    add [voice_loop_low], ax
    adc word [voice_loop_high], 0
    mov ax, [voice_loop_low]
    mov [voice_end_low], ax
    mov ax, [voice_loop_high]
    mov [voice_end_high], ax
    mov ax, [voice_loop_length]
    dec ax                          ; GF1 end addresses are inclusive
    add [voice_end_low], ax
    adc word [voice_end_high], 0
    mov byte [voice_mode], 08h
    jmp .address_ready
.no_loop:
    mov ax, [voice_begin_low]
    mov [voice_end_low], ax
    mov ax, [voice_begin_high]
    mov [voice_end_high], ax
    mov ax, [voice_sample_length]
    dec ax
    add [voice_end_low], ax
    adc word [voice_end_high], 0
    mov byte [voice_mode], 0
.address_ready:
    mov bx, di
    shl bx, 1
    mov ax, [channel_period+bx]
    or ax, ax
    jz .stop
    call period_to_frequency
    mov [voice_frequency], ax
    mov ax, di
    mov [voice_number], al
    mov bx, di
    mov al, [music_pan+bx]
    mov [voice_pan], al
    mov al, [channel_volume+di]
    call music_volume_word
    mov [voice_volume], ax
    call gf1_start_voice
    jmp .done
.stop:
    mov ax, di
    call gf1_stop_voice
.done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

update_music_frequency:
    push ax
    push bx
    mov bx, di
    shl bx, 1
    mov ax, [channel_period+bx]
    or ax, ax
    jz .done
    call period_to_frequency
    mov bx, ax
    mov ax, di
    call gf1_voice_frequency
.done:
    pop bx
    pop ax
    ret

update_music_volume:
    push ax
    push bx
    mov al, [channel_volume+di]
    call music_volume_word
    mov bx, ax
    mov ax, di
    call gf1_voice_volume
    pop bx
    pop ax
    ret

period_to_frequency:
    push bx
    push cx
    push dx
    mov bx, ax
    or bx, bx
    jz .zero
    mov ax, bx
    shr ax, 1
    add ax, 41179               ; round((3546895/period)*512/44100)
    xor dx, dx
    div bx
    shl ax, 1                  ; GF1 frequency bit 0 is unused
    jmp .done
.zero:
    xor ax, ax
.done:
    pop dx
    pop cx
    pop bx
    ret

music_volume_word:
    push bx
    push cx
    xor ah, ah
    mov bl, [music_master]
    mul bl
    mov cl, 6
    shr ax, cl
    cmp ax, 64
    jbe .index
    mov ax, 64
.index:
    shl ax, 1
    mov bx, ax
    mov ax, [volume_table+bx]
    pop cx
    pop bx
    ret

; ---------------------------------------------------------------------------
; GF1 voice operations

gf1_start_voice:
    pushf
    cli
    push ax
    push bx
    push cx
    push dx
    mov dx, [gus_voice_port]
    mov al, [voice_number]
    out dx, al

    mov dx, [gus_command_port]
    mov al, 0Dh
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 03h
    out dx, al
    call gf1_delay
    out dx, al
    mov dx, [gus_command_port]
    xor al, al
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 03h
    out dx, al
    call gf1_delay
    out dx, al

    mov dx, [gus_command_port]
    mov al, 09h
    out dx, al
    mov dx, [gus_data_low_port]
    xor ax, ax
    out dx, ax

    mov byte [voice_addr_register], 0Ah
    mov ax, [voice_begin_low]
    mov [voice_addr_low], ax
    mov ax, [voice_begin_high]
    mov [voice_addr_high], ax
    call gf1_write_voice_address
    mov byte [voice_addr_register], 02h
    mov ax, [voice_loop_low]
    mov [voice_addr_low], ax
    mov ax, [voice_loop_high]
    mov [voice_addr_high], ax
    call gf1_write_voice_address
    mov byte [voice_addr_register], 04h
    mov ax, [voice_end_low]
    mov [voice_addr_low], ax
    mov ax, [voice_end_high]
    mov [voice_addr_high], ax
    call gf1_write_voice_address

    mov dx, [gus_command_port]
    mov al, 01h
    out dx, al
    mov dx, [gus_data_low_port]
    mov ax, [voice_frequency]
    out dx, ax
    mov dx, [gus_command_port]
    mov al, 0Ch
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, [voice_pan]
    out dx, al
    mov dx, [gus_command_port]
    mov al, 09h
    out dx, al
    mov dx, [gus_data_low_port]
    mov ax, [voice_volume]
    out dx, ax

    mov dx, [gus_command_port]
    xor al, al
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, [voice_mode]
    and al, 0FCh
    out dx, al
    call gf1_delay
    out dx, al
    pop dx
    pop cx
    pop bx
    pop ax
    popf
    ret

gf1_write_voice_address:
    push ax
    push bx
    push cx
    push dx
    mov ax, [voice_addr_low]
    mov cx, [voice_addr_high]
    mov bx, cx
    shr ax, 7
    shr cx, 7
    shl bx, 9
    or ax, bx
    mov bx, ax
    mov dx, [gus_command_port]
    mov al, [voice_addr_register]
    out dx, al
    mov dx, [gus_data_low_port]
    mov ax, bx
    out dx, ax
    mov dx, [gus_command_port]
    mov al, [voice_addr_register]
    inc al
    out dx, al
    mov dx, [gus_data_low_port]
    mov ax, [voice_addr_low]
    shl ax, 9
    out dx, ax
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; AL = voice, BX = frequency word
gf1_voice_frequency:
    push ax
    push dx
    pushf
    cli
    mov dx, [gus_voice_port]
    out dx, al
    mov dx, [gus_command_port]
    mov al, 01h
    out dx, al
    mov dx, [gus_data_low_port]
    mov ax, bx
    out dx, ax
    popf
    pop dx
    pop ax
    ret

; AL = voice, BX = GF1 current-volume register word
gf1_voice_volume:
    push ax
    push dx
    pushf
    cli
    mov dx, [gus_voice_port]
    out dx, al
    mov dx, [gus_command_port]
    mov al, 09h
    out dx, al
    mov dx, [gus_data_low_port]
    mov ax, bx
    out dx, ax
    popf
    pop dx
    pop ax
    ret

; AL = voice
gf1_stop_voice:
    push ax
    push dx
    pushf
    cli
    mov dx, [gus_voice_port]
    out dx, al
    mov dx, [gus_command_port]
    mov al, 09h
    out dx, al
    mov dx, [gus_data_low_port]
    xor ax, ax
    out dx, ax
    mov dx, [gus_command_port]
    xor al, al
    out dx, al
    mov dx, [gus_data_high_port]
    mov al, 03h
    out dx, al
    call gf1_delay
    out dx, al
    popf
    pop dx
    pop ax
    ret

mute_music_voices:
    xor si, si
.loop:
    mov ax, si
    call gf1_stop_voice
    inc si
    cmp si, 4
    jb .loop
    ret

gus_quiet:
    pushf
    cli
    push ax
    push si
    cmp word [gus_base], 0
    je .done
    xor si, si
.voice:
    mov ax, si
    call gf1_stop_voice
    inc si
    cmp si, 14
    jb .voice
    mov dx, [gus_command_port]
    mov al, 45h
    out dx, al
    mov dx, [gus_data_high_port]
    xor al, al
    out dx, al
.done:
    pop si
    pop ax
    popf
    ret

; ---------------------------------------------------------------------------
; Polyphonic SFX

play_requested_sfx:
    xor bx, bx
    mov bl, [requested_sfx]
    cmp bx, 10
    ja .done
    shl bx, 1
    mov ax, [sfx_lengths+bx]
    or ax, ax
    jz .done
    mov [voice_sample_length], ax
    mov ax, [sfx_offsets+bx]
    mov [voice_begin_low], ax
    mov [voice_loop_low], ax
    mov [voice_end_low], ax
    xor ax, ax
    mov [voice_begin_high], ax
    mov [voice_loop_high], ax
    mov [voice_end_high], ax
    mov ax, [voice_sample_length]
    dec ax
    add [voice_end_low], ax
    mov word [voice_frequency], 186
    mov byte [voice_mode], 0
    xor bx, bx
    mov bl, [sfx_round_robin]
    mov al, bl
    inc byte [sfx_round_robin]
    and byte [sfx_round_robin], 7
    add al, 4
    mov [voice_number], al
    and bl, 1
    add bl, 7
    mov [voice_pan], bl
    mov ax, [volume_table+55*2]
    mov [voice_volume], ax
    call gf1_start_voice
    inc word [sfx_played]
.done:
    ret

; ---------------------------------------------------------------------------
; Data

msg_banner       db 13,10,'PRE2GUS 1.3 - native Gravis UltraSound GF1 audio',13,10,'$'
msg_bad_args     db 'Usage: PRE2GUS [/T] [/P-100..100]  (or -vp-100..100)',13,10,'$'
msg_pan          db 'GF1 music stereo width: $'
msg_pan_end      db '%',13,10,'$'
msg_bad_config   db 'ERROR: ULTRASND must contain a supported base,DMA,DMA,IRQ,IRQ setting.',13,10,'$'
msg_no_memory    db 'ERROR: DOS could not resize the launcher memory block.',13,10,'$'
msg_no_gus       db 'ERROR: no writable GF1 DRAM found at the ULTRASND base port.',13,10,'$'
msg_probe_detail  db 'Probe base/readback: $'
msg_probe_values  db ' / $'
msg_no_sfx       db 'ERROR: PRE2SFX.RAW is missing, truncated, or unreadable.',13,10,'$'
msg_exec_failed  db 'ERROR: DOS could not execute PRE2.EXE; DOS code 0x','$'
msg_patch_ok     db 'PRE2GUS: exact game image patched in memory; vectors restored.',13,10,'$'
msg_patch_missing db 'WARNING: exact PRE2 code signature was not seen; no game code was patched.',13,10,'$'
msg_song_error   db 'WARNING: at least one .MOD file could not be loaded or validated.',13,10,'$'
msg_audio_counts db 'GF1 events serviced: songs=$'
msg_audio_sfx    db ' sfx=$'
%ifdef DUMP_CODE
msg_patch_trigger db 'Patch trigger DOS AX=$'
msg_patch_trigger_ip db ' return IP=$'
%endif
msg_test_start   db 'Self-test: playing PRESENTA.MOD and SFX through the GF1 for five seconds...',13,10,'$'
msg_test_ok      db 'Self-test passed: GF1 timer interrupts were received.',13,10,'$'
msg_test_fail    db 'Self-test failed: no GF1 timer interrupts were received.',13,10,'$'
msg_crlf         db 13,10,'$'

ultrasnd_key     db 'ULTRASND='
game_filename    db 'PRE2.EXE',0
exec_tail        db 0,13      ; consume our switches; child receives no arguments
%ifdef DUMP_CODE
code_dump_filename db 'CODEDUMP.BIN',0
%endif
sfx_filename     db 'PRE2SFX.RAW',0
name_pres        db 'PRES.MOD',0
name_carte       db 'CARTE.MOD',0
name_code        db 'CODE.MOD',0
name_presenta    db 'PRESENTA.MOD',0
name_glace       db 'GLACE.MOD',0
name_mines       db 'MINES.MOD',0
name_mystery     db 'MYSTERY.MOD',0
name_monster     db 'MONSTER.MOD',0
name_final       db 'FINAL.MOD',0
name_bravo       db 'BRAVO.MOD',0
name_kool        db 'KOOL.MOD',0
name_boula       db 'BOULA.MOD',0

song_filename_table:
    dw name_pres, name_carte, name_code, name_presenta, name_glace
    dw 0, 0, 0, 0, name_mines, name_mystery, 0, 0
    dw name_monster, name_final, name_bravo, name_kool, name_boula

irq_lut          db 0,0,1,3,0,2,0,4,0,0,0,5,6,0,0,7
dma_lut          db 0,1,0,2,0,3,4,5
music_pan        db 3,12,12,3     ; populated by set_music_pan at startup

patch_signature:
    db 0FAh,0FCh,0BAh,0FFh,0FFh,0BEh,080h,000h
    db 0ACh,098h,08Bh,0C8h,0E3h,05Eh
patch_signature_len equ $-patch_signature

sfx_lengths:
    dw 6286,7296,9054,6630,2738,2322,0,13778,1732,7302,3630
sfx_offsets:
    dw 0,6286,13582,22636,29266,32004,34326,34326,48104,49836,57138

; Independently derived linear 0..64 -> GF1 exponent/mantissa values.
volume_table:
    dw 00000h,09FF0h,0AFF0h,0B800h,0BFF0h,0C400h,0C800h,0CC00h
    dw 0CFF0h,0D200h,0D400h,0D600h,0D800h,0DA00h,0DC00h,0DE00h
    dw 0DFF0h,0E100h,0E200h,0E300h,0E400h,0E500h,0E600h,0E700h
    dw 0E800h,0E900h,0EA00h,0EB00h,0EC00h,0ED00h,0EE00h,0EF00h
    dw 0EFF0h,0F080h,0F100h,0F180h,0F200h,0F280h,0F300h,0F380h
    dw 0F400h,0F480h,0F500h,0F580h,0F600h,0F680h,0F700h,0F780h
    dw 0F800h,0F880h,0F900h,0F980h,0FA00h,0FA80h,0FB00h,0FB80h
    dw 0FC00h,0FC80h,0FD00h,0FD80h,0FE00h,0FE80h,0FF00h,0FF80h
    dw 0FFF0h

psp_segment       dw 0
gus_base          dw 0
gus_dma1          dw 0
gus_dma2          dw 0
gus_irq           dw 0
gus_midi_irq      dw 0
gus_voice_port    dw 0
gus_command_port  dw 0
gus_data_low_port dw 0
gus_data_high_port dw 0
gus_status_port   dw 0
gus_timer_control_port dw 0
gus_timer_data_port dw 0
gus_dram_port     dw 0
irq_latch         db 0
dma_latch         db 0
old_pic_master    db 0
old_pic_slave     db 0
pan_percent       db 60
pan_reverse       db 0
pan_seen          db 0
irq_vector        db 0
vectors_installed db 0
timer_started     db 0
timer_control_shadow db 0
test_mode         db 0
patch_installed   db 0
game_line_muted   db 0
patch_segment     dw 0
patch_scan_start  dw 0
patch_scan_limit  dw 0
exec_failed       db 0
exec_error        dw 0
child_exit_code   db 0
bios_tick_start   dw 0
total_ticks       dw 0
songs_loaded      dw 0
sfx_played        dw 0
song_error        db 0
music_active      db 0
current_song      db 0FFh
requested_song    db 0
requested_sfx     db 0
sfx_round_robin   db 0
music_master      db 52

old_int21         dd 0
old_int65         dd 0
old_int66         dd 0
old_irq           dd 0
exec_params       times 14 db 0

file_handle       dw 0FFFFh
bytes_remaining   dw 0
dram_addr_low     dw 0
dram_addr_high    dw 0
peek_value        db 0
probe_value0      db 0
probe_value1      db 0

mod_song_length   db 0
mod_num_patterns  db 0
mod_pattern_bytes dw 0
tracker_tick_count db 1
tracker_speed     db 6
tracker_order     db 0
tracker_row       dw 0
channel_sample    times 4 db 0FFh
channel_period    times 4 dw 0
channel_volume    times 4 db 0
channel_slide     times 4 db 0

sample_start_low  times 31 dw 0
sample_start_high times 31 dw 0
sample_length     times 31 dw 0
sample_loop_start times 31 dw 0
sample_loop_length times 31 dw 0
sample_volume     times 31 db 0

temp_sample       db 0
temp_effect       db 0
temp_param        db 0
temp_period       dw 0
temp_trigger      db 0
temp_freq_changed db 0
temp_volume_changed db 0

voice_number      db 0
voice_mode        db 0
voice_pan         db 7
voice_frequency   dw 0
voice_volume      dw 0
voice_begin_low   dw 0
voice_begin_high  dw 0
voice_loop_low    dw 0
voice_loop_high   dw 0
voice_end_low     dw 0
voice_end_high    dw 0
voice_sample_length dw 0
voice_loop_length dw 0
voice_addr_register db 0
voice_addr_low    dw 0
voice_addr_high   dw 0

io_buffer         times IO_BUFFER_BYTES db 0
%ifdef DUMP_CODE
code_dumped       db 0
patch_trigger_ax  dw 0
patch_trigger_ip  dw 0
code_dump         times 1000h db 0
%endif
module_buffer     times MOD_HEADER_BYTES+MOD_PATTERN_LIMIT db 0
stack_space       times 1024 db 0
stack_top:
resident_end:

; Flat-binary labels are relocatable to ORG 100h; subtracting the section base
; makes the file length scalar, then add the PSP prefix retained in memory.
RESIDENT_PARAS equ ((resident_end - $$ + 100h + 15) / 16)
