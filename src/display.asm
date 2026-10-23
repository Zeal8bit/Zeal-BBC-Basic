; BBC VDU state and ZVB backend. Native startup output remains an OS stream.
; After MODE, this module owns cursor, windows, scrolling and input echo.
        EXTERN D_CHAR, D_GX, D_GY, D_GW, D_GH, D_GROW
        EXTERN D_BITS, D_FILL, D_L, D_T, D_R, D_B
        EXTERN D_CX, D_CY, D_SCROLL_LINE, D_SCROLL_BOUNDARY, D_SCROLL_SOURCE_END, D_SCROLL_H
        EXTERN D_SCROLL_DEST
        INCLUDE "zos_syscall.asm"
        INCLUDE "zos_video.asm"
        PUBLIC D_BYTE, D_CLEAR, D_SETCURSOR, D_GETCURSOR, D_MODE, D_COLOUR
        PUBLIC D_BITMAP, D_ACTIVE, D_MASK, D_ERROR, D_UNSUPPORTED
        EXTERN V_READ, V_WRITE, V_SPAN, D_VREAD, D_VWRITE
        EXTERN V_ADDRESS, V_TEXT_ADDRESS
        PUBLIC D_RESET_SEQUENCE, D_EXIT, D_FILL_RECT
        EXTERN ZOS_SYSCALL, RAW_WRCH, EXTERR, TRAP
        EXTERN G_CLEAR, G_COLOUR, G_PLOT, G_RESET, G_WINDOW, G_SET_ORIGIN
        EXTERN G_X, G_Y
        EXTERN G_TRANSFORM, G_TEXT_PIXEL, G_ABORT
D_ACTIVE: defb 0
D_BITMAP: defb 0
D_MODE_NO: defb 255
D_MASK: defb 15
D_COLS: defb 80
D_ROWS: defb 40
D_X: defb 0
D_Y: defb 0
D_LEFT: defb 0
D_TOP: defb 0
D_RIGHT: defb 79
D_BOTTOM: defb 39
D_FG: defb 7
D_BG: defb 0
D_DISABLED: defb 0
D_GRAPH_TEXT: defb 0
D_SAVED: defb 0
D_PENDING: defb 0
D_COMMAND: defb 0
D_INDEX: defb 0
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
        ld (D_INDEX),a
        ld (D_DISABLED),a
        ld (D_GRAPH_TEXT),a
        jp G_ABORT
; OSWRCH wraps this entry to preserve main registers; no alternate bank use.
D_BYTE:
        ld b,a
        ld a,(D_PENDING)
        or a
        jr z,D_NEW_BYTE
        ld hl,D_PARAMS
        ld a,(D_INDEX)
        ld e,a
        ld d,0
        add hl,de
        ld (hl),b
        inc a
        ld (D_INDEX),a
        ld a,(D_PENDING)
        dec a
        ld (D_PENDING),a
        ret nz
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
        xor a
        ld (D_INDEX),a
        ld a,(D_PENDING)
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
        jp D_COLOUR
D_VGCOL:
        ld a,(D_PARAMS+1)
        ld e,a
        ld a,(D_PARAMS)
        jp G_COLOUR
D_VMODE:
        ld a,(D_PARAMS)
        jr D_MODE
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
        cp 0xff
        jp z,D_UNSUPPORTED
        or a
        jp z,D_UNSUPPORTED      ; bitmap modes require ZVB firmware 1.x+
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
D_MODE:
        cp 7
        jp nc,D_UNSUPPORTED
        push af
        call D_SAVE
        pop af
        ld (D_MODE_NO),a
        ld e,a
        ld d,0
        ld hl,D_MODES
        add hl,de
        ld a,(hl)
        ld (D_MASK),a
        ld hl,D_WIDTHS
        add hl,de
        ld a,(hl)
        ld (D_COLS),a
        ld a,e
        cp 3
        jr z,D_TEXT_MODE
        cp 6
        jr z,D_TEXT_MODE
        ld a,1
        ld (D_BITMAP),a
        ld a,32
        ld (D_ROWS),a
        ld a,3
        jr D_MODE_SET
D_TEXT_MODE:
        xor a
        ld (D_BITMAP),a
        ld a,25
        ld (D_ROWS),a
        xor a
D_MODE_SET:
        out (0x9c),a
        xor a
        out (0x8e),a
        out (0xa6),a          ; no hardware cursor; software owns layout
        out (0xa3),a
        out (0xa4),a
        ld a,0x80
        out (0x9d),a
        ld a,1
        ld (D_ACTIVE),a
        call D_RESET_SEQUENCE
        call D_WINDOWS
        call G_RESET
        call D_DEFAULT_COLOURS
        jp D_CLEAR
D_MODES: defb 1,3,15,1,1,3,1
D_WIDTHS: defb 80,40,20,80,40,20,40
D_DEFAULT_COLOURS:
        call D_TAKE_TEXT
        call D_SAVE
        ld a,(D_MASK)
        ld e,a
        xor a
        call G_COLOUR
        ld e,128
        xor a
        call G_COLOUR
        xor a
        ld (D_BG),a
        ld a,(D_MASK)
        ld (D_FG),a
        ld hl,D_BBC_PALETTE
        ld de,0x0e00
        ld b,16
D_PAL_LOOP:
        ld a,(hl)
        call D_VWRITE
        inc hl
        inc de
        ld a,(hl)
        call D_VWRITE
        inc hl
        inc de
        djnz D_PAL_LOOP
        ; BBC default logical palettes: 2 colours black/white; 4 colours
        ; black/red/yellow/white; 16 colours use BBC physical colour numbers.
        ld a,(D_MASK)
        cp 1
        jr nz,D_PAL_FOUR
        ld hl,0xffff
        ld de,0x0e02
        jr D_PAL_WORD
D_PAL_FOUR:
        cp 3
        ret nz
        ld hl,0xf800
        ld de,0x0e02
        call D_PAL_WORD
        ld hl,0xffe0
        ld de,0x0e04
        call D_PAL_WORD
        ld hl,0xffff
        ld de,0x0e06
D_PAL_WORD:
        ld a,l
        call D_VWRITE
        inc de
        ld a,h
        jp D_VWRITE
D_BBC_PALETTE:
        defw 0,0xf800,0x07e0,0xffe0,0x001f,0xf81f,0x07ff,0xffff
        defw 0,0xf800,0x07e0,0xffe0,0x001f,0xf81f,0x07ff,0xffff
D_PALETTE:
        call D_TAKE_TEXT
        call D_SAVE
        ld a,(D_PARAMS)
        ld b,a
        ld a,(D_MASK)
        cp b
        jp c,D_ERROR
        ld a,b
        add a,a
        ld e,a
        ld d,0x0e
        ld a,(D_PARAMS+1)
        cp 16
        jr z,D_RGB
        cp 8
        jp nc,D_UNSUPPORTED    ; flashing physical colours deferred
        add a,a
        ld l,a
        ld h,0
        ld bc,D_BBC_PALETTE
        add hl,bc
        ld c,(hl)
        inc hl
        ld h,(hl)
        ld l,c
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
        ld e,a
        ld a,(D_MASK)
        and e
        bit 7,e
        jr nz,D_COLOUR_BG
        ld (D_FG),a
        jr D_SET_OS_COLOURS
D_COLOUR_BG:
        ld (D_BG),a
D_SET_OS_COLOURS:
        ld a,(D_ACTIVE)
        or a
        ret nz
        ld a,(D_FG)
        call D_VGA_COLOUR
        ld e,a
        ld a,(D_BG)
        call D_VGA_COLOUR
        ld d,a
        ld h,DEV_STDOUT
        ld c,CMD_SET_COLORS
        BBC_SYSCALL(7)
        ret
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
        cp b
        jp z,D_ERROR
        jp c,D_ERROR
        ld a,(D_PARAMS+3)
        ld b,a
        ld a,(D_PARAMS+1)
        cp b
        jp c,D_ERROR
        ld b,a
        ld a,(D_ROWS)
        cp b
        jp z,D_ERROR
        jp c,D_ERROR
        ld a,(D_PARAMS)
        ld (D_LEFT),a
        ld a,(D_PARAMS+1)
        ld (D_BOTTOM),a
        ld a,(D_PARAMS+2)
        ld (D_RIGHT),a
        ld a,(D_PARAMS+3)
        ld (D_TOP),a
        jr D_HOME
D_SETCURSOR:
        push bc
        ld a,(D_ACTIVE)
        or a
        jr nz,D_CURSOR_OWN
        ld a,e
        ld e,l
        ld d,a
        ld h,DEV_STDOUT
        ld c,CMD_SET_CURSOR_XY
        BBC_SYSCALL(7)
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
        ld h,DEV_STDOUT
        ld c,CMD_GET_CURSOR_XY
        ld de,D_CURSOR
        BBC_SYSCALL(7)
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
        call D_CHAR_WIDTH
        add a,a
        add a,a
        ld e,a
        ld d,0
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
        ld hl,(G_Y)
        ld de,32
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
        ld hl,(G_Y)
        ld de,-32
        add hl,de
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
        ld a,32
        call D_PRINT
        jp D_BACK
; Calculate cell origin and dimensions for current cursor. BBC bitmap modes
; have 32 rows in 200 pixels; row boundaries alternate between 6 and 7 pixels.
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
D_CHAR_WIDTH:
        ld a,(D_COLS)
        ld b,4
        cp 80
        jr z,D_CHAR_WIDTH_DONE
        ld b,8
        cp 40
        jr z,D_CHAR_WIDTH_DONE
        ld b,16
D_CHAR_WIDTH_DONE:
        ld a,b
        ld (D_GW),a
        ret
D_BITMAP_CELL:
        call D_CHAR_WIDTH
        ld a,(D_X)
        ld l,a
        ld h,0
        ld c,b
D_CELL_MUL:
        srl c
        jr z,D_CELL_X
        add hl,hl
        jr D_CELL_MUL
D_CELL_X:
        ld (D_GX),hl
        ld a,(D_Y)
        call D_ROW_Y
        ld (D_GY),hl
        push hl
        ld a,(D_Y)
        inc a
        call D_ROW_Y
        pop de
        or a
        sbc hl,de
        ld a,l
        ld (D_GH),a
        ret
D_ROW_Y:
        ; row*25 = row*(16+8+1)
        ld h,0
        ld l,a
        add hl,hl
        add hl,hl
        add hl,hl
        ld d,h
        ld e,l
        add hl,hl
        add hl,de
        ld e,a
        ld d,0
        add hl,de
        srl h
        rr l
        srl h
        rr l
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
        xor a
        ld (D_GROW),a
D_GLYPH_ROW:
        ; Sample the 12-row native font at six useful rows. Seven-pixel
        ; cells have a final background scanline. UDGs use the same mapping.
        ld a,(D_GROW)
        cp 6
        ld a,0
        jr nc,D_GLYPH_BITS
        ld a,(D_GROW)
        ld e,a
        ld d,0
        ld hl,D_FONT_ROWS
        add hl,de
        ld e,(hl)
        ld hl,D_GLYPH
        add hl,de
        ld a,(hl)
D_GLYPH_BITS:
        ld (D_BITS),a
        ld a,(D_GROW)
        ld e,a
        ld d,0
        ld hl,(D_GY)
        add hl,de
        ld de,(D_GX)
        ld a,(D_GRAPH_TEXT)
        or a
        call z,V_ADDRESS       ; opaque rows advance a VRAM pointer directly
        ld a,(D_GW)
        ld b,a
D_GLYPH_COL:
        ld a,(D_GRAPH_TEXT)
        or a
        jr z,D_GLYPH_OPAQUE
        ld a,(D_BITS)
        bit 7,a
        call nz,G_TEXT_PIXEL
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
        ld a,(D_GW)
        cp 16
        jr nz,D_GLYPH_ROTATE
        bit 0,b                ; 16-pixel cells repeat each source bit twice
        jr z,D_GLYPH_STEP
D_GLYPH_ROTATE:
        ld a,(D_BITS)
        rlca
        ld c,a
        ld a,(D_GW)
        cp 4
        ld a,c
        jr nz,D_GLYPH_SAVE
        rlca                   ; four-pixel cells sample alternate source bits
D_GLYPH_SAVE:
        ld (D_BITS),a
D_GLYPH_STEP:
        djnz D_GLYPH_COL
        ld a,(D_GROW)
        inc a
        ld (D_GROW),a
        ld b,a
        ld a,(D_GH)
        cp b
        jp nz,D_GLYPH_ROW
        ret
D_FONT_ROWS: defb 1,3,5,6,8,10
D_GRAPH_PRINT:
        ld a,(D_BITMAP)
        or a
        jp z,D_UNSUPPORTED
        ld de,(G_X)
        ld hl,(G_Y)
        call G_TRANSFORM
        ld (D_GX),de
        ld (D_GY),hl
        call D_CHAR_WIDTH
        ld a,6
        ld (D_GH),a
        call D_LOAD_GLYPH
        call D_DRAW_GLYPH
        jp D_FORWARD
D_CLEAR:
        ld a,(D_ACTIVE)
        or a
        jr nz,D_CLEAR_OWN
        ld h,DEV_STDOUT
        ld c,CMD_CLEAR_SCREEN
        BBC_SYSCALL(7)
        ret
D_CLEAR_OWN:
        call D_WINDOW_RECT
        ld a,(D_BG)
        ld (D_FILL),a
        call D_FILL_RECT
        jp D_HOME
; Convert the text window into a physical rectangle (pixel or text cells).
D_WINDOW_RECT:
        ld a,(D_X)
        push af
        ld a,(D_Y)
        push af
        ld a,(D_LEFT)
        ld (D_X),a
        ld a,(D_TOP)
        ld (D_Y),a
        ld a,(D_BITMAP)
        or a
        jr z,D_WINDOW_TEXT
        call D_CELL
        ld hl,(D_GX)
        ld (D_L),hl
        ld hl,(D_GY)
        ld (D_T),hl
        ld a,(D_RIGHT)
        ld (D_X),a
        ld a,(D_BOTTOM)
        ld (D_Y),a
        call D_CELL
        ld hl,(D_GX)
        ld a,(D_GW)
        ld e,a
        ld d,0
        add hl,de
        dec hl
        ld (D_R),hl
        ld hl,(D_GY)
        ld a,(D_GH)
        ld e,a
        ld d,0
        add hl,de
        dec hl
        ld (D_B),hl
        jr D_WINDOW_DONE
D_WINDOW_TEXT:
        ld a,(D_LEFT)
        ld l,a
        ld h,0
        ld (D_L),hl
        ld a,(D_RIGHT)
        ld l,a
        ld (D_R),hl
        ld a,(D_TOP)
        ld l,a
        ld (D_T),hl
        ld a,(D_BOTTOM)
        ld l,a
        ld (D_B),hl
D_WINDOW_DONE:
        pop af
        ld (D_Y),a
        pop af
        ld (D_X),a
        ret
D_FILL_RECT:
        ld hl,(D_T)
        ld (D_CY),hl
D_FILL_ROW:
        ld a,(D_BITMAP)
        or a
        jr z,D_FILL_TEXT_ROW
        ld hl,(D_L)
        ld (D_CX),hl
        call D_RECT_ADDRESS
        push de
        ld hl,(D_R)
        ld de,(D_L)
        or a
        sbc hl,de
        inc hl
        ld b,h
        ld c,l
        pop de
        ld a,(D_FILL)
        call V_SPAN
        jr D_FILL_NEXT
D_FILL_TEXT_ROW:
        ld hl,(D_L)
        ld (D_CX),hl
D_FILL_COL:
        call D_RECT_ADDRESS
D_FILL_TEXT:
        ld a,32
        call D_WRITE_CELL
D_FILL_STEP:
        ld hl,(D_CX)
        ld de,(D_R)
        or a
        sbc hl,de
        jr z,D_FILL_NEXT
        ld hl,(D_CX)
        inc hl
        ld (D_CX),hl
        jr D_FILL_COL
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
D_RECT_ADDRESS:
        ld de,(D_CX)
        ld hl,(D_CY)
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
        ld a,(D_TOP)
        ld (D_SCROLL_LINE),a
        call D_SCROLL_METRICS
D_SCROLL_BEGIN:
        ld hl,(D_T)
        ld (D_CY),hl
D_SCROLL_ROW:
        ld a,(D_BITMAP)
        or a
        jr z,D_SCROLL_ROW_READY
        ld hl,(D_CY)
        ld de,(D_SCROLL_BOUNDARY)
        or a
        sbc hl,de
        jr c,D_SCROLL_ROW_READY
        ld a,(D_SCROLL_LINE)
        inc a
        ld (D_SCROLL_LINE),a
        call D_SCROLL_METRICS
D_SCROLL_ROW_READY:
        ld de,(D_L)
        ld hl,(D_CY)
        call D_ADDRESS
        ld (D_SCROLL_DEST),de
        ld hl,(D_CY)
        ld de,(D_SCROLL_H)
        add hl,de
        ld a,(D_BITMAP)
        or a
        jr z,D_SCROLL_SOURCE_READY
        ; Stretch the final scanline of a short source cell when the target
        ; cell is taller; never read a scanline from the following text row.
        ld de,(D_SCROLL_SOURCE_END)
        push hl
        or a
        sbc hl,de
        pop hl
        jr c,D_SCROLL_SOURCE_READY
        jr z,D_SCROLL_SOURCE_READY
        ex de,hl
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
        push de
        ld hl,(D_R)
        ld de,(D_L)
        or a
        sbc hl,de
        inc hl
        ld b,h
        ld c,l
        pop de
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
D_SCROLL_METRICS:
        ld a,(D_SCROLL_LINE)
        call D_ROW_Y
        push hl
        ld a,(D_SCROLL_LINE)
        inc a
        call D_ROW_Y
        ld (D_SCROLL_BOUNDARY),hl
        pop de
        or a
        sbc hl,de
        ld (D_SCROLL_H),hl
        ld a,(D_SCROLL_LINE)
        add a,2
        call D_ROW_Y
        dec hl
        ld (D_SCROLL_SOURCE_END),hl
        ret
; UDG definition: store an 8x8 BBC glyph expanded into the ZVB 8x12 font.
D_DEFINE:
        ld a,(D_PARAMS)
        cp 1
        ret z                 ; VDU 23,1 cursor visibility (no bitmap cursor)
        cp 32
        jp c,D_UNSUPPORTED
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
        ret
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
        ld h,DEV_STDOUT
        ld c,CMD_RESET_SCREEN
        BBC_SYSCALL(7)
        jp D_RESET_SEQUENCE
