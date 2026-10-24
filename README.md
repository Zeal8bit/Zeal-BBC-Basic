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

## Loading programs

`LOAD` reads tokenized BASIC programs. The Zeal extension `LOAD$` reads a numbered
ASCII source file and tokenizes each line as it is read:

```basic
LOAD$ "H:/examples/gfx/bounce.bas"
RUN
```

The filename extension does not matter: `LOAD$ "H:/something.bbcbas"` works too.
The filename may be any BASIC string expression. Importing stores the program;
it does not execute its statements. Use `RUN` afterwards, or `LIST` to inspect it.
`SAVE "H:/bounce.bbc"` saves the imported program in the normal tokenized format.

Source files must contain nonempty numbered statements with unique, ascending
line numbers from 1 to 65535. Blank lines are ignored. LF, CRLF and CR endings,
and a final line without a newline, are accepted. Spaces and tabs may indent a
line or separate its number from its first statement. Statement contents use the
same tokenizer as keyboard entry, including uppercase BASIC keywords; tabs
within statements are kept literal. Files must be ASCII without a byte-order
mark. A source line may contain at most 255 bytes excluding its line ending;
the interpreter's existing tokenized-line limit also applies.

An open failure preserves the existing program. Once the file opens, importing
replaces the program and clears its variables. Invalid input, Escape, insufficient
memory or a later file error discards the incomplete import and reports the
source-file line reached. Duplicate/out-of-order numbers, bare line numbers and
unnumbered commands are rejected. The importer streams through the existing
line buffers; it does not load the entire source file into a temporary buffer.

Command-line filename autorun still expects a tokenized program; `LOAD$` is an
interactive command. See [examples/gfx](examples/gfx/README.md) for source files
and ready-to-load tokenized copies.

## Keyboard and ZShell

BASIC selects cooked, blocking keyboard input for its command prompt and INPUT,
and raw input for GET and Escape handling. ZShell's inherited keyboard mode is
changed explicitly. Initial `HIMEM` is `&F700`: the private interrupt-vector page
above it keeps arithmetic registers safe while keyboard interrupts remain enabled.
`PAGE` is aligned above the interpreter and its display workspace. See [tests/README.md](tests/README.md) for the real-kernel
ZShell verification command; the normal `zshell/emu` kernel also works headlessly.

## Timing and nonblocking input

`TIME` returns a 32-bit centisecond counter; `TIME=expression` sets the local
BASIC counter without resetting the OS clock. `INKEY$(0)` returns one pending
keyboard character or an empty string immediately. `INKEY(0)` exposes the same
operation as a character code or -1. Both share GET's existing translated-key
queue and Escape handling. Positive timeouts and negative key-state queries
are not implemented and report error 255, `Only INKEY(0) supported`.

Timing uses the native ZVB timer peripheral (bank 6) at one millisecond per
tick, with interrupts disabled for that peripheral. Its divider uses the ZVB's
50MHz clock. The OS's optional vblank counter is not required. BASIC owns this
timer while running; called machine code must not reconfigure it concurrently.
Timer access restores the bank used by text and other ZVB peripherals.

The adapter extends the 16-bit hardware counter at execution/key polls and
`TIME` reads, retaining fractional milliseconds and handling normal wraps.
It must sample at least once per **65.536 seconds**: a longer blocking OS read,
or machine code that prevents sampling, loses complete hardware-counter wraps.
Normal interpreted execution and the Lander game sample frequently. This is
not an independent interrupt-driven clock and does not implement `TIME$`.

An original BBC graphics game with a small, documented Zeal patch is available
in [examples/gfx/lander](examples/gfx/lander/README.md).

## BBC graphics and VDU

The display layer implements BBC BASIC commands through the ZVB's existing
video hardware. It does not emulate a TMS chip. Graphics requires ZVB firmware
1.x or later with its 320x200 indexed bitmap mode; the native emulator supports
this mode. Physical-board operation has not yet been verified.

| MODE | Native display | Text grid | Colour format |
| --- | --- | --- | --- |
| 3 | 640x480 text | 80x40 | 16 text indices; BBC MODE 3 has 25 rows |
| 6 | 320x240 text | 40x20 | 16 text indices; BBC MODE 6 has 25 rows |
| 8 | 320x200 bitmap | 40x16 | 8-bit indexed, 256 colours |
| 9 | 256x240 bitmap | 32x20 | 8-bit indexed, 256 colours |
| 10 | 320x240 tilemap | 20x15 | 8-bit tiles |
| 11 | 640x480 tilemap | 40x30 | 8-bit tiles |
| 12 | 320x240 tilemap | 20x15 | 4-bit tiles |
| 13 | 640x480 tilemap | 40x30 | 4-bit tiles |

BBC graphics modes **0, 1, 2, 4, 5** are unsupported and raise error 255;
**MODE 7** is reserved for deferred teletext. They are not approximate aliases
for Zeal graphics. `MODE 3` restores native 80x40 text and `MODE 6` selects native
40x20 text without exiting BASIC. `VDU 22,n` selects the same modes.

See [the mode reference](docs/video-modes.md) for all BBC differences, coordinate
and colour conventions, tile-font reservations, and examples of mode selection.

The startup console retains Zeal OS text output until a mode or application-owned
text window/palette is selected. `MODE` clears and resets the display. Program
completion leaves it visible; `*BYE` restores the OS text display, default palette,
and original font. BASIC's program start (`PAGE`) is now calculated from the
interpreter and workspace size, rather than fixed at `&8000`; do not hard-code it.
Workspace is reserved at startup above the loaded image, without zero-filled
buffers in the binary. The build checks this separation and available BASIC RAM,
and reports progress against the 16 KiB executable-size goal. The goal is informational while the
complete port exceeds one page; the original interpreter and assembler are
retained.

Supported graphics commands are `GCOL action,colour`, `MOVE`, `DRAW`,
`PLOT operation,x,y`, `CLG`, and `POINT(x,y)`. Coordinates use BBC's 1280x1024
logical space, bottom-left origin, signed relative plotting, and VDU-controlled
origin/window in bitmap modes 8/9. `POINT` returns the stored logical colour, or -1 outside the
screen or graphics window. GCOL actions 0–4 implement replace, OR, AND, XOR, and
invert. Zeal graphics modes use colour indices 0-255 for foreground and
256-511 for background; modes 3/6 retain the BBC colour+128 background convention.
Logical coordinates are scaled to the selected native bitmap. Original BBC pixel grids,
aspect ratios, and timing are approximated; high-resolution details can merge.

PLOT families 0–63 (solid/dotted lines with endpoint omission), 64–71 (points),
72–79 (horizontal fill bounded by non-background pixels), 80–87 (filled triangles),
and 96–103 (filled rectangles) are supported. Low bits retain BBC relative/absolute,
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

Bitmap text uses native 8x12 character cells. Tilemap text uses reserved 16x16
font tiles. Graphics text
(VDU 5) uses transparent backgrounds, GCOL, and the graphics window. Line input
after MODE uses blocking raw reads, translated keys, and display-aware echo,
including backspace. Reads return to nonblocking mode before rendering.
Errors discard partial VDU commands and return to ordinary text output in the
current mode. Long drawing operations continue to poll for Escape.

Mode 7, flashing colours, circles/ellipses/arcs, general flood fill, BBC screen
memory/MOS/6502 compatibility, sprites, and sound are outside this milestone.
Eight-bit graphics use a full RGB332 default palette. Tilemap modes reserve
96 font tiles and two palette entries for visible BASIC text and input; see the
mode reference before uploading application assets.
Try `examples/graphics.bas` and `examples/graphics-modes.bas` as numbered source.
For small, playful demos, see [examples/gfx](examples/gfx/README.md): rainbow
string art, fireworks, an XOR bouncing box and native tilemap text.
