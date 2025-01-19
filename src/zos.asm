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


        MACRO KB_MODE MODE
                ; raw mode
                ld h, DEV_STDIN
                ld c, KB_CMD_SET_MODE
                ld de, MODE
                IOCTL()
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
        KB_MODE(KB_READ_NON_BLOCK | KB_MODE_RAW)        ; default to raw keyboard for INKEYs

        ld a, b
        or c
        jr z, @skipload
        ; load file

        ld hl, ACCS ; copy filename to string buffer
        ex de, hl
        ldir
        ; Reset Z flag
        or 1
@skipload:
        ld de, 0xF800
        ld hl, USER ; start of user memory
        ret
;

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
;

;OSRDCH - Read from the current input stream (keyboard).
;  Outputs: A = character
; Destroys: A,F
;
OSRDCH:
        call OSKEY      ; check for a key
        ret c           ; return if carry set
        jr OSRDCH       ; loop until key is press
;

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
;

;OSLINE - Read/edit a complete line, terminated by CR.
;   Inputs: HL addresses destination buffer.
;           (L=0)
;  Outputs: Buffer filled, terminated by CR.
;           A=0.
; Destroys: A,B,C,D,E,H,L,F
;
OSLINE:
        push hl ; save buffer address
        KB_MODE(KB_READ_BLOCK | KB_MODE_COOKED) ; switch to cooked to read a "line"
        pop hl  ; pop buffer address

        ex de, hl
        ld bc, 254
        ei
        S_READ1(DEV_STDIN)
        di
        xor a

        push af ; save S_READ1 error
        push hl ; save buffer address
        KB_MODE(KB_READ_NON_BLOCK | KB_MODE_RAW); switch back to raw
        pop hl  ; pop buffer address
        pop af  ; pop the S_READ1 error

        ret
;

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
        jr c, @read
        ld h, O_WRONLY | O_CREAT | O_APPEND
@read:
        OPEN()
        ; Check for error, if positive, return
        or a
        ret p
@error:
        xor a
        ret
;

;OSSTAT - Read file status.
;   Inputs: E = file channel
;  Outputs: Z flag set - EOF
;           (If Z then A=0)
;           DE = address of file block.
; Destroys: A,D,E,H,L,F
;
OSSTAT:
        ret
;


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
        ; If we read 0 byte, it's the end of the file, it's not exactly how it should
        ; be done but it's the simplest solution for now
        ld a, b
        or c
        jr z, @last
        ; No way to return an error, make the assumption it's a success
        ld a, (de)
        pop hl
        pop de
        ret
@last:
        scf
        pop hl
        pop de
        ret
;

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
        pop hl
        pop de
        ret
;

;OSLOAD - Load an area of memory from a file.
;   Inputs: HL addresses filename (NULL-term)
;           DE = address at which to load
;           BC = maximum allowed size (bytes)
;  Outputs: Carry reset indicates no room for file.
; Destroys: A,B,C,D,E,H,L,F
;
OSLOAD:
        ; Open the file for writing
        push de
        push bc
        ld b, h
        ld c, l
        ld h, O_RDONLY
        OPEN()
        pop bc
        pop de
        ; Check for errors
        or a
        jp m, SHOW_ERROR_NEG
        ; Read the data
        ld h, a
        ld bc, 0x2000   ; TODO: load data in chunks up to BC (free memory size)
        READ()
        ld (OSLOAD_SIZE), bc
        CLOSE()
        scf   ; For now, always accept the file, do not check the size
        ret

OSLOAD_SIZE: DEFW 0x2000
;

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
        ; Write the data
        ld h, a
        WRITE()
        CLOSE()
        ret
;

;
SHOW_ERROR_NEG:
        neg
SHOW_ERROR:
        ret
;

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
    ret
;

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
        jr nz, @error
        ; Dereference the size from the structure
        ld hl, (BUFFER)
        ld de, (BUFFER + 2)
        ret
@error:
        ld de, 0
        ld h, d
        ld l, e
        ret
;

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
        jr nz, @error
        ld h, b
        ld l, c
        ex de, hl
        ret
@error:
        ; Return 0 in terms of error
        ld de, 0
        ld h, d
        ld l, e
        ret
;

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
        ret
;

;
PROMPT:
        ld a, '>'
        call OSWRCH
        ld a, ' '
        jp OSWRCH
;

;
;BYE - Stop interrupts and return to Shell.
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
;

;TRAP - Test ESCAPE flag and abort if set;
;       every 20th call, test for keypress.
; Destroys: A,H,L,F
;
TRAP:
        ret
;

;
;OSCLI - Process an "operating system" command
;
OSCLI:
        ; TODO: implement more than "BYE"
        jr BYE
        ret
;

;
;OSKEY - Read key with time-limit, test for ESCape.
;Main function is carried out in user patch.
;   Inputs: HL = time limit (centiseconds)
;  Outputs: Carry reset if time-out
;           If carry set A = character
; Destroys: A,H,L,F
;
OSKEY:
        push bc
        push de
        push hl

        ei
@getkey:
        S_READ3(DEV_STDIN, BUFFER, 3)
        or a    ; did an error occur?
        jr nz, @error
        or c    ; did we read any bytes?
        jr z, @error ; if no key

        ld a, (de) ; get the code from BUFFER[0]
        cp KB_RELEASED  ; ignore key releases
        jr z, @error

        scf
        jp @read
@error:
        ; an error has occurred, handle it
        xor a   ; clear carry flag
@read:
        di

        pop hl
        pop de
        pop bc

        ld a, (BUFFER) ; get the code from BUFFER[0]
        ret
;

;
OSCALL:
        ret
;

;
    ; Make sure it's big enough for storing the stat
BUFFER: DEFS ZOS_STAT_SIZE
