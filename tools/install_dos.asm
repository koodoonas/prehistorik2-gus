; PRE2GUS native DOS asset installer/converter
;
; Build: nasm -Wall -f bin -o INSTALL.COM tools/install_dos.asm
;
; Run from the Prehistorik 2 directory after extracting the release bundle.
; It decodes the user's original *.TRK and SAMPLE.SQZ files in place.  No game
; data is embedded here.  /Y permits replacement of previously generated
; PRE2GUS audio files without an interactive confirmation.

bits 16
org 100h

%define INPUT_BUFFER_SIZE  2048
%define OUTPUT_BUFFER_SIZE 2048
%define HISTORY_SIZE       32768
%define HISTORY_MASK       7FFFh
%define TREE_BUFFER_SIZE   1020

start:
    cli
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0FFFEh
    sti
    cld

    mov dx, msg_banner
    call print_dos
    call parse_yes_switch
    call check_package_files
    jc fatal_package
    call check_existing_outputs
    cmp byte [outputs_exist], 0
    je .convert
    cmp byte [yes_switch], 1
    je .convert
    mov dx, msg_overwrite
    call print_dos
    mov ah, 01h
    int 21h
    mov dx, msg_crlf
    call print_dos
    and al, 0DFh
    cmp al, 'Y'
    jne cancelled
.convert:
    call convert_tracks
    jc fatal_convert
    call convert_sfx
    jc fatal_convert
    mov dx, msg_success
    call print_dos
    xor al, al
    jmp exit_dos

cancelled:
    mov dx, msg_cancelled
    call print_dos
    xor al, al
    jmp exit_dos

fatal_package:
    mov dx, msg_missing
    call print_dos
    mov si, [current_input]
    call print_asciiz
    mov dx, msg_crlf
    call print_dos
    mov al, 1
    jmp exit_dos

fatal_convert:
    call abort_pair
    mov dx, msg_failed
    call print_dos
    mov si, [current_input]
    call print_asciiz
    mov dx, msg_arrow
    call print_dos
    mov si, [current_output]
    call print_asciiz
    mov dx, msg_crlf
    call print_dos
    mov al, 2

exit_dos:
    mov ah, 4Ch
    int 21h

; ---------------------------------------------------------------------------
; UI and package checks

print_dos:
    mov ah, 09h
    int 21h
    ret

print_asciiz:
    push ax
    push dx
.next:
    lodsb
    or al, al
    jz .done
    mov dl, al
    mov ah, 02h
    int 21h
    jmp .next
.done:
    pop dx
    pop ax
    ret

parse_yes_switch:
    mov byte [yes_switch], 0
    xor cx, cx
    mov cl, [80h]
    mov si, 81h
.scan:
    jcxz .done
    lodsb
    dec cx
    cmp al, '/'
    je .letter
    cmp al, '-'
    jne .scan
.letter:
    jcxz .done
    mov al, [si]
    and al, 0DFh
    cmp al, 'Y'
    jne .scan
    mov byte [yes_switch], 1
.done:
    ret

check_package_files:
    mov si, package_files
.next:
    lodsw
    or ax, ax
    jz .ok
    mov [current_input], ax
    mov dx, ax
    mov ax, 3D00h
    int 21h
    jc .fail
    mov bx, ax
    mov ah, 3Eh
    int 21h
    jmp .next
.ok:
    clc
    ret
.fail:
    stc
    ret

file_exists:
    mov ax, 3D00h
    int 21h
    jc .no
    mov bx, ax
    mov ah, 3Eh
    int 21h
    mov al, 1
    ret
.no:
    xor al, al
    ret

check_existing_outputs:
    mov byte [outputs_exist], 0
    mov si, track_table
    mov cx, 12
.track:
    mov dx, [si+2]
    call file_exists
    or al, al
    jnz .found
    add si, 8
    loop .track
    mov dx, out_sfx
    call file_exists
    or al, al
    jnz .found
    ret
.found:
    mov byte [outputs_exist], 1
    ret

; ---------------------------------------------------------------------------
; Conversion dispatch and DOS file handling

convert_tracks:
    mov word [table_pointer], track_table
    mov byte [track_remaining], 12
.next:
    mov si, [table_pointer]
    mov ax, [si]
    mov [current_input], ax
    mov ax, [si+2]
    mov [current_output], ax
    mov ax, [si+4]
    mov [expected_low], ax
    mov ax, [si+6]
    mov [expected_high], ax
    add word [table_pointer], 8

    mov dx, msg_converting
    call print_dos
    mov si, [current_input]
    call print_asciiz
    mov dx, msg_arrow
    call print_dos
    mov si, [current_output]
    call print_asciiz
    mov dx, msg_dots
    call print_dos

    call begin_pair
    jc .fail
    mov byte [decode_kind], 0
    call decode_lzss
    jc .fail_abort
    call validate_track_output
    jc .fail_abort
    call finish_pair
    jc .fail_abort
    mov dx, msg_ok
    call print_dos
    dec byte [track_remaining]
    jnz .next
    clc
    ret
.fail_abort:
    call abort_pair
.fail:
    stc
    ret

convert_sfx:
    mov word [current_input], in_sfx
    mov word [current_output], out_sfx
    mov word [expected_low], 0ED60h
    mov word [expected_high], 0
    mov dx, msg_converting
    call print_dos
    mov si, [current_input]
    call print_asciiz
    mov dx, msg_arrow
    call print_dos
    mov si, [current_output]
    call print_asciiz
    mov dx, msg_dots
    call print_dos
    call begin_pair
    jc .fail
    mov byte [decode_kind], 1
    call decode_huffman_rle
    jc .fail_abort
    call validate_output_size
    jc .fail_abort
    call finish_pair
    jc .fail_abort
    mov dx, msg_ok
    call print_dos
    clc
    ret
.fail_abort:
    call abort_pair
.fail:
    stc
    ret

begin_pair:
    mov word [input_handle], 0FFFFh
    mov word [output_handle], 0FFFFh
    mov byte [output_created], 0
    call reset_streams
    mov dx, [current_input]
    mov ax, 3D00h
    int 21h
    jc .fail
    mov [input_handle], ax
    mov dx, [current_output]
    xor cx, cx
    mov ah, 3Ch
    int 21h
    jc .close_input
    mov [output_handle], ax
    mov byte [output_created], 1
    clc
    ret
.close_input:
    mov bx, [input_handle]
    mov ah, 3Eh
    int 21h
    mov word [input_handle], 0FFFFh
.fail:
    stc
    ret

finish_pair:
    call flush_output
    pushf
    mov bx, [output_handle]
    cmp bx, 0FFFFh
    je .input
    mov ah, 3Eh
    int 21h
    mov word [output_handle], 0FFFFh
.input:
    mov bx, [input_handle]
    cmp bx, 0FFFFh
    je .closed
    mov ah, 3Eh
    int 21h
    mov word [input_handle], 0FFFFh
.closed:
    popf
    jc .fail
    mov byte [output_created], 0
    clc
    ret
.fail:
    stc
    ret

abort_pair:
    mov bx, [output_handle]
    cmp bx, 0FFFFh
    je .input
    mov ah, 3Eh
    int 21h
    mov word [output_handle], 0FFFFh
.input:
    mov bx, [input_handle]
    cmp bx, 0FFFFh
    je .delete
    mov ah, 3Eh
    int 21h
    mov word [input_handle], 0FFFFh
.delete:
    cmp byte [output_created], 0
    je .done
    mov dx, [current_output]
    mov ah, 41h
    int 21h
    mov byte [output_created], 0
.done:
    ret

reset_streams:
    mov word [input_position], 0
    mov word [input_length], 0
    mov word [output_position], 0
    mov word [output_count_low], 0
    mov word [output_count_high], 0
    mov word [history_position], 0
    mov word [mod_magic], 0
    mov word [mod_magic+2], 0
    mov byte [last_output], 0
    ret

read_byte:
    push bx
    push cx
    push dx
    mov bx, [input_position]
    cmp bx, [input_length]
    jb .have
    mov bx, [input_handle]
    mov cx, INPUT_BUFFER_SIZE
    mov dx, input_buffer
    mov ah, 3Fh
    int 21h
    jc .error
    or ax, ax
    jz .error
    mov [input_length], ax
    mov word [input_position], 0
    xor bx, bx
.have:
    mov al, [input_buffer+bx]
    inc bx
    mov [input_position], bx
    pop dx
    pop cx
    pop bx
    clc
    ret
.error:
    pop dx
    pop cx
    pop bx
    stc
    ret

flush_output:
    push ax
    push bx
    push cx
    push dx
    mov cx, [output_position]
    jcxz .ok
    mov bx, [output_handle]
    mov dx, output_buffer
    mov ah, 40h
    int 21h
    jc .error
    cmp ax, cx
    jne .error
    mov word [output_position], 0
.ok:
    pop dx
    pop cx
    pop bx
    pop ax
    clc
    ret
.error:
    pop dx
    pop cx
    pop bx
    pop ax
    stc
    ret

emit_byte:
    mov [emit_value], al
    cmp word [output_count_high], 0
    jne .history
    mov bx, [output_count_low]
    cmp bx, 1080
    jb .history
    cmp bx, 1083
    ja .history
    sub bx, 1080
    mov al, [emit_value]
    mov [mod_magic+bx], al
.history:
    mov bx, [history_position]
    mov al, [emit_value]
    mov [history_buffer+bx], al
    inc bx
    and bx, HISTORY_MASK
    mov [history_position], bx

    mov bx, [output_position]
    mov [output_buffer+bx], al
    inc bx
    mov [output_position], bx
    mov [last_output], al
    inc word [output_count_low]
    jnz .maybe_flush
    inc word [output_count_high]
.maybe_flush:
    cmp bx, OUTPUT_BUFFER_SIZE
    jb .ok
    call flush_output
    ret
.ok:
    clc
    ret

validate_output_size:
    mov ax, [output_count_low]
    cmp ax, [expected_low]
    jne .fail
    mov ax, [output_count_high]
    cmp ax, [expected_high]
    jne .fail
    clc
    ret
.fail:
    stc
    ret

validate_track_output:
    call validate_output_size
    jc .fail
    cmp byte [mod_magic], 'M'
    jne .fail
    cmp byte [mod_magic+1], '.'
    jne .fail
    cmp byte [mod_magic+2], 'K'
    jne .fail
    cmp byte [mod_magic+3], '.'
    jne .fail
    clc
    ret
.fail:
    stc
    ret

; ---------------------------------------------------------------------------
; PRE2 bit-oriented LZSS decoder

lz_get_bit:
    mov ax, [lz_bits]
    and al, 1
    mov [bit_value], al
    shr word [lz_bits], 1
    dec byte [lz_bits_left]
    jnz .return
    call read_byte
    jc .fail
    mov [word_low_byte], al
    call read_byte
    jc .fail
    mov ah, al
    mov al, [word_low_byte]
    mov [lz_bits], ax
    mov byte [lz_bits_left], 16
.return:
    mov al, [bit_value]
    clc
    ret
.fail:
    stc
    ret

decode_lzss:
    mov cx, 17
.skip_header:
    call read_byte
    jc .fail
    loop .skip_header
    cmp byte [input_buffer], 0B4h
    jne .fail
    cmp byte [input_buffer+1], 04Ch
    jne .fail
    call read_byte
    jc .fail
    mov [word_low_byte], al
    call read_byte
    jc .fail
    mov ah, al
    mov al, [word_low_byte]
    mov [lz_bits], ax
    mov byte [lz_bits_left], 16

.token:
    call lz_get_bit
    jc .fail
    or al, al
    jz .match
    call read_byte
    jc .fail
    call emit_byte
    jc .fail
    jmp .token

.match:
    call lz_get_bit
    jc .fail
    mov [lz_long], al
    call read_byte
    jc .fail
    mov [lz_lo], al
    mov byte [lz_hi], 0FFh
    cmp byte [lz_long], 0
    je .short_distance

    shl byte [lz_hi], 1
    call lz_get_bit
    jc .fail
    or [lz_hi], al
    call lz_get_bit
    jc .fail
    or al, al
    jnz .choose_length
    mov byte [lz_subtract], 2
    mov byte [loop_counter], 3
.distance_bits:
    call lz_get_bit
    jc .fail
    or al, al
    jnz .distance_ready
    shl byte [lz_hi], 1
    call lz_get_bit
    jc .fail
    or [lz_hi], al
    shl byte [lz_subtract], 1
    dec byte [loop_counter]
    jnz .distance_bits
.distance_ready:
    mov al, [lz_subtract]
    sub [lz_hi], al

.choose_length:
    mov byte [lz_length_seed], 2
    mov byte [lz_short_form], 0
    mov byte [loop_counter], 4
.short_length_bits:
    inc byte [lz_length_seed]
    call lz_get_bit
    jc .fail
    or al, al
    jnz .got_short_length
    dec byte [loop_counter]
    jnz .short_length_bits
    call lz_get_bit
    jc .fail
    or al, al
    jz .longer_length
    inc byte [lz_length_seed]
    call lz_get_bit
    jc .fail
    or al, al
    jz .seed_length
    inc byte [lz_length_seed]
.seed_length:
    xor ax, ax
    mov al, [lz_length_seed]
    mov [copy_remaining], ax
    jmp .copy_match
.got_short_length:
    mov byte [lz_short_form], 1
    xor ax, ax
    mov al, [lz_length_seed]
    mov [copy_remaining], ax
    jmp .copy_match
.longer_length:
    call lz_get_bit
    jc .fail
    or al, al
    jz .bit_length
    call read_byte
    jc .fail
    xor ah, ah
    add ax, 11h
    mov [copy_remaining], ax
    jmp .copy_match
.bit_length:
    mov word [copy_remaining], 0
    mov byte [loop_counter], 3
.three_length_bits:
    shl word [copy_remaining], 1
    call lz_get_bit
    jc .fail
    xor ah, ah
    add [copy_remaining], ax
    dec byte [loop_counter]
    jnz .three_length_bits
    add word [copy_remaining], 9
    jmp .copy_match

.short_distance:
    call lz_get_bit
    jc .fail
    or al, al
    jz .short_or_end
    mov byte [loop_counter], 3
.short_distance_bits:
    shl byte [lz_hi], 1
    call lz_get_bit
    jc .fail
    or [lz_hi], al
    dec byte [loop_counter]
    jnz .short_distance_bits
    dec byte [lz_hi]
    mov word [copy_remaining], 2
    jmp .copy_match
.short_or_end:
    cmp byte [lz_lo], 0FFh
    je .done
    mov word [copy_remaining], 2

.copy_match:
    mov al, [lz_lo]
    mov ah, [lz_hi]
    mov [lz_encoded], ax
    test ax, 8000h
    jz .fail
    neg ax
    cmp word [output_count_high], 0
    jne .distance_valid
    cmp [output_count_low], ax
    jb .fail
.distance_valid:
    mov bx, [history_position]
    add bx, [lz_encoded]
    and bx, HISTORY_MASK
    mov [copy_source], bx
.copy_loop:
    cmp word [copy_remaining], 0
    je .token
    mov bx, [copy_source]
    mov al, [history_buffer+bx]
    inc bx
    and bx, HISTORY_MASK
    mov [copy_source], bx
    call emit_byte
    jc .fail
    dec word [copy_remaining]
    jmp .copy_loop
.done:
    clc
    ret
.fail:
    stc
    ret

; ---------------------------------------------------------------------------
; PRE2 Huffman/RLE decoder for SAMPLE.SQZ

read_word_le:
    call read_byte
    jc .fail
    mov [word_low_byte], al
    call read_byte
    jc .fail
    mov ah, al
    mov al, [word_low_byte]
    clc
    ret
.fail:
    stc
    ret

huff_get_bit:
    cmp byte [huff_mask], 0
    jne .have
    call read_byte
    jc .fail
    mov [huff_byte], al
    mov byte [huff_mask], 80h
.have:
    mov al, [huff_byte]
    and al, [huff_mask]
    jz .zero
    mov byte [bit_value], 1
    jmp .shift
.zero:
    mov byte [bit_value], 0
.shift:
    shr byte [huff_mask], 1
    mov al, [bit_value]
    clc
    ret
.fail:
    stc
    ret

huff_symbol:
    xor bx, bx
.node:
    call huff_get_bit
    jc .fail
    or al, al
    jz .index_ready
    add bx, 2
.index_ready:
    mov dx, [tree_size]
    dec dx
    cmp bx, dx
    jae .fail
    mov ax, [tree_buffer+bx]
    test ax, 8000h
    jnz .leaf
    mov bx, ax
    jmp .node
.leaf:
    and ax, 7FFFh
    clc
    ret
.fail:
    stc
    ret

decode_huffman_rle:
    call read_word_le
    jc .fail
    mov [huff_target_high], ax
    call read_word_le
    jc .fail
    mov [huff_target_low], ax
    cmp ax, [expected_low]
    jne .fail
    mov ax, [huff_target_high]
    cmp ax, [expected_high]
    jne .fail
    call read_word_le
    jc .fail
    mov [tree_size], ax
    or ax, ax
    jz .fail
    cmp ax, TREE_BUFFER_SIZE
    ja .fail
    test ax, 1
    jnz .fail
    mov cx, ax
    mov di, tree_buffer
.read_tree:
    call read_byte
    jc .fail
    stosb
    loop .read_tree
    mov byte [huff_mask], 0

.symbol_loop:
    mov ax, [output_count_high]
    cmp ax, [huff_target_high]
    jb .need_symbol
    ja .done
    mov ax, [output_count_low]
    cmp ax, [huff_target_low]
    jae .done
.need_symbol:
    call huff_symbol
    jc .fail
    cmp ax, 100h
    jae .run
    call emit_byte
    jc .fail
    jmp .symbol_loop
.run:
    mov dx, [output_count_low]
    or dx, [output_count_high]
    jz .fail
    and ax, 00FFh
    cmp ax, 0
    je .extended_count
    cmp ax, 1
    je .word_count
    mov [run_remaining], ax
    jmp .emit_run
.extended_count:
    call huff_symbol
    jc .fail
    mov [run_remaining], ax
    jmp .emit_run
.word_count:
    call huff_symbol
    jc .fail
    and ax, 00FFh
    mov ah, al
    mov [run_word_high], ah
    call huff_symbol
    jc .fail
    and ax, 00FFh
    mov ah, [run_word_high]
    mov [run_remaining], ax
.emit_run:
    cmp word [run_remaining], 0
    je .symbol_loop
    mov ax, [output_count_high]
    cmp ax, [huff_target_high]
    jb .emit_one
    ja .done
    mov ax, [output_count_low]
    cmp ax, [huff_target_low]
    jae .done
.emit_one:
    mov al, [last_output]
    call emit_byte
    jc .fail
    dec word [run_remaining]
    jmp .emit_run
.done:
    clc
    ret
.fail:
    stc
    ret

; ---------------------------------------------------------------------------
; Tables and state

msg_banner      db 13,10,'PRE2GUS 1.3 native DOS installer',13,10
                db 'Converts original game audio locally; no game data is included.',13,10,'$'
msg_overwrite   db 'Converted PRE2GUS audio already exists. Replace it? [Y/N] $'
msg_converting  db 'Converting $'
msg_arrow       db ' -> $'
msg_dots        db ' ... $'
msg_ok          db 'OK',13,10,'$'
msg_missing     db 'ERROR: required file is missing: $'
msg_failed      db 'ERROR: conversion failed: $'
msg_cancelled   db 'Installation cancelled; no conversion was started.',13,10,'$'
msg_success     db 13,10,'Installation complete.',13,10
                db 'Run TEST_GUS.BAT first, then RUN_GUS.BAT.',13,10,'$'
msg_crlf        db 13,10,'$'

file_pre2       db 'PRE2.EXE',0
file_launcher   db 'PRE2GUS.COM',0
file_run        db 'RUN_GUS.BAT',0
file_test       db 'TEST_GUS.BAT',0
package_files   dw file_pre2, file_launcher, file_run, file_test
                dw in_boula, in_bravo, in_carte, in_code, in_final, in_glace
                dw in_kool, in_mines, in_monster, in_mystery, in_pres
                dw in_presenta, in_sfx, 0

in_boula        db 'BOULA.TRK',0
in_bravo        db 'BRAVO.TRK',0
in_carte        db 'CARTE.TRK',0
in_code         db 'CODE.TRK',0
in_final        db 'FINAL.TRK',0
in_glace        db 'GLACE.TRK',0
in_kool         db 'KOOL.TRK',0
in_mines        db 'MINES.TRK',0
in_monster      db 'MONSTER.TRK',0
in_mystery      db 'MYSTERY.TRK',0
in_pres         db 'PRES.TRK',0
in_presenta     db 'PRESENTA.TRK',0
in_sfx          db 'SAMPLE.SQZ',0

out_boula       db 'BOULA.MOD',0
out_bravo       db 'BRAVO.MOD',0
out_carte       db 'CARTE.MOD',0
out_code        db 'CODE.MOD',0
out_final       db 'FINAL.MOD',0
out_glace       db 'GLACE.MOD',0
out_kool        db 'KOOL.MOD',0
out_mines       db 'MINES.MOD',0
out_monster     db 'MONSTER.MOD',0
out_mystery     db 'MYSTERY.MOD',0
out_pres        db 'PRES.MOD',0
out_presenta    db 'PRESENTA.MOD',0
out_sfx         db 'PRE2SFX.RAW',0

track_table:
    dw in_boula,    out_boula,    33706, 0
    dw in_bravo,    out_bravo,    33548, 0
    dw in_carte,    out_carte,     6664, 0
    dw in_code,     out_code,       8012, 0
    dw in_final,    out_final,     55516, 0
    dw in_glace,    out_glace,     43228, 0
    dw in_kool,     out_kool,      43580, 0
    dw in_mines,    out_mines,     38764, 0
    dw in_monster,  out_monster,   38404, 0
    dw in_mystery,  out_mystery,   47414, 0
    dw in_pres,     out_pres,      48580, 0
    dw in_presenta, out_presenta,    992, 1 ; 66528 = 0x000103E0

yes_switch       db 0
outputs_exist    db 0
track_remaining db 0
table_pointer    dw 0
current_input    dw 0
current_output   dw 0
expected_low     dw 0
expected_high    dw 0
input_handle     dw 0FFFFh
output_handle    dw 0FFFFh
output_created   db 0
decode_kind      db 0

input_position   dw 0
input_length     dw 0
output_position  dw 0
output_count_low dw 0
output_count_high dw 0
history_position dw 0
last_output      db 0
emit_value       db 0
mod_magic        times 4 db 0

bit_value        db 0
word_low_byte    db 0
loop_counter     db 0
lz_bits          dw 0
lz_bits_left     db 0
lz_long          db 0
lz_lo            db 0
lz_hi            db 0
lz_subtract      db 0
lz_length_seed   db 0
lz_short_form    db 0
lz_encoded       dw 0
copy_source      dw 0
copy_remaining   dw 0

huff_byte        db 0
huff_mask        db 0
huff_target_low  dw 0
huff_target_high dw 0
tree_size        dw 0
run_remaining    dw 0
run_word_high    db 0

input_buffer     times INPUT_BUFFER_SIZE db 0
output_buffer    times OUTPUT_BUFFER_SIZE db 0
tree_buffer      times TREE_BUFFER_SIZE db 0
history_buffer   times HISTORY_SIZE db 0
