; LOAD$ imports numbered ASCII source, independent of filename extension.
; ACCS holds one source line; the original lexer writes tokens to BUFFER.
; Program records always retain a valid end marker, even during an import.
        INCLUDE "zos_sys.asm"
        PUBLIC Z_LOAD_TEXT, Z_IMPORT_TEXT, Z_TEXT_RESET
        EXTERN EXPRS, LEXAN2, LINNUM, LOADFAIL, CLEAR, WARM, ERROR, EXTERR
        EXTERN FILE_OPEN, FILE_CLOSE, SHOW_ERROR, SHOW_ERROR_NEG, OSBGET, LTRAP
        EXTERN ACCS, BUFFER, PAGE, TOP, TELL, PBCDL, CRLF
        EXTERN TEXT_ACTIVE, TEXT_CHANNEL, TEXT_EOF, TEXT_SKIP_LF
        EXTERN TEXT_PREVIOUS, TEXT_SOURCE_LINE

Z_LOAD_TEXT:
        inc iy                  ; consume '$', then use ordinary string expressions
        call EXPRS
        xor a
        ld (de),a
        call Z_IMPORT_TEXT
        jp WARM

; ACCS contains the NUL-terminated filename. Opening failure preserves the
; existing program. Once open, replace it; all later failures discard the import.
Z_IMPORT_TEXT:
        ld bc,ACCS
        ld h,O_RDONLY
        call FILE_OPEN
        or a
        jp m,SHOW_ERROR_NEG
        ld (TEXT_CHANNEL),a
        xor a
        ld (TEXT_EOF),a
        ld (TEXT_SKIP_LF),a
        ld hl,0
        ld (TEXT_PREVIOUS),hl
        ld (TEXT_SOURCE_LINE),hl
        call TEXT_CLEAR         ; clear old text, variables and error handler
        ld a,1
        ld (TEXT_ACTIVE),a
TEXT_NEXT:
        ld a,(TEXT_EOF)
        or a
        jr nz,TEXT_FINISH
        ld hl,(TEXT_SOURCE_LINE)
        inc hl
        ld (TEXT_SOURCE_LINE),hl
        ld a,h
        or l
        jp z,TEXT_BAD           ; do not wrap the diagnostic source line counter
        call LTRAP
        call TEXT_READ_LINE
        ld iy,ACCS
        call TEXT_SPACE
        cp 10
        jr z,TEXT_NEXT          ; ignore blank lines
        sub '0'
        cp 10
        jp nc,TEXT_BAD          ; never execute unnumbered source as a command
        call LINNUM
        ld a,h
        or l
        jp z,TEXT_BAD
        ld de,(TEXT_PREVIOUS)
        push hl
        or a
        sbc hl,de
        pop hl
        jp c,TEXT_BAD
        jp z,TEXT_BAD           ; require strictly ascending, nonzero numbers
        ld (TEXT_PREVIOUS),hl
        call TEXT_SPACE
        cp 10
        jp z,TEXT_BAD           ; a bare number is not an importable statement
        ld de,BUFFER
        ld c,1                 ; same left-side lexical mode as keyboard entry
        call LEXAN2
        ld (de),a              ; lexer returns LF; E is token-body length
        call TEXT_APPEND
        jr TEXT_NEXT
TEXT_FINISH:
        ld a,(TEXT_CHANNEL)
        ld h,a
        call FILE_CLOSE
        or a
        jp nz,SHOW_ERROR
        xor a
        ld (TEXT_ACTIVE),a
        jp CLEAR

TEXT_SPACE:
        ld a,(iy)
        cp ' '
        jr z,TEXT_SPACE_NEXT
        cp 9
        ret nz
TEXT_SPACE_NEXT:
        inc iy
        jr TEXT_SPACE

; Stream a bounded line through OSBGET, reusing the existing syscall adapter.
; Accept LF, CRLF, CR and an unterminated final line. Keep tabs literal inside
; statements, matching keyboard entry; TEXT_SPACE accepts tab indentation.
TEXT_READ_LINE:
        ld hl,ACCS
        ld b,0
TEXT_READ_BYTE:
        push bc
        ld a,(TEXT_CHANNEL)
        ld e,a
        call OSBGET
        pop bc
        jr c,TEXT_READ_EOF
        ld c,a
        ld a,(TEXT_SKIP_LF)
        or a
        ld a,0
        ld (TEXT_SKIP_LF),a
        ld a,c
        jr z,TEXT_READ_CHAR
        cp 10
        jr z,TEXT_READ_BYTE
TEXT_READ_CHAR:
        cp 10
        jr z,TEXT_READ_END
        cp 13
        jr z,TEXT_READ_CR
        cp 9
        jr z,TEXT_READ_STORE
        cp 32
        jp c,TEXT_BAD
        cp 127
        jp nc,TEXT_BAD          ; reject binary/tokenized input and non-ASCII
TEXT_READ_STORE:
        ld c,a
        ld a,b
        cp 255
        jr z,TEXT_LONG
        ld (hl),c
        inc hl
        inc b
        jr TEXT_READ_BYTE
TEXT_READ_CR:
        ld a,1
        ld (TEXT_SKIP_LF),a
        jr TEXT_READ_END
TEXT_READ_EOF:
        ld a,1
        ld (TEXT_EOF),a
TEXT_READ_END:
        ld (hl),10
        ret

; TOP includes the three-byte end marker. Replace it with a record and move
; the marker to the new end. Leave a 256-byte margin below the current stack.
TEXT_APPEND:
        ld c,e
        inc c                  ; body plus LF
        ld b,0
        ld hl,(TOP)
        push hl
        add hl,bc
        inc hl
        inc hl
        inc hl                 ; new TOP = old TOP + body length + 4
        push hl
        ld de,256
        add hl,de
        jp c,TEXT_NO_ROOM
        or a
        sbc hl,sp
        jp nc,TEXT_NO_ROOM
        pop hl
        ld (TOP),hl
        pop hl
        dec hl
        dec hl
        dec hl
        ld a,c
        add a,3
        ld (hl),a
        inc hl
        ld de,(TEXT_PREVIOUS)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ex de,hl
        ld hl,BUFFER
        ldir
        ex de,hl
        ld (hl),0
        inc hl
        ld (hl),255
        inc hl
        ld (hl),255
        ret
TEXT_NO_ROOM:
        call Z_TEXT_RESET
        xor a
        jp ERROR
TEXT_LONG:
        call Z_TEXT_RESET
        ld a,255
        call EXTERR
        DEFM "Text source line too long"
        DEFB 0
TEXT_BAD:
        call Z_TEXT_RESET
        ld a,255
        call EXTERR
        DEFM "Bad text source"
        DEFB 0

; Called by platform RESET on lexer, read, Escape and close failures too.
; Clear ACTIVE first so a diagnostic-output failure cannot recurse. Ownership
; remains recorded by FILE_CLOSE when closing fails, for OSCLEAN to retry.
Z_TEXT_RESET:
        ld a,(TEXT_ACTIVE)
        or a
        ret z
        xor a
        ld (TEXT_ACTIVE),a
        call TEXT_CLEAR
        ld a,(TEXT_CHANNEL)
        ld h,a
        call FILE_CLOSE
        call TELL
        DEFM "Text source line "
        DEFB 0
        ld hl,(TEXT_SOURCE_LINE)
        call PBCDL
        jp CRLF

TEXT_CLEAR:
        call LOADFAIL
        ld hl,(PAGE)
        inc hl
        ld (hl),255
        inc hl
        ld (hl),255
        ret
