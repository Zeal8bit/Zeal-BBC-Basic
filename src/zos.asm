    INCLUDE "zos_sys.asm"
    INCLUDE "zos_keyboard.asm"

        PUBLIC	OSINIT
        PUBLIC	OSRDCH
        PUBLIC	OSWRCH
        PUBLIC	OSLINE
        PUBLIC	OSSAVE
        PUBLIC	OSLOAD
        PUBLIC	OSOPEN
        PUBLIC	OSSHUT
        PUBLIC	OSCLEAN
        PUBLIC	OSBGET
        PUBLIC	OSBPUT
        PUBLIC	OSSTAT
        PUBLIC	GETEXT
        PUBLIC	GETPTR
        PUBLIC	PUTPTR
        PUBLIC	PROMPT
        PUBLIC	RESET
        PUBLIC	LTRAP
        PUBLIC	OSCLI
        PUBLIC	TRAP
        PUBLIC	OSKEY
        PUBLIC	OSCALL
;
        EXTERN	ESCAPE
        EXTERN	EXTERR
        EXTERN	CHECK
        EXTERN	CRLF
        EXTERN	TELL
;
        EXTERN	ACCS
        EXTERN	FREE
        EXTERN	HIMEM
        EXTERN	ERRLIN
        EXTERN	USER


        ; Interpreter arithmetic uses the alternate register bank. The OS
        ; reserves that bank for interrupt handlers, so every enabled window
        ; must save it, including blocking console reads.
        MACRO SAVE_ALTERNATES _
                ex af, af'
                push af
                ex af, af'
                exx
                push bc
                push de
                push hl
                exx
        ENDM
        MACRO RESTORE_ALTERNATES _
                di
                exx
                pop hl
                pop de
                pop bc
                exx
                ex af, af'
                pop af
                ex af, af'
        ENDM

;OSINIT - Initialise RAM mapping etc.
;If BASIC is entered by BBCBASIC FILENAME then file
;FILENAME.BBC is automatically CHAINed.
;   Outputs: DE = initial value of HIMEM (top of RAM)
;            HL = initial value of PAGE (user program)
;            Z-flag reset indicates AUTO-RUN.
;  Destroys: A,B,C,D,E,H,L,F
;
OSINIT:
        di       ; disable interrupts
        ld a, b
        or c
        jr z, SKIPLOAD
        ; load file

        ld hl, ACCS ; copy filename to string buffer
        ex de, hl
        ldir
        ; Reset Z flag
        or 1
SKIPLOAD:
        push af                 ; preserve the auto-run decision
        ld hl, FILE_CHANNELS
        ld de, FILE_CHANNELS + 1
        ld bc, 127
        ld (hl), 0
        ldir                    ; initialize this interpreter's ownership table
        call INPUT_RAW
        pop af
        ld de, 0xF800
        ld hl, USER ; start of user memory
        ret

;PTEXT - Print text
;   Inputs: HL = address of text
;            B = number of characters to print
; Destroys: A,B,H,L,F
;
CPTEXT:
        push de
        push bc
        ; Put buffer in DE
        ex de, hl
        ld c, b
        ld b, 0
        S_WRITE1(DEV_STDOUT)
        pop bc
        pop de
        ret


;OSRDCH - Read from the current input stream (keyboard).
;  Outputs: A = character
; Destroys: A,F
;
OSRDCH:
        push bc
        push de
        push hl
WAITFORKEY:
        ld a, (RAW_INPUT)
        or a
        jr z, KEY_STREAM
        call POLL_INPUT
        ld a, (ESC_PENDING)
        or a
        jr nz, KEY_ESCAPE
        call KEY_DEQUEUE
        jr nc, WAITFORKEY
KEY_RETURN:
        pop hl
        pop de
        pop bc
        ret
KEY_STREAM:
        SAVE_ALTERNATES()
        ei
        S_READ3(DEV_STDIN, KEY_EVENTS, 1)
        RESTORE_ALTERNATES()
        or a
        jp nz, SHOW_ERROR
        ld a, c
        or a
        jr nz, KEY_STREAM_BYTE
        ld a, ERR_NO_MORE_ENTRIES
        jp SHOW_ERROR
KEY_STREAM_BYTE:
        ld a, (KEY_EVENTS)
        jr KEY_RETURN
KEY_ESCAPE:
        pop hl
        pop de
        pop bc
        jp ESCAPE

; Mode changes preserve the interpreter's main register pairs.
INPUT_RAW:
        push bc
        push de
        push hl
        ld h, DEV_STDIN
        ld c, KB_CMD_SET_MODE
        ld de, KB_READ_NON_BLOCK | KB_MODE_RAW
        IOCTL()
        or a
        ld a, 0
        jr nz, INPUT_RAW_DONE    ; redirected/non-keyboard stdin cannot be polled
        inc a
INPUT_RAW_DONE:
        ld (RAW_INPUT), a
        pop hl
        pop de
        pop bc
        ret
INPUT_COOKED:
        push bc
        push de
        push hl
        xor a
        ld (RAW_INPUT), a
        ld (KEY_MODIFIERS), a
        ld h, DEV_STDIN
        ld c, KB_CMD_SET_MODE
        ld de, KB_READ_BLOCK | KB_MODE_COOKED
        IOCTL()
        pop hl
        pop de
        pop bc
        ret

;OSWRCH - Write a character to console output.
;   Inputs: A = character.
; Destroys: Nothing
;
OSWRCH:
        ld (BUFFER), a
        push af
        push bc
        push de
        push hl
        S_WRITE3(DEV_STDOUT, BUFFER, 1)
        pop hl
        pop de
        pop bc
        pop af
        ret

;OSLINE - Read/edit a complete line, terminated by CR.
;   Inputs: HL addresses destination buffer.
;           (L=0)
;  Outputs: Buffer filled, terminated by CR.
;           A=0.
; Destroys: A,B,C,D,E,H,L,F
;
OSLINE:
        SAVE_ALTERNATES()
        call INPUT_COOKED
        ex de, hl
        ld bc, 254
        ei
        S_READ1(DEV_STDIN)
        di
        call INPUT_RAW
        RESTORE_ALTERNATES()
        xor a
        ret


;OSOPEN - Open a file for reading or writing.
;   Inputs: HL addresses filename (term 0)
;           Carry clear for OPENOUT, set with A=0 for OPENIN,
;           set with A=1 for OPENUP (as supplied by the evaluator).
;  Outputs: A = file channel (=0 if cannot open)
; Destroys: A,B,C,D,E,H,L,F
;
OSOPEN:
        ; Put the file name in BC
        ld b, h
        ld c, l
        ; Set the flags
        ld h, O_WRONLY | O_CREAT | O_TRUNC
        jr nc, OSOPEN_READ
        ld h, O_RDONLY
        or a
        jr z, OSOPEN_READ
        ld h, O_RDWR
OSOPEN_READ:
        call FILE_OPEN
        ; Check for error, if positive, return
        or a
        ret p
OSOPEN_ERROR:
        xor a
        ret


; Every file opened by this adapter, including temporary load/save handles,
; is owned until CLOSE succeeds. Zeal descriptors are shared with the caller;
; never infer ownership merely from a descriptor being open in the OS.
FILE_OPEN:
        OPEN()
        or a
        ret m
        push af
        ld e, a
        call CHANNEL_ENTRY
        ld (hl), 1
        pop af
        or a
        ret nz
        ; Native descriptor zero cannot be represented as a BASIC channel.
        ; It was just allocated by us, so close it rather than leak it.
        ld h, 0
        call FILE_CLOSE
        ld a, -ERR_INVALID_FILEDEV
        ret

FILE_CLOSE:
        push hl
        CLOSE()
        pop hl
        or a
        ret nz                  ; retain ownership so failed closes can be retried
        push af
        ld e, h
        call CHANNEL_ENTRY
        ld (hl), 0
        pop af
        ret

; E is a nonnegative descriptor (0..127, the successful OPEN return range).
CHANNEL_ENTRY:
        ld d, 0
        ld hl, FILE_CHANNELS
        add hl, de
        ret

;OSSTAT - Read file status.
;   Inputs: E = file channel
;  Outputs: Z flag set - EOF
;           (If Z then A=0)
; Destroys: A,D,E,H,L,F
;
OSSTAT:
        push bc
        ld h, e
        ld bc, 0
        ld de, 0
        ld a, SEEK_CUR
        SEEK()                  ; inspect the position without consuming a byte
        or a
        jp nz, SHOW_ERROR
        push bc
        push de
        ld de, BUFFER
        DSTAT()
        or a
        jp nz, SHOW_ERROR
        pop de                  ; BCDE = current position
        pop bc
        ; Compare the full 32-bit size with the position, most significant first.
        ld a, (BUFFER + 4)
        cp b
        jr nz, FILE_EOF_COMPARE
        ld a, (BUFFER + 3)
        cp c
        jr nz, FILE_EOF_COMPARE
        ld a, (BUFFER + 2)
        cp d
        jr nz, FILE_EOF_COMPARE
        ld a, (BUFFER + 1)
        cp e
FILE_EOF_COMPARE:
        jr c, FILE_AT_EOF        ; also EOF if the file shrank below the position
        jr z, FILE_AT_EOF
        ld a, 1
        or a                    ; NZ: bytes remain
        pop bc
        ret
FILE_AT_EOF:
        xor a                   ; Z: position is at/past the end
        pop bc
        ret


;OSBGET - Read a byte from a random disk file.
;   Inputs: E = file channel
;  Outputs: A = byte read
;           Carry set if LAST BYTE of file
; Destroys: A,B,C,F
;
OSBGET:
        push de
        push hl
        ld h, e
        ld de, BUFFER
        ld bc, 1
        READ()
        or a
        jp nz, SHOW_ERROR
        ; If we read 0 byte, it's the end of the file, it's not exactly how it should
        ; be done but it's the simplest solution for now
        ld a, b
        or c
        jr z, OSBGET_LAST
        ; No way to return an error, make the assumption it's a success
        ld a, (de)
        pop hl
        pop de
        ret
OSBGET_LAST:
        scf
        pop hl
        pop de
        ret

;OSBPUT - Write a byte to a random disk file.
;   Inputs: E = file channel
;           A = byte to write
; Destroys: A,B,C,F
;
OSBPUT:
        push de
        push hl
        ld h, e
        ld de, BUFFER
        ld bc, 1
        ; Byte to write in BUFFER
        ld (de), a
        WRITE()
        or a
        jp nz, SHOW_ERROR
        dec bc
        ld a, b
        or c
        jp nz, TRANSFER_ERROR
        pop hl
        pop de
        ret

;OSLOAD - Load an area of memory from a file.
;   Inputs: HL addresses filename (NULL-term)
;           DE = address at which to load
;           BC = maximum allowed size (bytes)
;  Outputs: Carry reset indicates no room for file.
; Destroys: A,B,C,D,E,H,L,F
;
OSLOAD:
        push de
        push bc
        ld b, h
        ld c, l
        ld h, O_RDONLY
        call FILE_OPEN
        pop bc
        pop de
        or a
        jp m, SHOW_ERROR_NEG
        ld h, a
        ; Inspect the full size before touching BASIC memory. Stat starts with
        ; one flags byte, followed by a little-endian 32-bit size.
        push hl
        push de
        push bc
        ld de, BUFFER
        DSTAT()
        or a
        jr nz, LOAD_STAT_ERROR
        ld hl, (BUFFER + 3)
        ld a, h
        or l
        jr nz, LOAD_TOO_LARGE
        ld hl, (BUFFER + 1)
        pop bc
        or a
        sbc hl, bc
        pop de
        pop hl
        jr c, LOAD_FITS
        jr z, LOAD_FITS
LOAD_NO_ROOM:
        call FILE_CLOSE
        or a
        jp nz, SHOW_ERROR
        or a                    ; carry clear: LOAD0 reports "No room"
        ret
LOAD_TOO_LARGE:
        pop bc
        pop de
        pop hl
        jr LOAD_NO_ROOM
LOAD_STAT_ERROR:
        pop bc
        pop de
        pop hl
        jp CLOSE_ERROR
LOAD_FITS:
        ld bc, (BUFFER + 1)
        ld (OSLOAD_SIZE), bc
        ld (FILE_REMAIN), bc
        ld l, 0                 ; Zeal read syscall
        call FILE_TRANSFER
        call FILE_CLOSE
        or a
        jp nz, SHOW_ERROR
        scf
        ret

OSLOAD_SIZE: DEFW 0
FILE_REMAIN: DEFW 0

; Transfer FILE_REMAIN bytes, splitting requests at virtual-page boundaries.
; H = channel, L = read/write syscall, DE = address. Retry short transfers.
FILE_TRANSFER:
        ld bc, (FILE_REMAIN)
        ld a, b
        or c
        ret z
        call FILE_CHUNK
        SYSCALL
        or a
        jp nz, CLOSE_ERROR
        ld a, b
        or c
        jr z, FILE_STALLED       ; EOF before stat size, or no write progress
        push hl
        ld hl, (FILE_REMAIN)
        or a
        sbc hl, bc
        ld (FILE_REMAIN), hl
        ld h, b
        ld l, c
        add hl, de
        ex de, hl
        pop hl
        jr FILE_TRANSFER
FILE_STALLED:
        ld a, ERR_FAILURE
        jp CLOSE_ERROR

; BC = min(BC, bytes until next 16KB boundary). Preserve HL and DE.
FILE_CHUNK:
        push hl
        push de
        ld a, d
        and 0x3f
        ld d, a
        ld hl, 0x4000
        or a
        sbc hl, de
        or a
        sbc hl, bc
        jr nc, FILE_CHUNK_READY
        add hl, bc
        ld b, h
        ld c, l
FILE_CHUNK_READY:
        pop de
        pop hl
        ret

;OSSAVE - Save an area of memory to a file.
;   Inputs: HL addresses filename (term CR)
;           DE = start address of data to save
;           BC = length of data to save (bytes)
; Destroys: A,B,C,D,E,H,L,F
;
OSSAVE:
        ; Open the file for writing
        push de
        push bc
        ld b, h
        ld c, l
        ld h, O_WRONLY | O_CREAT | O_TRUNC
        call FILE_OPEN
        pop bc
        pop de
        ; Check for errors
        or a
        jp m, SHOW_ERROR_NEG
        ld h, a
        ld (FILE_REMAIN), bc
        ld l, 1                 ; Zeal write syscall
        call FILE_TRANSFER
        call FILE_CLOSE
        or a
        jp nz, SHOW_ERROR
        ret
CLOSE_ERROR:
        ; Keep the original failure even when cleanup fails too.
        push af
        call FILE_CLOSE
        pop af
        jr SHOW_ERROR
TRANSFER_ERROR:
        ld a, ERR_FAILURE
        jr SHOW_ERROR
SHOW_ERROR_NEG:
        neg
SHOW_ERROR:
        ; BASIC OS errors occupy 128..255; retain the Zeal error in bits 0..6.
        or 0x80
        call EXTERR
        DEFM "Zeal OS error"
        DEFB 0


;OSSHUT - Close a BASIC-owned channel, or all owned channels if E=0.
; Explicit closes report errors; error unwinding uses OSCLEAN directly.
OSSHUT:
        ld a, e
        or a
        jr z, CLOSE_ALL
        bit 7, e
        jr nz, CHANNEL_ERROR
        call CHANNEL_ENTRY
        ld a, (hl)
        or a
        jr z, CHANNEL_ERROR
        ld h, e
        call FILE_CLOSE
        or a
        jp nz, SHOW_ERROR
        ret
CHANNEL_ERROR:
        ld a, ERR_INVALID_FILEDEV
        jp SHOW_ERROR
CLOSE_ALL:
        call OSCLEAN
        or a
        jp nz, SHOW_ERROR
        ret

; Best-effort cleanup: attempt every owned close and return the first error in
; A, without raising a new BASIC error while another error is being reported.
OSCLEAN:
        xor a
        ld (CLOSE_FAILURE), a
        ld e, 0
CLEAN_CHANNEL:
        push de
        call CHANNEL_ENTRY
        ld a, (hl)
        or a
        jr z, CLEAN_NEXT
        ld h, e
        call FILE_CLOSE
        or a
        jr z, CLEAN_NEXT
        ld b, a
        ld a, (CLOSE_FAILURE)
        or a
        jr nz, CLEAN_NEXT
        ld a, b
        ld (CLOSE_FAILURE), a
CLEAN_NEXT:
        pop de
        inc e
        bit 7, e
        jr z, CLEAN_CHANNEL
        ld a, (CLOSE_FAILURE)
        or a
        ret

FILE_CHANNELS: DEFS 128
CLOSE_FAILURE: DEFB 0

;
;GETEXT - Find file size.
;   Inputs: E = file channel
;  Outputs: DEHL = file size (0-&800000)
; Destroys: A,B,C,D,E,H,L,F
;
GETEXT:
        ld h, e
        ld de, BUFFER
        DSTAT()
        ; Report errors before interpreting the stat buffer.
        or a
        jr nz, GETEXT_ERROR
        ; Skip s_flags; s_size is a little-endian 32-bit value at offset 1.
        ld hl, (BUFFER + 1)
        ld de, (BUFFER + 3)
        ret
GETEXT_ERROR:
        jp SHOW_ERROR

;
;GETPTR - Return file pointer.
;   Inputs: E = file channel
;  Outputs: DEHL = pointer (0-&7FFFFF)
; Destroys: A,B,C,D,E,H,L,F
;
GETPTR:
        ld h, e
        ; Use SEEK_CUR with offset 0
        ld bc, 0
        ld d, b
        ld e, c
        ld a, SEEK_CUR
        SEEK()
        or a
        jr nz, GETPTR_ERROR
        ld h, b
        ld l, c
        ex de, hl
        ret
GETPTR_ERROR:
        jp SHOW_ERROR

;
;PUTPTR - Update file pointer.
;   Inputs: A = file channel
;           DEHL = new pointer (0-&7FFFFF)
; Destroys: A,B,C,D,E,H,L,F
;
PUTPTR:
        ; Use SEEK_CUR with offset 0
        ex de, hl
        ld b, h
        ld c, l
        ; Set the opened dev
        ld h, a
        ld a, SEEK_SET
        SEEK()
        or a
        jp nz, SHOW_ERROR
        ret


PROMPT:
        ld a, '>'
        call OSWRCH
        ld a, ' '
        jp OSWRCH

;
;BYE - Stop interrupts and return to CP/M.
;
BYE:
        ld e, 0
        call OSSHUT
        call INPUT_COOKED
        ld h, 0 ; Return value
        ei
        EXIT()

RESET:
        xor a
        ld (OPTVAL), a
        ld (ESC_PENDING), a
        ld (KEY_COUNT), a
        ld (KEY_READ), a
        ld (KEY_WRITE), a
        ld a, 20
        ld (TRAP_COUNT), a
        ret

OPTVAL: DEFS 1
RAW_INPUT: DEFB 0
ESC_PENDING: DEFB 0
TRAP_COUNT: DEFB 20
KEY_COUNT: DEFB 0
KEY_READ: DEFB 0
KEY_WRITE: DEFB 0
KEY_QUEUE: DEFS 16
KEY_EVENTS: DEFS 2
KEY_MODIFIERS: DEFB 0            ; L/R Shift, L/R Ctrl, Caps Lock, Caps key down

;LTRAP - Poll and abort on Escape. Preserve all register pairs, including
; alternate registers: Zeal interrupt handlers are allowed to use them.
LTRAP:
        push bc
        push de
        push hl
        call POLL_INPUT
        ld a, (ESC_PENDING)
        or a
        pop hl
        pop de
        pop bc
        jp nz, ESCAPE
        ret

;TRAP - Service keyboard/interrupts every 20 statements or loop iterations.
TRAP:
        ld a, (TRAP_COUNT)
        dec a
        ld (TRAP_COUNT), a
        ret nz
        ld a, 20
        ld (TRAP_COUNT), a
        jr LTRAP

; Keep the interpreter interrupt-disabled except inside this guarded window.
; Save AF', BC', DE', HL' before any interrupt or keyboard syscall can run.
; Destroys main registers only; IX/IY remain owned by the interpreter.
POLL_INPUT:
        SAVE_ALTERNATES()
        ei
        nop
        di
        ld a, (RAW_INPUT)
        or a
        jr z, POLL_DONE
        ; Two bytes accommodate a complete release pair without consuming
        ; unrelated events that the decoder cannot retain.
        S_READ3(DEV_STDIN, KEY_EVENTS, 2)
        di
        or a
        jr nz, POLL_DONE
        ld a, c
        or a
        jr z, POLL_DONE
        ld b, c
        ld hl, KEY_EVENTS
POLL_EVENT:
        ld a, (hl)
        inc hl
        cp KB_RELEASED
        jr nz, POLL_PRESS
        ; The ABI promises a pair. Older drivers can return a trailing marker;
        ; ignore it without reading beyond the buffer or wrapping the counter.
        dec b
        jr z, POLL_DONE
        ld a, (hl)
        inc hl
        ld e, 0                 ; released event
        jr POLL_TRANSLATE
POLL_PRESS:
        ld e, 1                 ; pressed event
POLL_TRANSLATE:
        push bc
        push hl
        call KEY_EVENT
        pop hl
        pop bc
POLL_NEXT:
        djnz POLL_EVENT
POLL_DONE:
        RESTORE_ALTERNATES()
        ret

; Raw keyboard events -> US-ASCII characters. Modifier-only and unsupported
; special keys produce no character. E=1 for a press, E=0 for a release.
KEY_EVENT:
        ld c, a
        ld d, 1
        cp KB_LEFT_SHIFT
        jp z, KEY_MODIFIER
        ld d, 2
        cp KB_RIGHT_SHIFT
        jp z, KEY_MODIFIER
        ld d, 4
        cp KB_LEFT_CTRL
        jp z, KEY_MODIFIER
        ld d, 8
        cp KB_RIGHT_CTRL
        jp z, KEY_MODIFIER
        cp KB_CAPS_LOCK
        jp z, KEY_CAPS
        ld a, e
        or a
        ret z
        ld a, c
        cp KB_ESC
        jp z, KEY_ESCAPE_EVENT
        cp 27
        jp z, KEY_ESCAPE_EVENT
        cp 0x80
        jr nc, KEY_KEYPAD
        ; Ctrl-letters and Ctrl-@.._ produce ASCII control codes.
        ld a, (KEY_MODIFIERS)
        and 12
        jr z, KEY_PRINTABLE
        ld a, c
        and 0xdf
        cp '@'
        jr c, KEY_PRINTABLE
        cp 0x60
        jr nc, KEY_PRINTABLE
        and 31
        jp KEY_ENQUEUE
KEY_PRINTABLE:
        ld a, c
        cp 'a'
        jr c, KEY_PUNCTUATION
        cp 'z' + 1
        jr nc, KEY_PUNCTUATION
        ld a, (KEY_MODIFIERS)
        ld d, a
        and 3
        ld a, d
        jr z, KEY_LETTER_CASE
        xor 16
KEY_LETTER_CASE:
        and 16
        ld a, c
        jp z, KEY_ENQUEUE
        and 0xdf
        jp KEY_ENQUEUE
KEY_PUNCTUATION:
        ld a, (KEY_MODIFIERS)
        and 3
        ld a, c
        jp z, KEY_ENQUEUE
        ld hl, KEY_SHIFT_BASE
        ld bc, KEY_SHIFT_SIZE
        cpir
        jp nz, KEY_ENQUEUE
        ld de, KEY_SHIFTED - KEY_SHIFT_BASE - 1
        add hl, de
        ld a, (hl)
        jp KEY_ENQUEUE
KEY_KEYPAD:
        sub KB_NUMPAD_0
        cp 16
        ret nc
        ld e, a
        ld d, 0
        ld hl, KEY_PAD_ASCII
        add hl, de
        ld a, (hl)
        jp KEY_ENQUEUE
KEY_MODIFIER:
        ld a, e
        or a
        ld a, (KEY_MODIFIERS)
        jr z, KEY_MODIFIER_UP
        or d
        jr KEY_MODIFIER_STORE
KEY_MODIFIER_UP:
        ld e, a
        ld a, d
        cpl
        and e
KEY_MODIFIER_STORE:
        ld (KEY_MODIFIERS), a
        ret
KEY_CAPS:
        ld a, e
        or a
        ld a, (KEY_MODIFIERS)
        jr z, KEY_CAPS_UP
        bit 5, a
        ret nz                  ; ignore repeated presses until the release
        xor 16
        or 32
        jr KEY_MODIFIER_STORE
KEY_CAPS_UP:
        and 0xdf
        jr KEY_MODIFIER_STORE
KEY_ESCAPE_EVENT:
        ld a, 1
        ld (ESC_PENDING), a
        ret

KEY_SHIFT_BASE:
        DEFB "1234567890-=[]", 0x5c, 0x3b, 0x27, 0x2c, 0x2e, 0x2f, 0x60
DEFC KEY_SHIFT_SIZE = $ - KEY_SHIFT_BASE
KEY_SHIFTED:
        DEFB "!@#$%^&*()_+{}", 0x7c, 0x3a, 0x22, 0x3c, 0x3e, 0x3f, 0x7e
KEY_PAD_ASCII:
        DEFB "0123456789.", 10, "+-*/"

; Retain ordinary keypresses for GET while polling for Escape. Like the
; hardware FIFO, this bounded queue drops new keys when full, but polling
; continues so Escape always remains reachable.
KEY_ENQUEUE:
        ld c, a
        ld a, (KEY_COUNT)
        cp 16
        ret nc
        inc a
        ld (KEY_COUNT), a
        ld a, (KEY_WRITE)
        ld e, a
        ld d, 0
        ld hl, KEY_QUEUE
        add hl, de
        ld (hl), c
        inc a
        and 15
        ld (KEY_WRITE), a
        ret

; Carry set and A = next key, carry clear if none.
KEY_DEQUEUE:
        ld a, (KEY_COUNT)
        or a
        ret z
        dec a
        ld (KEY_COUNT), a
        ld a, (KEY_READ)
        ld e, a
        ld d, 0
        ld hl, KEY_QUEUE
        add hl, de
        inc a
        and 15
        ld (KEY_READ), a
        ld a, (hl)
        scf
        ret

;
;OSCLI - Process an "operating system" command
;
OSCLI:
        jp BYE
        ret

;
;OSKEY - Read key with time-limit, test for ESCape.
;Main function is carried out in user patch.
;   Inputs: HL = time limit (centiseconds)
;  Outputs: Carry reset if time-out
;           If carry set A = character
; Destroys: A,H,L,F
;
OSKEY:
        xor a
        ret

OSCALL:
        ret

    ; Make sure it's big enough for storing the stat
BUFFER: DEFS ZOS_STAT_SIZE
