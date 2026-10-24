# Lunar Lander: original and Zeal OS versions

Jim Murray's Lunar Lander, from chapter 29 of the *BBC Microcomputer System
User Guide*, printed pages 151-154. The reference used here is the
[remastered BBC B+ edition](https://basic.barrybks.co.uk/downloads/manuals/third-party/BBC_B%2B_User_Guide_v5.pdf),
PDF pages 165-168. Credit and copyright remain with the original author and
publisher; this is a historical listing, not a newly authored demo.

- [original.bas](original.bas) transcribes the printed game. Wrapped statements
  are joined onto their numbered lines; typesetting indentation is omitted.
  It retains the missing comma printed on line 8015 and the original BBC modes,
  sound and OS commands. It is a comparison reference, not the Zeal version.
- [zos.bas](zos.bas) contains the small changes listed below. The flight
  equations, fuel consumption, numeric thrust controls and landing criteria
  remain unchanged.

With the repository root shared as HostFS:

```basic
LOAD$ "H:/examples/gfx/lander/zos.bas"
RUN
```

Use the number keys **1-9** to fire the rocket; larger numbers burn more fuel.
No key means no thrust. Zeal's native keyboard repeat applies while holding a
key; the original BBC repeat-setting calls are disabled. The dashboard shows
time, height, speed, fuel and the current burn rate. Land below about 15 mph;
the original test is `speed<=0.004` miles/second (14.4 mph). Escape interrupts
the game. It leaves the bitmap visible; enter `MODE 3` to return to native text.

## The complete patch

Only 11 existing numbered lines differ; none are renumbered:

| Lines | Change | Reason |
| --- | --- | --- |
| 10 | `MODE5` to `MODE9` | Use the native 256x240 bitmap and 32x20 text grid. |
| 70 | Explicit palette entries 1 red, 2 green, 3 white | Preserve the game's colours despite the RGB332 default palette. |
| 80 | Text-window bottom 20 to 19 | Native MODE 9 text has rows 0-19. |
| 110, 245 | Comment out repeat-setting `*FX` commands | Zeal's native keyboard repeat applies. |
| 185, 247 | Replace `*FX 15,1` with `REPEAT UNTIL INKEY$(0)=""` | Preserve the original input-buffer flush without BBC OS commands. |
| 5020, 6020, 6025 | Comment out `SOUND` | Sound is not implemented; crash graphics and the success branch still execute. |
| 8015 | Insert the missing comma in `VDU10,9,127` | Correct the printed listing's syntax error. |

Compare the two `.bas` files directly to see every change. The ship uses the
same custom glyph definitions, expanded by the port into native 8x12 cells.
Its appearance and text density differ from BBC MODE 5; no BBC pixel grid is
emulated. The original game has crash graphics and a success fanfare, but no
separate written win/lose message; the ZOS version's fanfare is silent.

## Verification

The real-kernel test loads `zos.bas` with `LOAD$` and runs the actual listing in
the headless native emulator. It first allows an unpowered crash, checking the
crash graphics loop completes without consuming fuel. It then plays using
ordinary PS/2 `9` keypresses and checks a successful landing, remaining fuel and
completion of the original fanfare branch. The controller only observes game
variables; it does not alter the listing, clock or flight state.

The controlled test flight crosses the hardware timer's 65.536-second wrap and
must land below 14.4 mph with fuel remaining. Its precise score and duration
depend on interpreter execution time; this is not a physical-hardware result.
Graphics regression checks separately verify that the game's `VDU 127` erases
old rocket cells without leaving a vertical trail or clearing the current ship.

```sh
python3 tests/lander_integration.py \
  --rom /path/to/os_with_romdisk.img --kernel-map /path/to/os.map
```

See the main README for `TIME` and `INKEY$(0)` support and clock limitations.
