; BBC logical raster operations over native Zeal indexed bitmaps.
; All persistent pixels are logical colour indices in VRAM. Palette changes
; never rewrite pixels, and POINT and GCOL therefore see the same colours.
        EXTERN G_ACTION, G_FG, G_BG, G_X, G_Y, G_OLDX
        EXTERN G_OLDY, G_ORIGIN, G_LEFT, G_BOTTOM, G_RIGHT, G_TOP
        EXTERN G_CL, G_CT, G_CR, G_CB, G_OP, G_INK
        EXTERN G_DO, G_AX, G_AY, G_BX, G_BY, G_CX
        EXTERN G_CY, G_DX, G_DY, G_SX, G_SY, G_ERR
        EXTERN G_MAJOR, G_DOT, G_FIRST, G_TY
        PUBLIC G_TRANSFORM, G_TEXT_PIXEL, G_TEXT_ERASE_PIXEL, G_ABORT, G_SET_ORIGIN
        PUBLIC G_CLEAR, G_COLOUR, G_PLOT, G_POINT, G_RESET, G_WINDOW
        EXTERN D_BITMAP, D_MASK, D_PARAMS, D_ERROR, D_UNSUPPORTED
        EXTERN G_SPANS
        EXTERN D_MODE_NO, Z_MAX_X, Z_MAX_Y
        EXTERN V_READ, V_PAINT, V_ADDRESS, TRAP

G_RESET:
        xor a
        ld (G_ACTION),a
        ld (G_BG),a
        ld hl,G_X
        ld de,G_X+1
        ld bc,G_RIGHT-G_X-1
        ld (hl),a
        ldir                   ; X/Y, history, origin and window minimums
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
        bit 0,d
        jr nz,G_BACKGROUND
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
        ld hl,D_PARAMS
        ld de,G_LEFT
        ld bc,8
        ldir
G_CLIP_WINDOW:
        ld hl,(G_LEFT)
        call G_SCALE_X
        ld de,0
        call G_MAX
        ld (G_CL),hl
        ld hl,(G_RIGHT)
        call G_SCALE_X
        ld de,(Z_MAX_X)
        call G_MIN
        ld (G_CR),hl
        ld hl,(G_TOP)
        call G_SCALE_Y
        ld de,0
        call G_MAX
        ld (G_CT),hl
        ld hl,(G_BOTTOM)
        call G_SCALE_Y
        ld de,(Z_MAX_Y)
        call G_MIN
        ld (G_CB),hl
        ret
; BBC logical coordinates: X divides by 4 or 5 for 320/256 pixels.
; Y maps the BBC's 256 logical pixel rows to 200 or 240 native rows.
; This stays in range even for signed coordinates far outside the screen.
G_SCALE_X:
        ld a,(D_MODE_NO)
        cp 9
        jr z,G_DIV5
G_DIV4:
        sra h
        rr l
        sra h
        rr l
        ret
G_DIV5:
        bit 7,h
        jr z,G_UDIV5
        ex de,hl
        ld hl,4
        or a
        sbc hl,de              ; ceil(abs(x)/5), including -32768
        call G_UDIV5
        ex de,hl
        ld hl,0
        or a
        sbc hl,de
        ret
G_UDIV5:
        ld e,0
        ld b,16
G_DIV5_BIT:
        add hl,hl
        rl e
        ld a,e
        cp 5
        jr c,G_DIV5_NEXT
        sub 5
        ld e,a
        inc l
G_DIV5_NEXT:
        djnz G_DIV5_BIT
        ret
G_SCALE_Y:
        call G_DIV4
        ld a,(D_MODE_NO)
        cp 9
        jr nz,G_SCALE_Y_200
        push hl
        ld de,15
        add hl,de
        ld b,4
G_SCALE_Y_240_DIV:
        sra h
        rr l
        djnz G_SCALE_Y_240_DIV
        ex de,hl
        pop hl
        or a
        sbc hl,de              ; row - ceil(row/16) = floor(row*15/16)
        jr G_Y_SCALED
G_SCALE_Y_200:
        ; Signed 24-bit product A:HL = row * 25. Keeping the sign byte avoids
        ; splitting row into a quotient and remainder for the final /32.
        ld a,h
        rla
        sbc a,a
        ld b,a
        ld d,h
        ld e,l
        add hl,hl
        rla
        add hl,hl
        rla
        add hl,hl
        rla                    ; row * 8
        push af
        push hl
        add hl,hl
        rla                    ; row * 16
        add hl,de
        adc a,b                ; row * 17
        pop de
        pop bc
        add hl,de
        adc a,b                ; row * 25
        ld b,5
G_YDIV:
        sra a
        rr h
        rr l
        djnz G_YDIV
G_Y_SCALED:
        ex de,hl
        ld hl,(Z_MAX_Y)
        or a
        sbc hl,de
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
        call G_ADDRESS
        ld hl,-1
        ret c
        call V_READ
        ld l,a
        ld h,0
        ret
; DE=x and HL=y in physical coordinates -> DE=VRAM offset, carry if clipped.
G_ADDRESS:
        ; Cached bounds are intersected with the physical screen. An empty
        ; intersection remains inverted, so these comparisons also reject it.
        push hl
        ex de,hl
        ld de,(G_CL)
        call G_LESS
        jr c,G_X_OUT
        ld de,(G_CR)
        ex de,hl
        call G_LESS
        pop hl
        jr c,G_OUT
        push de
        ld de,(G_CT)
        call G_LESS
        jr c,G_Y_OUT
        ld de,(G_CB)
        ex de,hl
        call G_LESS
        ex de,hl
        pop de
        jr c,G_OUT
        jp V_ADDRESS
G_X_OUT:
        pop hl
        scf
        ret
G_Y_OUT:
        pop de
G_OUT:  scf
        ret
; Pixel writer at physical DE=x, HL=y, preserving caller registers.
G_TEXT_ERASE_PIXEL:
        ld a,(G_BG)
        ld (G_INK),a
        xor a                  ; deletion replaces with background, regardless of GCOL
        jr G_TEXT_ACTION
G_TEXT_PIXEL:
        ld a,(G_FG)
        ld (G_INK),a
        ld a,(G_ACTION)
G_TEXT_ACTION:
        ld (G_DO),a
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
        jr nz,G_PIXEL_DONE
        call G_ADDRESS
        jr c,G_PIXEL_DONE
        ld bc,1
        call G_PAINT
G_PIXEL_DONE:
        pop hl
        pop de
        pop bc
        pop af
        ret
; The span writer implements all colour actions. Inversion is XOR with the
; current logical colour mask, so no read/modify/write implementation is duplicated.
G_PAINT:
        ld a,(G_DO)
        cp 4
        ld l,a
        ld a,(G_INK)
        jp nz,V_PAINT
        ld l,3
        ld a,(D_MASK)
        jp V_PAINT
G_CLEAR:
        call G_REQUIRE
        ld a,(G_BG)
        ld (G_INK),a
        xor a
        ld (G_DO),a
        ld hl,G_CL
        ld de,G_AX
        ld bc,8
        ldir                   ; cached rectangle and plot rectangle share X/Y order
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
        jr c,G_VALID_LOW
        cp 96
        jp c,D_UNSUPPORTED
        cp 104
        jp nc,D_UNSUPPORTED
G_VALID_LOW:
        pop hl
        pop de
        ld a,(G_OP)
        bit 2,a
        jr nz,G_ABSOLUTE
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
        jr z,G_USE_INVERSE
        cp 3
        ld a,(G_BG)
        jr z,G_USE_INK
        ld a,(G_FG)
G_USE_INK:
        ld (G_INK),a
        ld a,(G_ACTION)
        ld (G_DO),a
        jr G_DISPATCH
G_USE_INVERSE:
        ld a,4
        ld (G_DO),a
G_DISPATCH:
        ld a,(G_OP)
        cp 64
        jr c,G_LINE
        cp 72
        jr nc,G_DISPATCH_FILL
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
; Major-axis Bresenham. Physical endpoints fit signed 14 bits, but doubling
; the old signed error could overflow. This accumulator stays within the major
; delta; carry from subtraction selects the minor step. DE/HL hold X/Y and BC
; counts remaining steps. G_PIXEL and TRAP preserve all three register pairs.
G_LINE:
        ld hl,(G_BX)
        ld de,(G_AX)
        call G_DELTA
        ld (G_SX),bc
        ld (G_DX),hl
        ld hl,(G_BY)
        ld de,(G_AY)
        call G_DELTA
        ld (G_SY),bc
        ex de,hl
        ld hl,(G_DX)
        call G_LESS
        ld a,0
        jr nc,G_LINE_MAJOR
        ex de,hl
        inc a
G_LINE_MAJOR:
        ld (G_MAJOR),a
        ld (G_DX),hl           ; major delta
        ld (G_DY),de           ; minor delta
        ld b,h
        ld c,l
        dec hl                 ; ties step the minor axis, like BBC lines
        srl h
        rr l
        ld (G_ERR),hl
        xor a
        ld (G_DOT),a
        inc a
        ld (G_FIRST),a
        ld de,(G_AX)
        ld hl,(G_AY)
G_LINE_LOOP:
        ld a,(G_OP)
        bit 3,a
        jr z,G_LINE_DOT
        ld a,b
        or c
        jr z,G_LINE_SKIP
G_LINE_DOT:
        ld a,(G_FIRST)
        or a
        jr z,G_LINE_PATTERN
        ld a,(G_OP)
        bit 5,a
        jr nz,G_LINE_SKIP
G_LINE_PATTERN:
        ld a,(G_OP)
        bit 4,a
        jr z,G_LINE_DRAW
        ld a,(G_DOT)
        and 1
        jr nz,G_LINE_SKIP
G_LINE_DRAW:
        call G_PIXEL
G_LINE_SKIP:
        ld a,b
        or c
        ret z
        xor a
        ld (G_FIRST),a
        ld a,(G_DOT)
        inc a
        ld (G_DOT),a
        call TRAP
        push hl
        push de
        ld hl,(G_ERR)
        ld de,(G_DY)
        or a
        sbc hl,de
        jr nc,G_LINE_ERROR
        ld de,(G_DX)
        add hl,de              ; wrap restores the error and leaves carry set
G_LINE_ERROR:
        ld (G_ERR),hl
        pop de
        pop hl
        call c,G_STEP_MINOR
        call G_STEP_MAJOR
        dec bc
        jr G_LINE_LOOP
G_DELTA:
        call G_LESS
        ld bc,1
        jr nc,G_DELTA_POSITIVE
        ld bc,-1
        ex de,hl
G_DELTA_POSITIVE:
        or a
        sbc hl,de
        ret
G_STEP_MINOR:
        ld a,(G_MAJOR)
        xor 1
        jr G_STEP_AXIS
G_STEP_MAJOR:
        ld a,(G_MAJOR)
G_STEP_AXIS:
        or a
        jr nz,G_STEP_Y
        push hl
        ld hl,(G_SX)
        add hl,de
        ex de,hl
        pop hl
        ret
G_STEP_Y:
        push de
        ld de,(G_SY)
        add hl,de
        pop de
        ret
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
        ld de,(G_CL)
        call G_MAX
        ld (G_AX),hl
        ld hl,(G_BX)
        ld de,(G_CR)
        call G_MIN
        ld (G_BX),hl
        ld hl,(G_AY)
        ld de,(G_CT)
        call G_MAX
        ld (G_AY),hl
        ld hl,(G_BY)
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
        jr c,G_RECT_RUN
        or a
        sbc hl,de
        ret nz
G_RECT_RUN:
        ld de,(G_AX)
        ld hl,(G_AY)
        call V_ADDRESS
        push de
        ld hl,(G_BX)
        ld de,(G_AX)
        or a
        sbc hl,de
        inc hl
        ld b,h
        ld c,l
        pop de
        call G_PAINT
G_RECT_NEXT:
        call TRAP
        ld hl,(G_AY)
        inc hl
        ld (G_AY),hl
        jr G_RECT_ROW
G_MAX:  call G_LESS
        ret nc
        ex de,hl
        ret
G_MIN:
G_SORT: call G_LESS
        ret c
        ex de,hl
        ret
; PLOT family 72 fills background pixels, stopping at any other colour.
G_HORIZONTAL_FILL:
        ld de,(G_BX)
        ld hl,(G_BY)
        call G_ADDRESS
        ret c
        call V_READ
        ld hl,G_BG
        cp (hl)
        ret nz
        push de                ; seed address, restored for the rightward scan
        ld bc,(G_BX)
G_FILL_LEFT:
        ld hl,(G_CL)
        or a
        sbc hl,bc
        jr z,G_FILL_LEFT_END
        dec bc
        dec de
        call V_READ
        ld hl,G_BG
        cp (hl)
        jr z,G_FILL_LEFT
        inc bc                 ; exclude the non-background boundary pixel
G_FILL_LEFT_END:
        ld (G_AX),bc
        pop de
        ld bc,(G_BX)
G_FILL_RIGHT:
        ld hl,(G_CR)
        or a
        sbc hl,bc
        jr z,G_FILL_RIGHT_END
        inc bc
        inc de
        call V_READ
        ld hl,G_BG
        cp (hl)
        jr z,G_FILL_RIGHT
        dec bc
G_FILL_RIGHT_END:
        ld (G_BX),bc
        ld hl,(G_BY)
        ld (G_AY),hl
        jp G_RECT
; Triangle scan conversion: walk each edge once with Bresenham, recording
; min/max X for each visible scanline, then fill each span exactly once.
; This avoids double-writing shared edges under XOR.
G_TRIANGLE:
        ld hl,G_SPANS
        ld b,240
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
        ld b,3
G_TRI_EDGE:
        push bc
        call G_EDGE
        ; Line stepping now leaves its endpoints intact. Rotate A/B/C after
        ; each edge, so AB, BC and CA share one loop and no saved vertices.
        ld hl,(G_AX)
        push hl
        ld hl,(G_AY)
        push hl
        ld hl,G_BX
        ld de,G_AX
        ld bc,8
        ldir
        pop hl
        ld (G_CY),hl
        pop hl
        ld (G_CX),hl
        pop bc
        djnz G_TRI_EDGE
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
        jr c,G_TRI_SPAN
        push hl
        or a
        sbc hl,de
        pop hl
        jr nz,G_TRI_NEXT
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
        cp 240
        jr c,G_TRI_ROW
        ret
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
        cp 240
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
        jr c,G_RECORD_MAX
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
