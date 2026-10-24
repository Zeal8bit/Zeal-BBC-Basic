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
        PUBLIC CLRSCN, PUTCSR, GETCSR
        EXTERN EXPRI, COMMA, BRAKET, XEQ, EXTERR
        EXTERN D_CLEAR, D_SETCURSOR, D_GETCURSOR, D_MODE, D_COLOUR, D_ERROR
        EXTERN G_CLEAR, G_COLOUR, G_PLOT, G_POINT
        EXTERN Z_KIND, Z_MAX_X, Z_NORMALIZE_COLOUR

; Link the original interpreter hooks directly to the Zeal implementations.
DEFC CLRSCN = D_CLEAR
DEFC PUTCSR = D_SETCURSOR
DEFC GETCSR = D_GETCURSOR
COLOUR: call COLOUR_ARG
        call D_COLOUR
        jp XEQ
MODE:   call BYTE_ARG
        call D_MODE
        jp XEQ
GCOL:   call BYTE_ARG
        push af
        call COMMA
        call COLOUR_ARG
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
; Custom Zeal modes use a ninth colour bit for background selection.
; Native BBC text selectors retain the conventional colour+128 syntax.
COLOUR_ARG:
        call EXPRI
        ld a,h
        or l
        jp nz,D_ERROR
        exx
        ld a,h
        cp 2
        jp nc,D_ERROR
        ld e,l
        ld d,h
        jp Z_NORMALIZE_COLOUR
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

        PUBLIC V_READ, V_WRITE, V_SPAN, V_PAINT, V_ADDRESS, V_TEXT_ADDRESS
        PUBLIC D_VREAD, D_VWRITE, VIDEO_ACCESS_END
; Map virtual page 2 only while running below &8000. No OS calls or runtime
; workspace accesses are permitted until its original mapping is restored.
; The private IRQ wrappers also stay below &8000; interrupts remain enabled.
V_READ:
        push bc
        push hl
        call V_MAP
        ld b,(hl)
        jr V_RETURN
V_WRITE:
        push bc
        ld b,a
        push hl
        call V_MAP
        ld (hl),b
V_RETURN:
        ld a,c
        out (0xf2),a
        ld a,b
        pop hl
        pop bc
        ret
; DE=offset in pixel storage. Return HL=mapped pointer, C=original page.
V_MAP:
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
        ret
; DE=VRAM offset, BC=count, A=ink. V_PAINT also takes L=0/1/2/3 for
; replace/OR/AND/XOR. Work in <=64-byte chunks that cannot cross MMU pages.
; Only the two bytes below are accessed while mapped; keep them below &8000.
V_SPAN:
        ld l,0
V_PAINT:
        ld (V_SPAN_INK),a
        ld a,l
        ld (V_SPAN_OP),a
V_SPAN_NEXT:
        ld a,b
        or c
        ret z
        push bc
        push de
        ld a,64
        sub e
        and 63
        jr nz,V_SPAN_BOUND
        ld a,64
V_SPAN_BOUND:
        ld h,a
        ld a,b
        or a
        ld a,h
        jr nz,V_SPAN_COUNT
        cp c
        jr c,V_SPAN_COUNT
        ld a,c
V_SPAN_COUNT:
        ld b,a
        call V_MAP
        ld e,b                 ; count survives the pixel loop
        ld a,(V_SPAN_OP)
        or a
        jr z,V_SPAN_REPLACE
        dec a
        jr z,V_SPAN_OR
        dec a
        jr z,V_SPAN_AND
V_SPAN_XOR:
        ld a,(V_SPAN_INK)
        xor (hl)
        ld (hl),a
        inc hl
        djnz V_SPAN_XOR
        jr V_SPAN_RESTORE
V_SPAN_AND:
        ld a,(V_SPAN_INK)
        and (hl)
        ld (hl),a
        inc hl
        djnz V_SPAN_AND
        jr V_SPAN_RESTORE
V_SPAN_OR:
        ld a,(V_SPAN_INK)
        or (hl)
        ld (hl),a
        inc hl
        djnz V_SPAN_OR
        jr V_SPAN_RESTORE
V_SPAN_REPLACE:
        ld a,(V_SPAN_INK)
V_SPAN_LOOP:
        ld (hl),a
        inc hl
        djnz V_SPAN_LOOP
V_SPAN_RESTORE:
        ld a,c
        out (0xf2),a
        ld a,e
        pop de
        pop bc
        ld l,a
        ld h,0
        add hl,de
        ex de,hl
        ld h,a
        ld a,c
        sub h
        ld c,a
        ld a,b
        sbc a,0
        ld b,a
        jr V_SPAN_NEXT
V_SPAN_INK: defb 0
V_SPAN_OP: defb 0
; VRAM control/font access at physical &100000.
D_VREAD:
        push bc
        push hl
        call D_VMAP
        ld b,(hl)
        jp V_RETURN
D_VWRITE:
        push bc
        ld b,a
        push hl
        call D_VMAP
        ld (hl),b
        jp V_RETURN
D_VMAP:
        ld a,0x80
        in a,(0xf0)
        ld c,a
        ld a,0x40
        out (0xf2),a
        ld a,d
        or 0x80
        ld h,a
        ld l,e
        ret
VIDEO_ACCESS_END:
; Shared address arithmetic, DE=x and HL=y. Carry is clear on return.
V_ADDRESS:
        push de
        ld a,(Z_MAX_X+1)
        or a
        jr z,V_ADDRESS_256
        ld d,h
        ld e,l
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ex de,hl
        ld h,l
        ld l,0
        jr V_ADDRESS_ADD
V_TEXT_ADDRESS:
        push de
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld d,h
        ld e,l
        add hl,hl
        add hl,hl
V_ADDRESS_ADD:
        add hl,de
V_ADDRESS_X:
        pop de
        add hl,de
        ex de,hl
        or a
        ret
V_ADDRESS_256:
        ld h,l
        ld l,0
        jr V_ADDRESS_X
