; BBC TIME uses the ZVB 50MHz timer, independent of the stopped ZOS vblank clock.
; Extend its 16-bit millisecond counter by sampling at execution/key polls.
; Complete counter periods are lost while BASIC is blocked in an OS call
; for more than 65.536 seconds; document that native-clock limitation.
        PUBLIC GETIME, PUTIME, Z_TIME_INIT, Z_TIME_REFRESH
        EXTERN TIME_PREVIOUS, TIME_VALUE, TIME_FRACTION

Z_TIME_INIT:
        di
        in a,(0x8e)
        push af
        ld a,6
        out (0x8e),a
        ld a,0x4f              ; divider 49999: one tick per millisecond
        out (0xa1),a
        ld a,0xc3
        out (0xa2),a
        ld a,255
        out (0xa3),a
        out (0xa4),a
        ld a,0xe1              ; down-counter, auto-reload FFFF, load/start, no IRQ
        out (0xa0),a
        pop af
        out (0x8e),a
        ei
        xor a
        ld (TIME_FRACTION),a
        ld hl,0
        ld (TIME_PREVIOUS),hl
        ld (TIME_VALUE),hl
        ld (TIME_VALUE+2),hl
        ret

GETIME:
        push bc
        call Z_TIME_REFRESH
        ld hl,(TIME_VALUE)
        ld de,(TIME_VALUE+2)
        pop bc
        ret
PUTIME:
        push de
        push hl
        push bc
        call Z_TIME_REFRESH
        pop bc
        pop hl
        pop de
        ld (TIME_VALUE),hl
        ld (TIME_VALUE+2),de
        xor a
        ld (TIME_FRACTION),a
        ret

Z_TIME_REFRESH:
        di
        in a,(0x8e)
        push af
        ld a,6
        out (0x8e),a
        in a,(0xa5)            ; low-byte read latches high byte
        cpl
        ld l,a
        in a,(0xa6)
        cpl
        ld h,a
        pop af
        out (0x8e),a
        ei
        ld de,(TIME_PREVIOUS)
        ld (TIME_PREVIOUS),hl
        or a
        sbc hl,de              ; unsigned elapsed milliseconds, including wrap
        ld c,0
        ld b,16
TIME_DIV10:
        add hl,hl
        rl c
        ld a,c
        cp 10
        jr c,TIME_DIV_NEXT
        sub 10
        ld c,a
        inc l
TIME_DIV_NEXT:
        djnz TIME_DIV10
        ld a,(TIME_FRACTION)
        add a,c
        cp 10
        jr c,TIME_REMAINDER
        sub 10
        inc hl
TIME_REMAINDER:
        ld (TIME_FRACTION),a
        ld de,(TIME_VALUE)
        add hl,de
        ld (TIME_VALUE),hl
        ret nc
        ld hl,(TIME_VALUE+2)
        inc hl
        ld (TIME_VALUE+2),hl
        ret
