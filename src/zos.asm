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
KEYGET:
OSRDCH:
        push bc
        push de
        push hl

        ; raw mode
        ld h, DEV_STDIN
        ld c, KB_CMD_SET_MODE
        ld de, KB_READ_NON_BLOCK | KB_MODE_RAW
        IOCTL()

        ei
        ; loop until a key is pressed
WAITFORKEY:
        S_READ3(DEV_STDIN, BUFFER, 3)
        or a
        jr nz, KEYERROR
        ; A is zero for sure, OR it with C to check if C is 0
        or c
        jr z, WAITFORKEY ; if no key
        ld a, (de) ; get the code from BUFFER[0]
        cp KB_RELEASED
        jr z, WAITFORKEY
        jp KEYREAD
KEYERROR:
        ; an error has occurred, handle it
        ; DE still contains the buffer address
        ld (de), a
KEYREAD:
        di

        ; go back to cooked mode
        ld h, DEV_STDIN
        ld c, KB_CMD_SET_MODE
        ld de, KB_READ_BLOCK | KB_MODE_COOKED
        IOCTL()

        pop hl
        pop de
        pop bc

        ld a, (BUFFER) ; get the code from BUFFER[0]
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
        ex de, hl
        ld bc, 254
        ei
        S_READ1(DEV_STDIN)
        di
        xor a
        ret


;OSOPEN - Open a file for reading or writing.
;   Inputs: HL addresses filename (term 0)
;           Carry set for OPENIN, cleared for OPENOUT.
;  Outputs: A = file channel (=0 if cannot open)
;           DE = file FCB
; Destroys: A,B,C,D,E,H,L,F
;
OSOPEN:
        ; Put the file name in BC
        ld b, h
        ld c, l
        ; Set the flags
        ld h, O_RDONLY
        jr c, OSOPEN_READ
        ld h, O_WRONLY | O_CREAT | O_APPEND
OSOPEN_READ:
        OPEN()
        ; Check for error, if positive, return
        or a
        ret p
OSOPEN_ERROR:
        xor a
        ret


;OSSTAT - Read file status.
;   Inputs: E = file channel
;  Outputs: Z flag set - EOF
;           (If Z then A=0)
;           DE = address of file block.
; Destroys: A,D,E,H,L,F
;
OSSTAT:
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
        OPEN()
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
        CLOSE()
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
        CLOSE()
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
        OPEN()
        pop bc
        pop de
        ; Check for errors
        or a
        jp m, SHOW_ERROR_NEG
        ld h, a
        ld (FILE_REMAIN), bc
        ld l, 1                 ; Zeal write syscall
        call FILE_TRANSFER
        CLOSE()
        or a
        jp nz, SHOW_ERROR
        ret
CLOSE_ERROR:
        ; Keep the original failure even when cleanup fails too.
        push af
        CLOSE()
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


;OSSHUT - Close disk file(s).
;   Inputs: E = file channel
;           If E=0 all files are closed (except SPOOL)
; Destroys: A,B,C,D,E,H,L,F
;
OSSHUT:
    ld a, e
    or a
    ret z
    ld h, a
    CLOSE()
    or a
    jp nz, SHOW_ERROR
    ret


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
        ; Check the error, return 0 in that case
        or a
        jr nz, GETEXT_ERROR
        ; Dereference the size from the structure
        ld hl, (BUFFER)
        ld de, (BUFFER + 2)
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
        ld h, 0 ; Return value
        ei
        EXIT()

RESET:
        xor a
        ld (OPTVAL), a
        ret

OPTVAL: DEFS 1

;LTRAP - Test ESCAPE flag and abort if set.
; Destroys: A,F
;
LTRAP:
        xor a
        ret

;TRAP - Test ESCAPE flag and abort if set;
;       every 20th call, test for keypress.
; Destroys: A,H,L,F
;
TRAP:
        ret

;
;OSCLI - Process an "operating system" command
;
OSCLI:
        jr BYE
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
