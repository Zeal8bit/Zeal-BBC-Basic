; BBC raster semantics over a 320x200 ZVB indexed bitmap.
; All persistent pixels are logical colour indices in VRAM. Palette changes
; never rewrite pixels, and POINT and GCOL therefore see the same colours.
        PUBLIC G_TRANSFORM, G_TEXT_PIXEL, G_ABORT, G_SET_ORIGIN
        PUBLIC G_CLEAR, G_COLOUR, G_PLOT, G_POINT, G_RESET, G_WINDOW
        PUBLIC G_ORIGIN, G_FG, G_BG, G_ACTION, G_X, G_Y
        PUBLIC G_LEFT, G_BOTTOM, G_RIGHT, G_TOP
        EXTERN D_BITMAP, D_MASK, D_PARAMS, D_ERROR, D_UNSUPPORTED
        EXTERN G_SPANS
        EXTERN V_READ, V_WRITE, TRAP

G_ACTION: defb 0
G_FG: defb 1
G_BG: defb 0
G_X: defw 0
G_Y: defw 0
G_OLDX: defw 0
G_OLDY: defw 0
G_ORIGIN: defw 0,0
G_LEFT: defw 0
G_BOTTOM: defw 0
G_RIGHT: defw 1279
G_TOP: defw 1023
G_CL: defw 0
G_CT: defw 0
G_CR: defw 319
G_CB: defw 199
G_OP: defb 0
G_INK: defb 0
G_DO: defb 0
G_AX: defw 0
G_AY: defw 0
G_BX: defw 0
G_BY: defw 0
G_CX: defw 0
G_CY: defw 0
G_DX: defw 0
G_DY: defw 0
G_SX: defw 0
G_SY: defw 0
G_ERR: defw 0
G_E2: defw 0
G_DOT: defb 0
G_LAST: defb 0
G_FIRST: defb 0
G_RESET:
        xor a
        ld (G_ACTION),a
        ld (G_BG),a
        ld hl,0
        ld (G_X),hl
        ld (G_Y),hl
        ld (G_OLDX),hl
        ld (G_OLDY),hl
        ld (G_ORIGIN),hl
        ld (G_ORIGIN+2),hl
        ld (G_LEFT),hl
        ld (G_BOTTOM),hl
        ld a,(D_MASK)
        ld (G_FG),a
        ld hl,1279
        ld (G_RIGHT),hl
        ld hl,1023
        ld (G_TOP),hl
        jp G_CLIP_WINDOW
G_COLOUR:
        cp 5
        jp nc,D_ERROR
        ld (G_ACTION),a
        ld a,(D_MASK)
        and e
        bit 7,e
        jp nz,G_BACKGROUND
        ld (G_FG),a
        ret
G_BACKGROUND:
        ld (G_BG),a
        ret
G_REQUIRE:
        ld a,(D_BITMAP)
        or a
        ret nz
        jp D_UNSUPPORTED
 ; Changing the origin moves the coordinate axes, not the existing cursor.
; Rebase both saved logical positions so the next relative draw/triangle
; continues from the same physical screen points.
G_SET_ORIGIN:
        ld hl,(G_ORIGIN)
        ld de,(D_PARAMS)
        or a
        sbc hl,de
        ex de,hl
        ld hl,(G_X)
        add hl,de
        ld (G_X),hl
        ld hl,(G_OLDX)
        add hl,de
        ld (G_OLDX),hl
        ld hl,(G_ORIGIN+2)
        ld de,(D_PARAMS+2)
        or a
        sbc hl,de
        ex de,hl
        ld hl,(G_Y)
        add hl,de
        ld (G_Y),hl
        ld hl,(G_OLDY)
        add hl,de
        ld (G_OLDY),hl
        ld hl,(D_PARAMS)
        ld (G_ORIGIN),hl
        ld hl,(D_PARAMS+2)
        ld (G_ORIGIN+2),hl
        ret
G_WINDOW:
        ld hl,(D_PARAMS)
        ld de,(D_PARAMS+4)
        ex de,hl
        call G_LESS
        jp c,D_ERROR
        ld hl,(D_PARAMS+2)
        ld de,(D_PARAMS+6)
        ex de,hl
        call G_LESS
        jp c,D_ERROR
        ld hl,(D_PARAMS)
        ld (G_LEFT),hl
        ld hl,(D_PARAMS+2)
        ld (G_BOTTOM),hl
        ld hl,(D_PARAMS+4)
        ld (G_RIGHT),hl
        ld hl,(D_PARAMS+6)
        ld (G_TOP),hl
G_CLIP_WINDOW:
        ld hl,(G_LEFT)
        call G_SCALE_X
        ld (G_CL),hl
        ld hl,(G_RIGHT)
        call G_SCALE_X
        ld (G_CR),hl
        ld hl,(G_TOP)
        call G_SCALE_Y
        ld (G_CT),hl
        ld hl,(G_BOTTOM)
        call G_SCALE_Y
        ld (G_CB),hl
        ret
; Signed divide X by four. Y maps the BBC's 256 logical pixel rows to 200.
; Divide by four, then use quotient/remainder for floor(row*25/32).
; This stays in range even for signed coordinates far outside the screen.
G_SCALE_X:
        sra h
        rr l
        sra h
        rr l
        ret
G_SCALE_Y:
        call G_SCALE_X
        ld a,l
        and 31
        ld c,a
        ld b,5
G_YQUOT:
        sra h
        rr l
        djnz G_YQUOT
        call G_TIMES25
        push hl
        ld l,c
        ld h,0
        call G_TIMES25
        ld b,5
G_YDIV:
        srl h
        rr l
        djnz G_YDIV
        pop de
        add hl,de
        ex de,hl
        ld hl,199
        or a
        sbc hl,de
        ret
G_TIMES25:
        ld d,h
        ld e,l
        add hl,hl
        add hl,hl
        add hl,hl
        push hl
        add hl,hl
        add hl,de
        pop de
        add hl,de
        ret
; Transform BBC coordinates DE=x, HL=y (relative to current origin).
G_TRANSFORM:
        push hl
        ld hl,(G_ORIGIN)
        add hl,de
        call G_SCALE_X
        ex de,hl
        pop hl
        push de
        ld de,(G_ORIGIN+2)
        add hl,de
        call G_SCALE_Y
        pop de
        ret
; Read a point without modifying the plot history.
G_POINT:
        call G_REQUIRE
        call G_TRANSFORM
        ld (G_TESTX),de
        call G_ADDRESS
        ld hl,-1
        ret c
        call V_READ
        ld l,a
        ld h,0
        ret
; DE=x and HL=y in physical coordinates -> DE=VRAM offset, carry if clipped.
G_ADDRESS:
        ld (G_TESTX),de
        bit 7,h
        jp nz,G_OUT
        ld a,h
        or a
        jp nz,G_OUT
        ld a,l
        cp 200
        jp nc,G_OUT
        bit 7,d
        jp nz,G_OUT
        push hl
        ld hl,319
        or a
        sbc hl,de
        pop hl
        jp c,G_OUT
        push hl
        ld hl,(G_CL)
        call G_LESS
        pop hl
        jp z,G_ADDR_LEFT_OK
        jp nc,G_OUT
G_ADDR_LEFT_OK:
        push hl
        ld hl,(G_CR)
        call G_LESS
        pop hl
        jp c,G_OUT
        push hl
        ld de,(G_CT)
        call G_LESS
        pop hl
        jp c,G_OUT
        push hl
        ld de,(G_CB)
        ex de,hl
        call G_LESS
        pop hl
        jp c,G_OUT
        ; X was overwritten during Y checks, recover from caller's scratch.
        ld de,(G_TESTX)
        push de
        ld d,h
        ld e,l
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl             ; y*64
        ex de,hl
        ld h,l
        ld l,0                ; y*256
        add hl,de
        pop de
        add hl,de
        ex de,hl
        or a
        ret
G_OUT:  scf
        ret
G_TESTX: defw 0
; Pixel writer at physical DE=x, HL=y, preserving caller registers.
G_TEXT_PIXEL:
        ld a,(G_FG)
        ld (G_INK),a
        ld a,(G_ACTION)
        ld (G_DO),a
        jp G_PIXEL
G_PIXEL:
        push af
        push bc
        push de
        push hl
        ld a,(G_EDGE_FLAG)
        or a
        call nz,G_RECORD
        ld a,(G_EDGE_FLAG)
        or a
        jp nz,G_PIXEL_DONE
        call G_ADDRESS
        jp c,G_PIXEL_DONE
        ld a,(G_DO)
        or a
        jp nz,G_PIXEL_ACTION
        ld a,(G_INK)
        call V_WRITE
        jp G_PIXEL_DONE
G_PIXEL_ACTION:
        cp 4
        jp z,G_INVERT
        push de
        call V_READ
        ld b,a
        ld a,(G_INK)
        ld c,a
        ld a,(G_DO)
        or a
        ld a,c
        jp z,G_STORE
        ld a,(G_DO)
        cp 1
        ld a,c
        jp z,G_OR
        ld a,(G_DO)
        cp 2
        ld a,c
        jp z,G_AND
        xor b
        jp G_STORE
G_OR:   or b
        jp G_STORE
G_AND:  and b
G_STORE:
        ld b,a
        ld a,(D_MASK)
        and b
        pop de
        call V_WRITE
        jp G_PIXEL_DONE
G_INVERT:
        push de
        call V_READ
        ld b,a
        ld a,(D_MASK)
        xor b
        pop de
        call V_WRITE
G_PIXEL_DONE:
        pop hl
        pop de
        pop bc
        pop af
        ret
G_CLEAR:
        call G_REQUIRE
        ld a,(G_BG)
        ld (G_INK),a
        xor a
        ld (G_DO),a
        ld hl,(G_CL)
        ld (G_AX),hl
        ld hl,(G_CT)
        ld (G_AY),hl
        ld hl,(G_CR)
        ld (G_BX),hl
        ld hl,(G_CB)
        ld (G_BY),hl
        jp G_RECT
; PLOT families: 0..63 lines, 64..71 points, 72..79 horizontal fill,
; 80..87 triangles, 96..103 rectangles. Low bits retain BBC meanings.
G_PLOT:
        ld (G_OP),a
        push de
        push hl
        call G_REQUIRE
        ld a,(G_OP)
        cp 88
        jp c,G_VALID_LOW
        cp 96
        jp c,D_UNSUPPORTED
        cp 104
        jp nc,D_UNSUPPORTED
G_VALID_LOW:
        ld a,(G_OP)
        and 0xf8
        cp 88
        jp z,D_UNSUPPORTED
        pop hl
        pop de
        ld a,(G_OP)
        bit 2,a
        jp nz,G_ABSOLUTE
        push hl
        ld hl,(G_X)
        add hl,de
        ex de,hl
        pop hl
        push de
        ld de,(G_Y)
        add hl,de
        pop de
G_ABSOLUTE:
        push de
        push hl
        ld de,(G_OLDX)
        ld hl,(G_OLDY)
        call G_TRANSFORM
        ld (G_CX),de
        ld (G_CY),hl
        ld de,(G_X)
        ld hl,(G_Y)
        ld (G_OLDX),de
        ld (G_OLDY),hl
        call G_TRANSFORM
        ld (G_AX),de
        ld (G_AY),hl
        pop hl
        pop de
        ld (G_X),de
        ld (G_Y),hl
        call G_TRANSFORM
        ld (G_BX),de
        ld (G_BY),hl
        ld a,(G_OP)
        and 3
        ret z                  ; MOVE updates history without drawing
        cp 2
        jp z,G_USE_INVERSE
        cp 3
        ld a,(G_BG)
        jp z,G_USE_INK
        ld a,(G_FG)
G_USE_INK:
        ld (G_INK),a
        ld a,(G_ACTION)
        ld (G_DO),a
        jp G_DISPATCH
G_USE_INVERSE:
        ld a,4
        ld (G_DO),a
G_DISPATCH:
        ld a,(G_OP)
        cp 64
        jp c,G_LINE
        cp 72
        jp nc,G_DISPATCH_FILL
        ld de,(G_BX)
        ld hl,(G_BY)
        jp G_PIXEL
G_DISPATCH_FILL:
        cp 80
        jp c,G_HORIZONTAL_FILL
        cp 88
        jp c,G_TRIANGLE
        jp G_RECT
; Compare signed HL and DE, carry iff HL < DE. Registers preserved.
G_LESS:
        push hl
        push de
        ld a,h
        xor 0x80
        ld h,a
        ld a,d
        xor 0x80
        ld d,a
        or a
        sbc hl,de
        pop de
        pop hl
        ret
; General Bresenham line with signed off-screen endpoints; writes are clipped.
G_LINE:
        ld hl,(G_BX)
        ld de,(G_AX)
        call G_LESS
        ld bc,1
        jp nc,G_LINE_XPOS
        ld bc,-1
        ex de,hl
G_LINE_XPOS:
        ld (G_SX),bc
        or a
        sbc hl,de
        ld (G_DX),hl
        ld hl,(G_BY)
        ld de,(G_AY)
        call G_LESS
        ld bc,1
        jp nc,G_LINE_YPOS
        ld bc,-1
        ex de,hl
G_LINE_YPOS:
        ld (G_SY),bc
        or a
        sbc hl,de
        ex de,hl
        ld hl,0
        sbc hl,de
        ld (G_DY),hl
        ld de,(G_DX)
        add hl,de
        ld (G_ERR),hl
        xor a
        ld (G_DOT),a
        inc a
        ld (G_FIRST),a
G_LINE_LOOP:
        ld hl,(G_AX)
        ld de,(G_BX)
        or a
        sbc hl,de
        ld a,h
        or l
        jp nz,G_NOT_LAST
        ld hl,(G_AY)
        ld de,(G_BY)
        or a
        sbc hl,de
        ld a,h
        or l
G_NOT_LAST:
        ld (G_LAST),a
        ld a,(G_OP)
        bit 3,a
        jp z,G_LINE_DOT
        ld a,(G_LAST)
        or a
        jp z,G_LINE_SKIP
G_LINE_DOT:
        ld a,(G_FIRST)
        or a
        jp z,G_LINE_PATTERN
        ld a,(G_OP)
        bit 5,a
        jp nz,G_LINE_SKIP
G_LINE_PATTERN:
        ld a,(G_OP)
        bit 4,a
        jp z,G_LINE_DRAW
        ld a,(G_DOT)
        and 1
        jp nz,G_LINE_SKIP
G_LINE_DRAW:
        ld de,(G_AX)
        ld hl,(G_AY)
        call G_PIXEL
G_LINE_SKIP:
        xor a
        ld (G_FIRST),a
        ld a,(G_LAST)
        or a
        ret z
        ld a,(G_DOT)
        inc a
        ld (G_DOT),a
        call TRAP
        ld hl,(G_ERR)
        add hl,hl
        ld (G_E2),hl
        ld de,(G_DY)
        call G_LESS
        jp c,G_LINE_ONLY_Y
        ld hl,(G_ERR)
        add hl,de
        ld (G_ERR),hl
        ld hl,(G_AX)
        ld de,(G_SX)
        add hl,de
        ld (G_AX),hl
G_LINE_ONLY_Y:
        ld hl,(G_DX)
        ld de,(G_E2)
        call G_LESS
        jp c,G_LINE_LOOP
        ld hl,(G_ERR)
        ld de,(G_DX)
        add hl,de
        ld (G_ERR),hl
        ld hl,(G_AY)
        ld de,(G_SY)
        add hl,de
        ld (G_AY),hl
        jp G_LINE_LOOP
; Inclusive rectangle, sorted and clamped before looping. Also used by CLG.
G_RECT:
        ld hl,(G_AX)
        ld de,(G_BX)
        call G_SORT
        ld (G_AX),hl
        ld (G_BX),de
        ld hl,(G_AY)
        ld de,(G_BY)
        call G_SORT
        ld (G_AY),hl
        ld (G_BY),de
        ; Clip spans before iterating, including extreme signed coordinates.
        ld hl,(G_AX)
        ld de,0
        call G_MAX
        ld de,(G_CL)
        call G_MAX
        ld (G_AX),hl
        ld hl,(G_BX)
        ld de,319
        call G_MIN
        ld de,(G_CR)
        call G_MIN
        ld (G_BX),hl
        ld hl,(G_AY)
        ld de,0
        call G_MAX
        ld de,(G_CT)
        call G_MAX
        ld (G_AY),hl
        ld hl,(G_BY)
        ld de,199
        call G_MIN
        ld de,(G_CB)
        call G_MIN
        ld (G_BY),hl
        ld hl,(G_BX)
        ld de,(G_AX)
        call G_LESS
        ret c
G_RECT_ROW:
        ld hl,(G_AY)
        ld de,(G_BY)
        call G_LESS
        jp c,G_RECT_RUN
        or a
        sbc hl,de
        ret nz
G_RECT_RUN:
        ld hl,(G_AX)
        ld (G_RX),hl
G_RECT_COL:
        ld de,(G_RX)
        ld hl,(G_AY)
        call G_PIXEL
        ld hl,(G_RX)
        ld de,(G_BX)
        or a
        sbc hl,de
        jp z,G_RECT_NEXT
        ld hl,(G_RX)
        inc hl
        ld (G_RX),hl
        jp G_RECT_COL
G_RECT_NEXT:
        call TRAP
        ld hl,(G_AY)
        inc hl
        ld (G_AY),hl
        jp G_RECT_ROW
G_RX: defw 0
G_MAX:  call G_LESS
        ret nc
        ex de,hl
        ret
G_MIN:  call G_LESS
        ret c
        ex de,hl
        ret
G_SORT: call G_LESS
        ret c
        ex de,hl
        ret
; Horizontal fill: extend left/right through non-foreground pixels, stopping
; at foreground or the graphics window. Family 72 is bounded by foreground.
G_HORIZONTAL_FILL:
        ld de,(G_BX)
        ld (G_TESTX),de
        ld hl,(G_BY)
        call G_ADDRESS
        ret c
        call V_READ
        ld b,a
        ld a,(G_FG)
        cp b
        ret z
        ld hl,(G_BX)
        ld (G_AX),hl
G_FILL_LEFT:
        ld de,(G_AX)
        dec de
        ld (G_TESTX),de
        ld hl,(G_BY)
        call G_ADDRESS
        jp c,G_FILL_RIGHT
        call V_READ
        ld b,a
        ld a,(G_FG)
        cp b
        jp z,G_FILL_RIGHT
        ld hl,(G_AX)
        dec hl
        ld (G_AX),hl
        jp G_FILL_LEFT
G_FILL_RIGHT:
        ld de,(G_BX)
        inc de
        ld (G_TESTX),de
        ld hl,(G_BY)
        call G_ADDRESS
        jp c,G_FILL_DRAW
        call V_READ
        ld b,a
        ld a,(G_FG)
        cp b
        jp z,G_FILL_DRAW
        ld hl,(G_BX)
        inc hl
        ld (G_BX),hl
        jp G_FILL_RIGHT
G_FILL_DRAW:
        ld hl,(G_BY)
        ld (G_AY),hl
        jp G_RECT
; Triangle scan conversion: walk each edge once with Bresenham, recording
; min/max X for each visible scanline, then fill each span exactly once.
; This avoids double-writing shared edges under XOR.
G_TRIANGLE:
        ld hl,G_SPANS
        ld b,200
G_TRI_INIT:
        ld (hl),0xff
        inc hl
        ld (hl),0x7f
        inc hl
        ld (hl),0
        inc hl
        ld (hl),0x80
        inc hl
        djnz G_TRI_INIT
        ld hl,(G_AX)
        ld (G_TAX),hl
        ld hl,(G_AY)
        ld (G_TAY),hl
        ld hl,(G_BX)
        ld (G_TBX),hl
        ld hl,(G_BY)
        ld (G_TBY),hl
        call G_EDGE
        ld hl,(G_TBX)
        ld (G_AX),hl
        ld hl,(G_TBY)
        ld (G_AY),hl
        ld hl,(G_CX)
        ld (G_BX),hl
        ld hl,(G_CY)
        ld (G_BY),hl
        call G_EDGE
        ld hl,(G_CX)
        ld (G_AX),hl
        ld hl,(G_CY)
        ld (G_AY),hl
        ld hl,(G_TAX)
        ld (G_BX),hl
        ld hl,(G_TAY)
        ld (G_BY),hl
        call G_EDGE
        ld hl,0
        ld (G_TY),hl
G_TRI_ROW:
        ld hl,(G_TY)
        add hl,hl
        add hl,hl
        ld de,G_SPANS
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ex de,hl
        call G_LESS
        jp c,G_TRI_SPAN
        push hl
        or a
        sbc hl,de
        pop hl
        jp nz,G_TRI_NEXT
G_TRI_SPAN:
        ld (G_AX),hl
        ld (G_BX),de
        ld hl,(G_TY)
        ld (G_AY),hl
        ld (G_BY),hl
        call G_RECT
G_TRI_NEXT:
        ld hl,(G_TY)
        inc hl
        ld (G_TY),hl
        ld a,l
        cp 200
        jp c,G_TRI_ROW
        ret
G_TAX: defw 0
G_TAY: defw 0
G_TBX: defw 0
G_TBY: defw 0
G_TY: defw 0
G_EDGE:
        ; Reuse line stepping with a private edge flag; G_PIXEL records spans.
        ld a,1
        ld (G_EDGE_FLAG),a
        ld a,(G_OP)
        push af
        xor a
        ld (G_OP),a
        call G_LINE
        pop af
        ld (G_OP),a
        xor a
        ld (G_EDGE_FLAG),a
        ret
G_ABORT:
        xor a
        ld (G_EDGE_FLAG),a
        ret
G_EDGE_FLAG: defb 0
G_RECORD:
        ld a,h
        or a
        ret nz
        ld a,l
        cp 200
        ret nc
        push de
        add hl,hl
        add hl,hl
        ld de,G_SPANS
        add hl,de
        pop de
        push hl
        ld c,(hl)
        inc hl
        ld b,(hl)
        ld h,b
        ld l,c
        call G_LESS
        pop hl
        jp c,G_RECORD_MAX
        ld (hl),e
        inc hl
        ld (hl),d
        dec hl
G_RECORD_MAX:
        inc hl
        inc hl
        push hl
        ld c,(hl)
        inc hl
        ld b,(hl)
        ld h,b
        ld l,c
        call G_LESS
        pop hl
        ret nc
        ld (hl),e
        inc hl
        ld (hl),d
        ret
