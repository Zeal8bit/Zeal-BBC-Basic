; BBC VDU state and ZVB backend. Native startup output remains an OS stream.
; After MODE, this module owns cursor, windows, scrolling and input echo.
        EXTERN D_CHAR, D_GX, D_GY
        EXTERN D_BITS, D_FILL, D_L, D_T, D_R, D_B
        EXTERN D_CY, D_SCROLL_H
        EXTERN D_SCROLL_DEST
        EXTERN D_MODE, D_MODE_NO, D_MASK, D_COLS, D_ROWS
        EXTERN Z_KIND, Z_MAX_X, Z_MAX_Y, Z_PALETTE, Z_NORMALIZE_COLOUR, Z_NATIVE_STATE
        EXTERN Z_PALETTE_ADDRESS, Z_TEXT_CELL, Z_TEXT_COLOURS, Z_BBC_COLOUR, Z_TILE_FONT
        PUBLIC D_SAVE, D_WINDOWS, D_DEFAULT_COLOURS, D_LOAD_GLYPH, D_PAL_WORD
        INCLUDE "zos_syscall.asm"
        INCLUDE "zos_video.asm"
        PUBLIC D_BYTE, D_CLEAR, D_SETCURSOR, D_GETCURSOR, D_COLOUR
        PUBLIC D_BITMAP, D_ACTIVE, D_X, D_FG, D_BG, D_ERROR, D_UNSUPPORTED
        EXTERN V_READ, V_WRITE, V_SPAN, D_VREAD, D_VWRITE
        EXTERN V_ADDRESS, V_TEXT_ADDRESS
        PUBLIC D_RESET_SEQUENCE, D_EXIT, D_FILL_RECT
        EXTERN ZOS_SYSCALL, RAW_WRCH, EXTERR, TRAP
        EXTERN G_CLEAR, G_COLOUR, G_PLOT, G_RESET, G_WINDOW, G_SET_ORIGIN
        EXTERN G_X, G_Y, G_ACTION, G_FG, G_BG
        EXTERN G_TRANSFORM, G_TEXT_PIXEL, G_TEXT_ERASE_PIXEL, G_ABORT
D_ACTIVE: defb 0
D_BITMAP: defb 0
D_X: defb 0
D_Y: defb 0
; Keep the VDU 28 parameter order for validation/copy and rectangle expansion.
D_LEFT: defb 0
D_BOTTOM: defb 39
D_RIGHT: defb 79
D_TOP: defb 0
D_FG: defb 7
D_BG: defb 0
D_DISABLED: defb 0
D_GRAPH_TEXT: defb 0
D_SAVED: defb 0
D_PENDING: defb 0
D_COMMAND: defb 0
        EXTERN D_NEXT_PARAM
        EXTERN D_PARAMS, D_GLYPH, D_CURSOR, D_ORIGINAL_FONT
D_ERROR:
        ld a,255
        call EXTERR
        defm "Bad display parameter"
        defb 0
D_UNSUPPORTED:
        ld a,255
        call EXTERR
        defm "Unsupported display operation"
        defb 0
D_RESET_SEQUENCE:
        xor a
        ld (D_PENDING),a
        ld (D_DISABLED),a
        ld (D_GRAPH_TEXT),a
        jp G_ABORT
; OSWRCH wraps this entry to preserve main registers; no alternate bank use.
D_BYTE:
        ld b,a
        ld hl,D_PENDING
        ld a,(hl)
        or a
        jr z,D_NEW_BYTE
        dec (hl)
        ld hl,(D_NEXT_PARAM)
        ld (hl),b
        inc hl
        ld (D_NEXT_PARAM),hl
        ret nz                 ; word increment and loads preserve pending's Z
        jr D_EXECUTE
D_NEW_BYTE:
        ld a,b
        cp 32
        jr c,D_CONTROL
        ld a,(D_DISABLED)
        or a
        ret nz
        ld a,(D_ACTIVE)
        or a
        ld a,b
        jp z,RAW_WRCH
        cp 127
        jp z,D_DELETE
        jp D_PRINT
D_CONTROL:
        ld a,b
        ld (D_COMMAND),a
        ld hl,D_LENGTHS
        ld e,a
        ld d,0
        add hl,de
        ld a,(hl)
        ld (D_PENDING),a
        ld hl,D_PARAMS
        ld (D_NEXT_PARAM),hl
        or a
        ret nz
D_EXECUTE:
        ld a,(D_DISABLED)
        or a
        jr z,D_EXECUTE_ENABLED
        ld a,(D_COMMAND)
        cp 6
        ret nz
D_EXECUTE_ENABLED:
        ld a,(D_COMMAND)
        add a,a
        ld e,a
        ld d,0
        ld hl,D_HANDLERS
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        jp (hl)
D_NOOP: ret
; Commands are bounded to 0..31 by D_CONTROL. Parameter lengths remain
; separate so fragmented and disabled VDU sequences are consumed identically.
D_HANDLERS:
        defw D_NOOP,D_NOOP,D_NOOP,D_NOOP
        defw D_TEXT_TEXT,D_TEXT_GRAPH,D_ENABLE,D_NOOP
        defw D_BACK,D_FORWARD,D_DOWN,D_UP
        defw D_CLEAR,D_RETURN,D_UNSUPPORTED,D_NOOP
        defw G_CLEAR,D_VCOLOUR,D_VGCOL,D_PALETTE
        defw D_DEFAULT_COLOURS,D_DISABLE,D_VMODE,D_DEFINE
        defw G_WINDOW,D_VPLOT,D_WINDOWS,D_UNSUPPORTED
        defw D_TEXT_WINDOW,G_SET_ORIGIN,D_HOME,D_VCURSOR
D_TEXT_TEXT:
        xor a
        ld (D_GRAPH_TEXT),a
        ret
D_TEXT_GRAPH:
        ld a,(D_BITMAP)
        or a
        jp z,D_UNSUPPORTED
        ld a,1
        ld (D_GRAPH_TEXT),a
        ret
D_ENABLE:
        xor a
        ld (D_DISABLED),a
        ret
D_DISABLE:
        ld a,1
        ld (D_DISABLED),a
        ret
D_VCOLOUR:
        ld a,(D_PARAMS)
        ld e,a
        ld d,0
        call Z_NORMALIZE_COLOUR
        jp D_COLOUR
D_VGCOL:
        ld a,(D_PARAMS+1)
        ld e,a
        ld d,0
        call Z_NORMALIZE_COLOUR
        ld a,(D_PARAMS)
        jp G_COLOUR
D_VMODE:
        ld a,(D_PARAMS)
        jp D_MODE
D_VPLOT:
        ld de,(D_PARAMS+1)
        ld hl,(D_PARAMS+3)
        ld a,(D_PARAMS)
        jp G_PLOT
D_VCURSOR:
        ld a,(D_PARAMS)
        ld e,a
        ld d,0
        ld a,(D_PARAMS+1)
        ld l,a
        ld h,0
        jp D_SETCURSOR
D_LENGTHS:
        defb 0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        defb 0,1,2,5,0,0,1,9,8,5,0,0,4,4,0,2
; Snapshot fonts once. The original font is restored even after definitions.
D_SAVE:
        ld a,(D_SAVED)
        or a
        ret nz
        in a,(0x82)
        inc a
        cp 2
        jp c,D_UNSUPPORTED      ; reject firmware 0 and absent-device &FF
        ld de,0x3000
        ld hl,D_ORIGINAL_FONT
        ld bc,3072
D_SAVE_FONT:
        call D_VREAD
        ld (hl),a
        inc hl
        inc de
        dec bc
        ld a,b
        or c
        jr nz,D_SAVE_FONT
        ld a,1
        ld (D_SAVED),a
        ret
D_DEFAULT_COLOURS:
        call D_TAKE_TEXT
        xor a
        ld (G_ACTION),a
        ld (G_BG),a
        ld (D_BG),a
        ld a,(D_MASK)
        ld (G_FG),a
        ld (D_FG),a
        jp Z_PALETTE
D_PAL_WORD:
        ld a,l
        call D_VWRITE
        inc de
        ld a,h
        jp D_VWRITE
D_PALETTE:
        call D_TAKE_TEXT
        ld a,(D_PARAMS)
        ld b,a
        ld a,(Z_KIND)
        or a
        jr nz,D_PALETTE_VALID
        ld a,(D_MASK)
        cp b
        jp c,D_ERROR
D_PALETTE_VALID:
        ld a,b
        call Z_PALETTE_ADDRESS
        ld a,(D_PARAMS+1)
        cp 16
        jr z,D_RGB
        cp 8
        jp nc,D_UNSUPPORTED    ; flashing physical colours deferred
        call Z_BBC_COLOUR
        jr D_PAL_WORD
D_RGB:
        ; RGB888 -> RGB565, BBC extended VDU 19 logical,16,r,g,b.
        ld a,(D_PARAMS+2)
        and 0xf8
        ld h,a
        ld a,(D_PARAMS+3)
        rrca
        rrca
        rrca
        rrca
        rrca
        and 7
        or h
        ld h,a
        ld a,(D_PARAMS+3)
        and 0x1c
        add a,a
        add a,a
        add a,a
        ld l,a
        ld a,(D_PARAMS+4)
        rrca
        rrca
        rrca
        and 31
        or l
        ld l,a
        jp D_PAL_WORD
D_COLOUR:
        ld a,(D_MASK)
        and e
        bit 0,d
        jr nz,D_COLOUR_BG
        ld (D_FG),a
        jr D_SET_OS_COLOURS
D_COLOUR_BG:
        ld (D_BG),a
D_SET_OS_COLOURS:
        ld a,(Z_KIND)
        cp 2
        jp nc,Z_TEXT_COLOURS
        ld a,(D_ACTIVE)
        or a
        ret nz
        ld a,(D_FG)
        call D_VGA_COLOUR
        ld e,a
        ld a,(D_BG)
        call D_VGA_COLOUR
        ld d,a
        ld c,CMD_SET_COLORS
        jp D_IOCTL
D_IOCTL:
        ld h,DEV_STDOUT
        ld l,7
        jp ZOS_SYSCALL
D_VGA_COLOUR:
        and 7
        ld hl,D_VGA_TABLE
        add a,l
        ld l,a
        jr nc,D_VGA_LOOKUP
        inc h
D_VGA_LOOKUP:
        ld a,(hl)
        ret
D_VGA_TABLE: defb 0,12,10,14,9,13,11,15
; Every active display has already saved the font. Callers can use this
; entry to establish both ownership and the font-save invariant.
D_TAKE_TEXT:
        ld a,(D_ACTIVE)
        or a
        ret nz
        call D_SAVE
        call D_GETCURSOR
        ld a,e
        ld (D_X),a
        ld a,l
        ld (D_Y),a
        ld a,1
        ld (D_ACTIVE),a
        call D_DEFAULT_COLOURS
        xor a
        out (0x8e),a
        out (0xa6),a
        ret
D_WINDOWS:
        call D_TAKE_TEXT
        xor a
        ld (D_LEFT),a
        ld (D_TOP),a
        ld a,(D_COLS)
        dec a
        ld (D_RIGHT),a
        ld a,(D_ROWS)
        dec a
        ld (D_BOTTOM),a
        ; Reset the graphics window through the same window validator.
        ld hl,0
        ld (D_PARAMS),hl
        ld (D_PARAMS+2),hl
        call G_SET_ORIGIN
        ld hl,1279
        ld (D_PARAMS+4),hl
        ld hl,1023
        ld (D_PARAMS+6),hl
        call G_WINDOW
        jp D_HOME
D_TEXT_WINDOW:
        call D_TAKE_TEXT
        ld a,(D_PARAMS)
        ld b,a
        ld a,(D_PARAMS+2)
        cp b
        jp c,D_ERROR
        ld b,a
        ld a,(D_COLS)
        dec a
        cp b
        jp c,D_ERROR
        ld a,(D_PARAMS+3)
        ld b,a
        ld a,(D_PARAMS+1)
        cp b
        jp c,D_ERROR
        ld b,a
        ld a,(D_ROWS)
        dec a
        cp b
        jp c,D_ERROR
        ld hl,D_PARAMS
        ld de,D_LEFT
        ld bc,4
        ldir                   ; VDU order: left, bottom, right, top
        jr D_HOME
D_SETCURSOR:
        push bc
        ld a,(D_ACTIVE)
        or a
        jr nz,D_CURSOR_OWN
        ld a,e
        ld e,l
        ld d,a
        ld c,CMD_SET_CURSOR_XY
        call D_IOCTL
        pop bc
        ret
D_CURSOR_OWN:
        ld a,d
        or h
        jp nz,D_ERROR
        ld a,(D_LEFT)
        add a,e
        jp c,D_ERROR
        ld b,a
        ld a,(D_RIGHT)
        cp b
        jp c,D_ERROR
        ld c,b
        ld a,(D_TOP)
        add a,l
        jp c,D_ERROR
        ld b,a
        ld a,(D_BOTTOM)
        cp b
        jp c,D_ERROR
        ld a,b
        ld (D_Y),a
        ld a,c
        ld (D_X),a
        pop bc
        ret
D_GETCURSOR:
        ld a,(D_ACTIVE)
        or a
        jr nz,D_GET_OWN
        ld c,CMD_GET_CURSOR_XY
        ld de,D_CURSOR
        call D_IOCTL
        ld a,(D_CURSOR)
        ld e,a
        ld d,0
        ld a,(D_CURSOR+1)
        ld l,a
        ld h,0
        ret
D_GET_OWN:
        ld a,(D_LEFT)
        ld b,a
        ld a,(D_X)
        sub b
        ld e,a
        ld d,0
        ld a,(D_TOP)
        ld b,a
        ld a,(D_Y)
        sub b
        ld l,a
        ld h,0
        ret
D_HOME:
        ld a,(D_LEFT)
        ld (D_X),a
        ld a,(D_TOP)
        ld (D_Y),a
        ld a,(D_ACTIVE)
        or a
        ret nz
        ld de,0
        ld hl,0
        jp D_SETCURSOR
D_RETURN:
        ld a,(D_GRAPH_TEXT)
        or a
        jr z,D_RETURN_TEXT
        ld hl,0
        ld (G_X),hl
        ret
D_RETURN_TEXT:
        ld a,(D_ACTIVE)
        or a
        ld a,13
        jp z,RAW_WRCH
        ld a,(D_LEFT)
        ld (D_X),a
        ret
D_BACK:
        ld a,(D_GRAPH_TEXT)
        or a
        jr z,D_BACK_TEXT
        call D_GRAPH_STEP
        ld hl,(G_X)
        or a
        sbc hl,de
        ld (G_X),hl
        ret
D_BACK_TEXT:
        ld a,(D_ACTIVE)
        or a
        ld a,8
        jp z,RAW_WRCH
        ld a,(D_LEFT)
        ld b,a
        ld a,(D_X)
        cp b
        jr z,D_BACK_ROW
        dec a
        ld (D_X),a
        ret
D_BACK_ROW:
        ld a,(D_RIGHT)
        ld (D_X),a
        jr D_UP
D_GRAPH_STEP:
        ld de,32
        ld a,(D_MODE_NO)
        cp 9
        ret nz
        ld e,40
        ret
D_GRAPH_Y_STEP:
        ld de,64
        ld a,(D_MODE_NO)
        cp 9
        ret nz
        ld e,52
        ret
D_FORWARD:
        ld a,(D_GRAPH_TEXT)
        or a
        jr z,D_FORWARD_TEXT
        call D_GRAPH_STEP
        ld hl,(G_X)
        add hl,de
        ld (G_X),hl
        ret
D_FORWARD_TEXT:
        ld a,(D_ACTIVE)
        or a
        ld a,9
        jp z,RAW_WRCH
        ld a,(D_RIGHT)
        ld b,a
        ld a,(D_X)
        cp b
        jr nc,D_WRAP
        inc a
        ld (D_X),a
        ret
D_WRAP:
        call D_RETURN
        jr D_DOWN_OWN
D_UP:
        ld a,(D_GRAPH_TEXT)
        or a
        jr z,D_UP_TEXT
        call D_GRAPH_Y_STEP
        ld hl,(G_Y)
        add hl,de
        ld (G_Y),hl
        ret
D_UP_TEXT:
        ld a,(D_ACTIVE)
        or a
        ld a,11
        jp z,RAW_WRCH
        ld a,(D_TOP)
        ld b,a
        ld a,(D_Y)
        cp b
        ret z
        dec a
        ld (D_Y),a
        ret
D_DOWN:
        ld a,(D_GRAPH_TEXT)
        or a
        jr z,D_DOWN_TEXT
        call D_GRAPH_Y_STEP
        ld hl,(G_Y)
        or a
        sbc hl,de
        ld (G_Y),hl
        ret
D_DOWN_TEXT:
        ld a,(D_ACTIVE)
        or a
        ld a,10
        jp z,RAW_WRCH
        call D_RETURN          ; Zeal BASIC uses LF alone for a newline
D_DOWN_OWN:
        ld a,(D_BOTTOM)
        ld b,a
        ld a,(D_Y)
        cp b
        jp nc,D_SCROLL
        inc a
        ld (D_Y),a
        ret
D_DELETE:
        call D_BACK
        ld a,(D_GRAPH_TEXT)
        or a
        jr z,D_DELETE_SPACE
        ld a,2                 ; internal graphics-cell erase, independent of glyph/GCOL
        ld (D_GRAPH_TEXT),a
        ld a,32
        call D_PRINT
        ld a,1
        ld (D_GRAPH_TEXT),a
        jp D_BACK
D_DELETE_SPACE:
        ld a,32
        call D_PRINT
        jp D_BACK
; Calculate native text-map addresses or fixed 8x12 bitmap character cells.
D_CELL:
        ld a,(D_BITMAP)
        or a
        jr nz,D_BITMAP_CELL
        ld a,(D_X)
        ld l,a
        ld h,0
        ld a,(D_Y)
        ld e,a
        ld d,0
        ex de,hl
        jp V_TEXT_ADDRESS
D_BITMAP_CELL:
        ld a,(D_X)
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld (D_GX),hl
        ld a,(D_Y)
        call D_ROW_Y
        ld (D_GY),hl
        ret
D_ROW_Y:
        ld h,0
        ld l,a
        add hl,hl
        add hl,hl
        ld d,h
        ld e,l
        add hl,hl
        add hl,de
        ret
D_PRINT:
        ld (D_CHAR),a
        ld a,(D_GRAPH_TEXT)
        or a
        jp nz,D_GRAPH_PRINT
        ld a,(D_BITMAP)
        or a
        jr nz,D_PRINT_BITMAP
        call D_CELL
        ld a,(D_CHAR)
        call D_WRITE_CELL
        jp D_FORWARD
D_WRITE_CELL:
        ld b,a
        ld a,(Z_KIND)
        cp 2
        ld a,b
        jp nc,Z_TEXT_CELL
        call D_VWRITE
        ld a,d
        add a,0x10
        ld d,a
        ld a,(D_BG)
        rlca
        rlca
        rlca
        rlca
        ld b,a
        ld a,(D_FG)
        or b
        jp D_VWRITE
D_PRINT_BITMAP:
        call D_CELL
        call D_LOAD_GLYPH
        call D_DRAW_GLYPH
        jp D_FORWARD
D_FONT_ADDRESS:
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        ld d,h
        ld e,l
        add hl,hl
        add hl,de
        ld de,0x3000
        add hl,de
        ex de,hl
        ret
D_LOAD_GLYPH:
        ld a,(D_CHAR)
        call D_FONT_ADDRESS
        ld hl,D_GLYPH
        ld b,12
D_GLYPH_LOAD:
        call D_VREAD
        ld (hl),a
        inc hl
        inc de
        djnz D_GLYPH_LOAD
        ret
D_DRAW_GLYPH:
        ld c,0
D_GLYPH_ROW:
        ; Native 8x12 font cells: no BBC row sampling or width stretching.
        ld a,c
        ld e,a
        ld d,0
        ld hl,D_GLYPH
        add hl,de
        ld a,(hl)
D_GLYPH_BITS:
        ld (D_BITS),a
        ld a,c
        ld e,a
        ld d,0
        ld hl,(D_GY)
        add hl,de
        ld de,(D_GX)
        ld a,(D_GRAPH_TEXT)
        or a
        call z,V_ADDRESS       ; opaque rows advance a VRAM pointer directly
        ld b,8
D_GLYPH_COL:
        ld a,(D_GRAPH_TEXT)
        or a
        jr z,D_GLYPH_OPAQUE
        cp 2
        jr z,D_GLYPH_ERASE
        ld a,(D_BITS)
        bit 7,a
        call nz,G_TEXT_PIXEL
        jr D_GLYPH_NEXT
D_GLYPH_ERASE:
        call G_TEXT_ERASE_PIXEL
        jr D_GLYPH_NEXT
D_GLYPH_OPAQUE:
        ld a,(D_BITS)
        bit 7,a
        ld a,(D_BG)
        jr z,D_GLYPH_WRITE
        ld a,(D_FG)
D_GLYPH_WRITE:
        call V_WRITE
D_GLYPH_NEXT:
        inc de
        ld a,(D_BITS)
        rlca
        ld (D_BITS),a
D_GLYPH_STEP:
        djnz D_GLYPH_COL
        inc c
        ld a,c
        cp 12
        jp nz,D_GLYPH_ROW
        ret
D_GRAPH_PRINT:
        ld a,(D_BITMAP)
        or a
        jp z,D_UNSUPPORTED
        ld de,(G_X)
        ld hl,(G_Y)
        call G_TRANSFORM
        ld (D_GX),de
        ld (D_GY),hl
        call D_LOAD_GLYPH
        call D_DRAW_GLYPH
        jp D_FORWARD
D_CLEAR:
        ld a,(D_ACTIVE)
        or a
        jr nz,D_CLEAR_OWN
        ld c,CMD_CLEAR_SCREEN
        jp D_IOCTL
D_CLEAR_OWN:
        call D_WINDOW_RECT
        ld a,(D_BG)
        ld (D_FILL),a
        call D_FILL_RECT
        jp D_HOME
; Convert the text window into a physical rectangle (pixel or text cells).
D_WINDOW_RECT:
        ; Expand the byte-sized text bounds in their shared left/bottom/right/
        ; top order. Convert boundaries directly without moving the cursor.
        ld hl,D_LEFT
        ld de,D_L
        ld b,4
D_WINDOW_EXPAND:
        ld a,(hl)
        inc hl
        ld (de),a
        inc de
        xor a
        ld (de),a
        inc de
        djnz D_WINDOW_EXPAND
        ld a,(D_BITMAP)
        or a
        ret z
        ld b,8
        ld hl,(D_L)
        ld de,(D_R)
        inc de                 ; scale the exclusive right boundary
D_WINDOW_SCALE_X:
        srl b
        jr z,D_WINDOW_X_READY
        add hl,hl
        ex de,hl
        add hl,hl
        ex de,hl
        jr D_WINDOW_SCALE_X
D_WINDOW_X_READY:
        dec de
        ld (D_L),hl
        ld (D_R),de
        ld a,(D_TOP)
        call D_ROW_Y
        ld (D_T),hl
        ld a,(D_BOTTOM)
        inc a
        call D_ROW_Y
        dec hl
        ld (D_B),hl
        ret
D_FILL_RECT:
        ld hl,(D_T)
        ld (D_CY),hl
D_FILL_ROW:
        ld de,(D_L)
        ld hl,(D_CY)
        call D_ADDRESS
        call D_ROW_WIDTH
        ld a,(D_BITMAP)
        or a
        jr z,D_FILL_TEXT
        ld a,(D_FILL)
        call V_SPAN
        jr D_FILL_NEXT
D_FILL_TEXT:
        push bc
        push de
        ld a,32
        call D_WRITE_CELL
        pop de
        pop bc
        inc de
        dec bc
        ld a,b
        or c
        jr nz,D_FILL_TEXT
D_FILL_NEXT:
        call TRAP
        ld hl,(D_CY)
        ld de,(D_B)
        or a
        sbc hl,de
        ret z
        ld hl,(D_CY)
        inc hl
        ld (D_CY),hl
        jr D_FILL_ROW
D_ROW_WIDTH:
        push de
        ld hl,(D_R)
        ld de,(D_L)
        or a
        sbc hl,de
        inc hl
        ld b,h
        ld c,l
        pop de
        ret
D_ADDRESS:
        ld a,(D_BITMAP)
        or a
        jp nz,V_ADDRESS
        jp V_TEXT_ADDRESS
D_SCROLL:
        call D_WINDOW_RECT
        ld a,(D_BG)
        ld (D_FILL),a
        ld hl,1
        ld (D_SCROLL_H),hl
        ld a,(D_BITMAP)
        or a
        jr z,D_SCROLL_BEGIN
        ld hl,12
        ld (D_SCROLL_H),hl
D_SCROLL_BEGIN:
        ld hl,(D_T)
        ld (D_CY),hl
D_SCROLL_ROW:
D_SCROLL_ROW_READY:
        ld de,(D_L)
        ld hl,(D_CY)
        call D_ADDRESS
        ld (D_SCROLL_DEST),de
        ld hl,(D_CY)
        ld de,(D_SCROLL_H)
        add hl,de
D_SCROLL_SOURCE_READY:
        ld de,(D_B)
        push hl
        or a
        sbc hl,de
        pop hl
        jr c,D_SCROLL_COPY
        jr z,D_SCROLL_COPY
        jp D_FILL_ROW           ; blank all remaining rows in the same window
D_SCROLL_COPY:
        ld de,(D_L)
        call D_ADDRESS
        call D_ROW_WIDTH
        ld hl,(D_SCROLL_DEST)
        ld a,(D_BITMAP)
        or a
        jr z,D_SCROLL_TEXT
        call D_COPY_PIXELS
        jr D_SCROLL_NEXT
D_SCROLL_TEXT:
        push bc
        push de
        push hl
        call D_COPY_TEXT
        pop hl
        pop de
        pop bc
        ld a,d
        add a,0x10
        ld d,a
        ld a,h
        add a,0x10
        ld h,a
        call D_COPY_TEXT
D_SCROLL_NEXT:
        call TRAP
        ld hl,(D_CY)
        inc hl
        ld (D_CY),hl
        jp D_SCROLL_ROW
; Rows always copy toward lower addresses. Each access restores the mapping,
; so source and destination may occupy different video pages.
D_COPY_PIXELS:
        call V_READ
        ex de,hl
        call V_WRITE
        ex de,hl
        inc de
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,D_COPY_PIXELS
        ret
D_COPY_TEXT:
        call D_VREAD
        ex de,hl
        call D_VWRITE
        ex de,hl
        inc de
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,D_COPY_TEXT
        ret
; UDG definition: store an 8x8 BBC glyph expanded into the ZVB 8x12 font.
D_DEFINE:
        ld a,(D_PARAMS)
        cp 1
        ret z                 ; VDU 23,1 cursor visibility (no bitmap cursor)
        cp 32
        jp c,D_UNSUPPORTED
        ld a,(Z_KIND)
        cp 2
        jr c,D_DEFINE_NATIVE
        ld a,(D_PARAMS)
        cp 128
        jp nc,D_UNSUPPORTED
D_DEFINE_NATIVE:
        call D_SAVE
        ld a,(D_PARAMS)
        call D_FONT_ADDRESS
        ld b,12
        ld c,0
D_DEFINE_ROW:
        push de
        ld e,c
        ld d,0
        ld hl,D_EXPAND_ROWS
        add hl,de
        ld e,(hl)
        ld hl,D_PARAMS+1
        add hl,de
        ld a,(hl)
        pop de
        call D_VWRITE
        inc de
        inc c
        djnz D_DEFINE_ROW
        ld a,(Z_KIND)
        cp 2
        ret c
        jp Z_TILE_FONT
D_EXPAND_ROWS: defb 0,0,1,2,2,3,4,4,5,6,6,7
D_EXIT:
        ld a,(D_SAVED)
        or a
        ret z
        ld hl,D_ORIGINAL_FONT
        ld de,0x3000
        ld bc,3072
D_RESTORE_FONT:
        ld a,(hl)
        call D_VWRITE
        inc hl
        inc de
        dec bc
        ld a,b
        or c
        jr nz,D_RESTORE_FONT
        xor a
        ld (D_ACTIVE),a
        ld (D_BITMAP),a
        ld (D_SAVED),a
        ld c,CMD_RESET_SCREEN
        call D_IOCTL
        call Z_NATIVE_STATE
        jp D_RESET_SEQUENCE
