; Copyright (c) 2020 J.B. Langston
;
; This software is provided 'as-is', without any express or implied
; warranty. In no event will the authors be held liable for any damages
; arising from the use of this software.
;
; Permission is granted to anyone to use this software for any purpose,
; including commercial applications, and to alter it and redistribute it
; freely, subject to the following restrictions:
;
; 1. The origin of this software must not be misrepresented; you must not
;    claim that you wrote the original software. If you use this software
;    in a product, an acknowledgment in the product documentation would be
;    appreciated but is not required.
; 2. Altered source versions must be plainly marked as such, and must not be
;    misrepresented as being the original software.
; 3. This notice may not be removed or altered from any source distribution.

; Zeal BBC display command adapters. BBC semantics live in display/graphics,
; not in the interpreter or the ZVB register interface.
        INCLUDE "zos_syscall.asm"
        INCLUDE "zos_video.asm"
        PUBLIC CLG, COLOUR, DRAW, ENVEL, GCOL, MODE, MOVE, PLOT
        PUBLIC SOUND, ADVAL, POINT, GETIMS, PUTIMS
        PUBLIC CLRSCN, PUTCSR, GETCSR, PUTIME, GETIME
        EXTERN EXPRI, COMMA, BRAKET, XEQ, EXTERR
        EXTERN D_CLEAR, D_SETCURSOR, D_GETCURSOR, D_MODE, D_COLOUR, D_ERROR
        EXTERN G_CLEAR, G_COLOUR, G_PLOT, G_POINT

CLRSCN: jp D_CLEAR
PUTCSR: jp D_SETCURSOR
GETCSR: jp D_GETCURSOR
GETIME: ld de,0
        ld hl,0
        ret
PUTIME: ret
COLOUR: call BYTE_ARG
        call D_COLOUR
        jp XEQ
MODE:   call BYTE_ARG
        call D_MODE
        jp XEQ
GCOL:   call BYTE_ARG
        push af
        call COMMA
        call BYTE_ARG
        ld e,a
        pop af
        call G_COLOUR
        jp XEQ
CLG:    call G_CLEAR
        jp XEQ
MOVE:   ld a,4
        jr XY_COMMAND
DRAW:   ld a,5
        jr XY_COMMAND
PLOT:   call BYTE_ARG
        push af
        call COMMA
        pop af
XY_COMMAND:
        push af
        call XY_ARGS
        pop af
        call G_PLOT
        jp XEQ
; BASIC byte arguments must not silently wrap into a different mode/action.
BYTE_ARG:
        call EXPRI
        ld a,h
        or l
        jp nz,D_ERROR
        exx
        ld a,h
        or a
        jp nz,D_ERROR
        ld a,l
        ret
; Return DE=x, HL=y. EXPRI returns its integer in the alternate bank.
XY_ARGS:
        call EXPRI
        exx
        push hl
        call COMMA
        call EXPRI
        exx
        pop de
        ret
POINT:  call XY_ARGS
        push de
        push hl
        call BRAKET
        pop hl
        pop de
        call G_POINT           ; HL=colour, or -1 outside graphics window
        ld a,h
        exx
        ld hl,0
        bit 7,a
        jr z,POINT_POSITIVE
        dec hl
POINT_POSITIVE:
        xor a
        ld c,a
        ret
ENVEL:
SOUND:
ADVAL:
GETIMS:
PUTIMS:
        xor a
        call EXTERR
        defm "Not implemented"
        defb 0

        PUBLIC V_READ, V_WRITE, V_SPAN, D_VREAD, D_VWRITE, VIDEO_ACCESS_END
; Temporary video mapping in virtual page 2. These helpers and the private
; IRQ wrappers must stay below &8000 (checked by the build). The kernel ROM,
; stack and vectors remain mapped, so interrupts remain enabled while drawing.
; No OS call or access to upper BASIC code/workspace occurs before restoration.
; DE=16-bit address within pixel storage (physical &110000).
V_READ:
        push bc
        push hl
        ld a,0x80
        in a,(0xf0)
        ld c,a
        ld a,d
        rlca
        rlca
        and 3
        add a,0x44
        out (0xf2),a
        ld a,d
        and 0x3f
        or 0x80
        ld h,a
        ld l,e
        ld b,(hl)
        jp V_RETURN
V_WRITE:
        push bc
        ld b,a
        push hl
        ld a,0x80
        in a,(0xf0)
        ld c,a
        ld a,d
        rlca
        rlca
        and 3
        add a,0x44
        out (0xf2),a
        ld a,d
        and 0x3f
        or 0x80
        ld h,a
        ld l,e
        ld (hl),b
V_RETURN:
        ld a,c
        out (0xf2),a
        ld a,b
        pop hl
        pop bc
        ret
; Fill BC pixels from DE with A, in chunks that never cross a mapping
; boundary. Interrupts can run throughout; poll for Escape between scanlines.
V_SPAN:
        ld (V_SPAN_INK),a
V_SPAN_NEXT:
        ld a,b
        or c
        ret z
        push bc
        push de
        ld a,0x80
        in a,(0xf0)
        ld (V_SPAN_PAGE),a
        ld a,d
        rlca
        rlca
        and 3
        add a,0x44
        out (0xf2),a
        ld a,d
        and 0x3f
        or 0x80
        ld h,a
        ld l,e
        ld a,64
        sub e
        and 63
        jp nz,V_SPAN_BOUND
        ld a,64
V_SPAN_BOUND:
        ld d,a
        ld a,b
        or a
        ld a,d
        jp nz,V_SPAN_COUNT
        cp c
        jp c,V_SPAN_COUNT
        ld a,c
V_SPAN_COUNT:
        ld (V_SPAN_COUNTED),a
        ld b,a
        ld a,(V_SPAN_INK)
V_SPAN_LOOP:
        ld (hl),a
        inc hl
        djnz V_SPAN_LOOP
        ld a,(V_SPAN_PAGE)
        out (0xf2),a
        pop de
        pop bc
        ld a,(V_SPAN_COUNTED)
        ld l,a
        ld h,0
        add hl,de
        ex de,hl
        ld a,(V_SPAN_COUNTED)
        ld l,a
        ld h,0
        push de
        ld d,b
        ld e,c
        ex de,hl
        or a
        sbc hl,de
        ld b,h
        ld c,l
        pop de
        jp V_SPAN_NEXT
V_SPAN_INK: defb 0
V_SPAN_PAGE: defb 0
V_SPAN_COUNTED: defb 0
; VRAM control/font access at physical 0x100000, protected like pixels.
D_VREAD:
        push bc
        push hl
        ld a,0x80
        in a,(0xf0)
        ld c,a
        ld a,0x40
        out (0xf2),a
        ld a,d
        or 0x80
        ld h,a
        ld l,e
        ld b,(hl)
        jp V_RETURN
D_VWRITE:
        push bc
        ld b,a
        push hl
        ld a,0x80
        in a,(0xf0)
        ld c,a
        ld a,0x40
        out (0xf2),a
        ld a,d
        or 0x80
        ld h,a
        ld l,e
        ld (hl),b
        jp V_RETURN
VIDEO_ACCESS_END:
