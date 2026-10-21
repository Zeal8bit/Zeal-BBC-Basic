# BBC Basic for Zeal 8-bit Computer

This is a modified source code based on [BBC BASIC+ for Z80](https://github.com/jblang/bbcbasic-z80) by (J.B. Langston)[@jblang],
originally modified from the [BBC BASIC (Z80)](http://www.bbcbasic.co.uk/bbcbasic/z80basic.html) by R.T. Russell, which is released under the [zlib](COPYING) licese at the request of David Given. David published the sources as part of his [cpmish](https://github.com/davidgiven/cpmish) project.

The original sources released by R.T. Russell are in the initial commit.  The following modifications have been made:

- Modified sources to assemble with [z88dk](https://github.com/z88dk/z88dk)'s z80asm
- Fixed a [bug](https://github.com/davidgiven/cpmish/issues/20) that causes the RUN command to hang under emulators.
- Moved hardware-specific functions from patch.asm to hardware.asm.
- Implemented CLS, TAB, and COLOUR using ANSI escape codes
- Added a Makefile and this README
- Reformatted the source with [z80-macroasm](https://marketplace.visualstudio.com/items?itemName=mborik.z80-macroasm) for VSCode

## Build Instructions

Use the [Zeal development environment](https://github.com/Zeal8bit/zeal-dev-environment) to build `build/bbcbasic.bin`:

```sh
zde cmake
```

## Operating-system commands

`*BYE` (or `OSCLI "BYE"`) closes BASIC-owned files and exits to Zeal OS.
`CPM` is retained as an exit alias. Command names are case-insensitive; leading
and trailing spaces and tabs are accepted. Empty commands and `*|` comments
return to BASIC. Other commands, including the original CP/M disk commands,
raise trappable error 254, `Bad command`.

## Keyboard and ZShell

BASIC selects cooked, blocking keyboard input for its command prompt and INPUT,
and raw input for GET and Escape handling. ZShell's inherited keyboard mode is
changed explicitly. Initial `HIMEM` is `&F700`: the private interrupt-vector page
above it keeps arithmetic registers safe while keyboard interrupts remain enabled.
`PAGE` is aligned above the interpreter and its display workspace. See [tests/README.md](tests/README.md) for the real-kernel
ZShell verification command; the normal `zshell/emu` kernel also works headlessly.

## BBC graphics and VDU

The display layer implements BBC BASIC commands through the ZVB's existing
video hardware. It does not emulate a TMS chip. Graphics requires ZVB firmware
1.x or later with its 320x200 indexed bitmap mode; the native emulator supports
this mode. Physical-board operation has not yet been verified.

| BBC MODE | Text grid | Logical colours | ZVB rendering |
| --- | --- | --- | --- |
| 0 | 80x32 | 2 | 320x200 bitmap |
| 1 | 40x32 | 4 | 320x200 bitmap |
| 2 | 20x32 | 16 | 320x200 bitmap |
| 3 | 80x25 | 2 | 640x480 text, software window |
| 4 | 40x32 | 2 | 320x200 bitmap |
| 5 | 20x32 | 4 | 320x200 bitmap |
| 6 | 40x25 | 2 | 640x480 text, 40-column software window |

The startup console retains Zeal OS text output until a mode or application-owned
text window/palette is selected. `MODE` clears and resets the display. Program
completion leaves it visible; `*BYE` restores the OS text display, default palette,
and original font. BASIC's program start (`PAGE`) is now calculated from the
interpreter and workspace size, rather than fixed at `&8000`; do not hard-code it.
Workspace is reserved at startup above the loaded image, without zero-filled
buffers in the binary. The build checks this separation and available BASIC RAM.

Supported graphics commands are `GCOL action,colour`, `MOVE`, `DRAW`,
`PLOT operation,x,y`, `CLG`, and `POINT(x,y)`. Coordinates use BBC's 1280x1024
logical space, bottom-left origin, signed relative plotting, and VDU-controlled
origin/window. `POINT` returns the stored logical colour, or -1 outside the
screen or graphics window. GCOL actions 0–4 implement replace, OR, AND, XOR, and
invert; colour+128 selects the graphics background. Logical pixels are mapped to
the ZVB raster: x/4 and 199-floor(floor(y/4)*25/32). Original BBC pixel grids,
aspect ratios, and timing are approximated; high-resolution details can merge.

PLOT families 0–63 (solid/dotted lines with endpoint omission), 64–71 (points),
72–79 (horizontal fill bounded by foreground), 80–87 (filled triangles), and
96–103 (filled rectangles) are supported. Low bits retain BBC relative/absolute,
move, foreground, inverse, and background meanings. Other families raise trappable
error 255, `Unsupported display operation`.

`VDU` and `PRINT CHR$()` share a parameter decoder, including parameters split
across statements. Supported controls include text/graphics text selection (4/5),
output enable/disable (6/21), cursor movement (8–11), clear/return (12/13), graphics
clear (16), text/graphics colours (17/18), palette definition/reset (19/20), mode
(22), 8x8 character definition (23), graphics window (24), plotting (25), window
reset (26), text window (28), origin (29), home (30), and cursor positioning (31).
`CLS`, `TAB`, `POS`, and `VPOS` share the same text state. Text window coordinates
are relative for TAB/POS/VPOS, and window bounds are inclusive. Palette command
19 accepts physical colours 0–7 or extended RGB form `VDU 19,logical,16,r,g,b`.
VDU 23,1 is accepted; display-owned modes currently have no visible cursor. Printer controls are consumed
without output; bell and paged-mode-off are no-ops. Paged-mode-on and unsupported
VDU 23 subcommands raise error 255.

Bitmap text samples the board's font into 4-, 8-, or 16-pixel-wide cells and
6/7-pixel-high rows; 80-column text is necessarily compressed. Graphics text
(VDU 5) uses transparent backgrounds, GCOL, and the graphics window. Line input
after MODE uses blocking raw reads, translated keys, and display-aware echo,
including backspace. Reads return to nonblocking mode before rendering.
Errors discard partial VDU commands and return to ordinary text output in the
current mode. Long drawing operations continue to poll for Escape.

Mode 7, flashing colours, circles/ellipses/arcs, general flood fill, BBC screen
memory/MOS/6502 compatibility, sprites, and sound are outside this milestone.
For 16-colour modes the upper eight physical palette entries initially repeat
the lower eight without flashing; all sixteen logical entries are programmable.
Try `examples/graphics.bas` and `examples/graphics-modes.bas` as numbered source.
