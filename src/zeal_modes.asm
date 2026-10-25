; Native Zeal video modes. BBC selectors 3/6 retain text intent; incompatible
; BBC graphics selectors and deferred teletext are rejected before any I/O.
        PUBLIC D_MODE, D_MODE_NO, D_MASK, D_COLS, D_ROWS, Z_NATIVE_STATE
        PUBLIC Z_KIND, Z_MAX_X, Z_MAX_Y
        PUBLIC Z_NORMALIZE_COLOUR, Z_PALETTE, Z_PALETTE_ADDRESS
        PUBLIC Z_TEXT_CELL, Z_TEXT_COLOURS, Z_TILE_FONT, Z_BBC_COLOUR
        EXTERN D_ACTIVE, D_BITMAP, D_ERROR, D_UNSUPPORTED, EXTERR
        EXTERN D_SAVE, D_EXIT, D_RESET_SEQUENCE, D_WINDOWS, D_CLEAR
        EXTERN D_DEFAULT_COLOURS, D_LOAD_GLYPH, D_PAL_WORD
        EXTERN D_CHAR, D_GLYPH, D_BITS, D_X, D_FG, D_BG
        EXTERN D_VREAD, D_VWRITE, V_WRITE, V_SPAN, G_RESET

D_MODE_NO: defb 3
; Descriptor fields must remain contiguous (nine bytes).
D_MASK: defb 15
D_COLS: defb 80
D_ROWS: defb 40
Z_HW_MODE: defb 0
Z_KIND: defb 0                 ; 0=text, 1=bitmap, 2=8-bit tiles, 3=4-bit tiles
Z_MAX_X: defw 639
Z_MAX_Y: defw 479

D_MODE:
        ld c,a
        cp 3
        jr z,Z_MODE_80
        cp 6
        jr z,Z_MODE_40
        sub 8
        cp 6
        jp nc,Z_MODE_ERROR
        jr Z_MODE_INDEX
Z_MODE_80:
        ld a,6
        jr Z_MODE_INDEX
Z_MODE_40:
        ld a,7
Z_MODE_INDEX:
        push bc
        push af
        ld a,c
        cp 3
        jr z,Z_MODE_RESTORE
        cp 6
        jr nz,Z_MODE_SAVE
Z_MODE_RESTORE:
        call D_EXIT            ; restore the saved native font on returning to text
Z_MODE_SAVE:
        call D_SAVE
        pop af
        pop bc
        ld l,a
        ld h,0
        ld a,c
        ld (D_MODE_NO),a
        ld d,h
        ld e,l
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,de
        ld de,Z_MODES
        add hl,de
        ld de,D_MASK
        ld bc,9
        ldir
        xor a
        out (0x9d),a           ; keep initialization off screen
        ld a,(Z_HW_MODE)
        out (0x9c),a
        xor a
        out (0x8e),a           ; banked text controller
        out (0xa6),a           ; BASIC owns text cursor/scrolling
        out (0xa3),a
        out (0xa4),a
        ld c,0x94
        ld b,8
Z_MODE_SCROLL:
        out (c),a
        inc c
        djnz Z_MODE_SCROLL
        ld a,(Z_KIND)
        cp 1
        ld a,0
        jr nz,Z_MODE_BITMAP
        inc a
Z_MODE_BITMAP:
        ld (D_BITMAP),a
        ld a,1
        ld (D_ACTIVE),a
        call D_RESET_SEQUENCE
        call D_WINDOWS
        call G_RESET
        call D_DEFAULT_COLOURS
        ld a,(Z_KIND)
        or a
        jr z,Z_MODE_CLEAR
        cp 1
        jr nz,Z_MODE_TILES
        ld de,0
        ld bc,64000
        ld a,(D_MODE_NO)
        cp 9
        jr nz,Z_MODE_PIXELS
        ld bc,61440
Z_MODE_PIXELS:
        xor a
        call V_SPAN
        ld de,0xffff           ; bitmap border colour is outside drawable pixels
        xor a
        call V_WRITE
        jr Z_MODE_CLEAR
Z_MODE_TILES:
        call Z_INIT_TILES
Z_MODE_CLEAR:
        call D_CLEAR
        ld a,0x80
        out (0x9d),a
        ret
Z_MODE_ERROR:
        ld a,255
        call EXTERR
        defm "Unsupported display mode"
        defb 0

; mask, columns, rows, hardware mode, kind, maximum pixel X/Y.
Z_MODES:
        defb 255,40,16,3,1
        defw 319,199            ; MODE 8: 320x200 bitmap
        defb 255,32,20,2,1
        defw 255,239            ; MODE 9: 256x240 bitmap
        defb 255,20,15,5,2
        defw 319,239            ; MODE 10: 320x240 8-bit tilemap
        defb 255,40,30,4,2
        defw 639,479            ; MODE 11: 640x480 8-bit tilemap
        defb 15,20,15,7,3
        defw 319,239            ; MODE 12: 320x240 4-bit tilemap
        defb 15,40,30,6,3
        defw 639,479            ; MODE 13: 640x480 4-bit tilemap
Z_MODE_TEXT80:
        defb 15,80,40,0,0
        defw 639,479            ; BBC MODE 3: native 80x40 text
        defb 15,40,20,1,0
        defw 319,239            ; BBC MODE 6: native 40x20 text

; Keep BASIC metadata consistent with the OS screen even if exit cleanup
; later fails and returns to the BASIC prompt instead of terminating.
Z_NATIVE_STATE:
        ld hl,Z_MODE_TEXT80
        ld de,D_MASK
        ld bc,9
        ldir
        ld hl,Z_NATIVE_CURSOR
        ld de,D_X
        ld bc,8
        ldir
        ld a,3
        ld (D_MODE_NO),a
        ret
Z_NATIVE_CURSOR: defb 0,0,0,39,79,0,7,0

; Convert legacy text colour+128 into the common DE representation. Native
; Zeal modes accept 0..255 foreground and 256..511 background. D is validated
; by COLOUR_ARG; one-byte VDU colours are foreground-only in native graphics.
Z_NORMALIZE_COLOUR:
        ld a,(Z_KIND)
        or a
        ret nz
        ld a,d
        or a
        jp nz,D_ERROR
        ld a,e
        rlca
        and 1
        ld d,a
        res 7,e
        ret

Z_PALETTE_ADDRESS:
        add a,a
        ld e,a
        ld a,0x0e
        adc a,0
        ld d,a
        ret
Z_READ_COLOUR:
        call Z_PALETTE_ADDRESS
        call D_VREAD
        ld l,a
        inc de
        call D_VREAD
        ld h,a
        ret
Z_PALETTE:
        ld de,0x0e00
        ld b,0                 ; initialize all 256 palette entries
Z_PALETTE_LOOP:
        ld a,e
        srl a
        bit 0,d
        jr z,Z_PALETTE_INDEX
        or 0x80
Z_PALETTE_INDEX:
        push bc
        push de
        ld c,a
        ld a,(D_MASK)
        inc a
        ld a,c
        jr nz,Z_PALETTE_BBC
        call Z_RGB332
        jr Z_PALETTE_WRITE
Z_PALETTE_BBC:
        call Z_BBC_COLOUR
Z_PALETTE_WRITE:
        pop de
        pop bc
        call D_PAL_WORD
        inc de
        djnz Z_PALETTE_LOOP
        ld a,(Z_KIND)
        cp 2
        ret c
        jp Z_TEXT_COLOURS
; RGB332 -> RGB565, repeating high channel bits to preserve full intensity.
Z_RGB332:
        ld c,a
        and 0xe0
        ld b,a
        rrca
        rrca
        rrca
        and 0x18
        or b
        ld h,a
        ld a,c
        rrca
        rrca
        and 7
        or h
        ld h,a
        ld a,c
        and 0x1c
        rlca
        rlca
        rlca
        ld l,a
        ld a,c
        and 3
        ld e,a
        ld d,0
        push hl
        ld hl,Z_BLUE
        add hl,de
        ld a,(hl)
        pop hl
        or l
        ld l,a
        ret
Z_BLUE: defb 0,10,21,31
Z_BBC_COLOUR:
        ld hl,0
        rrca
        jr nc,Z_BBC_GREEN
        ld h,0xf8
Z_BBC_GREEN:
        rrca
        jr nc,Z_BBC_BLUE
        ld l,0xe0
        push af
        ld a,h
        or 7
        ld h,a
        pop af
Z_BBC_BLUE:
        rrca
        ret nc
        ld a,l
        or 31
        ld l,a
        ret

; Tile text reserves the final two colours of palette bank 0 and ASCII tiles
; 160..255. Rebind the selected colours to those stable font entries, so a
; subsequent background change does not lose the current foreground colour.
Z_TEXT_COLOURS:
        ld a,(D_FG)
        call Z_READ_COLOUR
        push hl
        ld a,(D_BG)
        call Z_READ_COLOUR
        push hl
        ld a,(D_MASK)
        call Z_PALETTE_ADDRESS
        pop hl
        call D_PAL_WORD
        ld a,(D_MASK)
        dec a
        call Z_PALETTE_ADDRESS
        pop hl
        call D_PAL_WORD
        ld a,(D_MASK)
        ld (D_BG),a
        dec a
        ld (D_FG),a
        ret
Z_TEXT_CELL:
        cp 32
        jp c,D_UNSUPPORTED
        cp 128
        jp nc,D_UNSUPPORTED
        add a,128
        call D_VWRITE
        ld a,(Z_KIND)
        cp 3
        ret nz
        ld a,d
        add a,0x10
        ld d,a
        xor a                  ; 4-bit tile attributes: bank 0, no flipping
        jp D_VWRITE
Z_INIT_TILES:
        ld de,0
        ld bc,3200
        call Z_ZERO_CONTROL
        ld de,0x1000
        ld bc,3200
        call Z_ZERO_CONTROL
        ld de,0x2800
        ld bc,1024
        call Z_ZERO_CONTROL    ; hide all sprites (zero positions are off-screen)
        ld de,0
        ld bc,256
        xor a
        call V_SPAN            ; tile 0 is transparent/empty
        jp Z_TILE_FONT
Z_ZERO_CONTROL:
        xor a
        call D_VWRITE
        inc de
        dec bc
        ld a,b
        or c
        jr nz,Z_ZERO_CONTROL
        ret
Z_TILE_FONT:
        ld a,32
Z_FONT_CHARACTER:
        ld (D_CHAR),a
        call D_LOAD_GLYPH
        ld a,(D_CHAR)
        add a,128
        ld d,a
        ld e,0
        ld a,(Z_KIND)
        cp 3
        jr nz,Z_FONT_START
        srl d
        rr e                   ; 4-bit tiles occupy 128 rather than 256 bytes
Z_FONT_START:
        ld hl,D_GLYPH
        ld b,16
Z_FONT_ROW:
        ld a,b
        cp 5
        ld a,0
        jr c,Z_FONT_BITS
        ld a,(hl)
        inc hl
Z_FONT_BITS:
        ld (D_BITS),a
        push bc
        ld c,16
Z_FONT_COLUMN:
        call Z_FONT_PIXEL
        dec c
        ld b,a
        ld a,(Z_KIND)
        cp 3
        ld a,b
        jr nz,Z_FONT_WRITE
        rlca
        rlca
        rlca
        rlca
        ld b,a
        call Z_FONT_PIXEL
        or b
        dec c
Z_FONT_WRITE:
        call V_WRITE
        inc de
        ld a,c
        or a
        jr nz,Z_FONT_COLUMN
        pop bc
        djnz Z_FONT_ROW
        ld a,(D_CHAR)
        inc a
        cp 128
        jr c,Z_FONT_CHARACTER
        ret
Z_FONT_PIXEL:
        ld a,c
        cp 9
        ld a,(D_BITS)
        jr nc,Z_FONT_ROTATE
        xor a                  ; right half of the 16x16 cell is padding
Z_FONT_ROTATE:
        rlca
        ld (D_BITS),a
        ld a,(D_MASK)
        ret nc
        dec a
        ret
