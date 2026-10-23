# Zeal display modes and BBC compatibility

`MODE n` and `VDU 22,n` select the same display. A successful mode change clears
its display, resets colours, origin, windows and cursor position, and keeps
BASIC running. `*BYE` restores the OS console and exits BASIC.

The startup display is the inherited Zeal OS console, normally native 80x40
text. MODE 3 and MODE 6 restore the original native font, then let BASIC own
VDU processing, text windows and scrolling on the selected native text screen.
Display-owned modes currently hide the hardware cursor.

## Implemented modes

The BASIC selectors below are not ZVB hardware register values.

| BASIC MODE | ZVB hardware mode | Native display | Text grid | Colour format |
| --- | --- | --- | --- | --- |
| **3** | 0 | 640x480 text | **80x40** | 16 foreground/background indices |
| **6** | 1 | 320x240 text | **40x20** | 16 foreground/background indices |
| **8** | 3 | 320x200 bitmap | 40x16 | 8-bit indexed pixels, 256 colours |
| **9** | 2 | 256x240 bitmap | 32x20 | 8-bit indexed pixels, 256 colours |
| **10** | 5 | 320x240 tilemap | 20x15 | 8-bit indexed tiles |
| **11** | 4 | 640x480 tilemap | 40x30 | 8-bit indexed tiles |
| **12** | 7 | 320x240 tilemap | 20x15 | 4-bit tiles, 16 colours per palette bank |
| **13** | 6 | 640x480 tilemap | 40x30 | 4-bit tiles, 16 colours per palette bank |

Bitmap and native text modes use the native 8x12 font. Tilemap text uses one
16x16 tile per character, containing the native 8x12 glyph and padding. No BBC
80/40/20-column bitmap font sampling or 6/7-pixel row emulation is performed.
MODE 8 has eight drawable pixel rows below its 16 complete text rows. `CLS`
clears the text window; `CLG` clears the graphics window, including those rows.

ZVB bitmap modes are always 8-bit indexed colour. MODE 8's 320x200 pixels are
shown inside a 320x240 output with 20 border lines above and below; borders are
not additional drawable pixels. MODE 9 provides 256x240 drawable pixels.

## BBC selectors and compatibility differences

BBC selectors keep their established purpose or fail explicitly; they are not
aliases for unrelated native graphics modes.

| BBC MODE | BBC Micro display | This port |
| --- | --- | --- |
| 0 | 640x256, 2 colours; 80x32 text | Unsupported: error 255 |
| 1 | 320x256, 4 colours; 40x32 text | Unsupported: error 255 |
| 2 | 160x256, 16 colours; 20x32 text | Unsupported: error 255 |
| 3 | 80x25 text | Native **80x40** text: 15 extra rows |
| 4 | 320x256, 2 colours; 40x32 text | Unsupported: error 255 |
| 5 | 160x256, 4 colours; 20x32 text | Unsupported: error 255 |
| 6 | 40x25 text | Native **40x20** text: five fewer rows |
| 7 | 40x25 teletext | Reserved; teletext deferred: error 255 |

Other undefined selectors also raise error 255, `Unsupported display mode`.
Validation happens before the display or saved font is changed. MODE arguments
must be unsigned bytes; out-of-range values do not wrap into another mode.

### MODE 3: standard 80-column text

`MODE 3` and `VDU 22,3` restore Zeal's native 80x40 text screen while remaining
in BASIC. Existing BBC MODE 3 text coordinates fit, but automatic scrolling
occurs after 40 rows rather than 25. Programs requiring a 25-row window can use
`VDU 28,0,24,79,0`. `VDU 26` restores the full native window.

### MODE 6: native 40-column text

`MODE 6` and `VDU 22,6` select actual 320x240 text hardware, not a 40-column
window in the 80-column display. Full-screen columns are 0-39 and rows 0-19.
Printing past the bottom scrolls the 20-row screen. `TAB` or a text window
requesting BBC rows 20-24 raises error 255; no hidden rows or smaller font are
provided. Games with fixed 25-row MODE 6 layouts need adjustment.

Native text modes support `PRINT`, `CLS`, `TAB`, `POS`, `VPOS`, character
definitions and VDU text windows. `DRAW`, `PLOT`, `POINT`, `CLG` and graphics
text (`VDU 5`) require a bitmap mode. Original BBC games needing modes
0/1/2/4/5 must be ported explicitly to MODE 8 or MODE 9; changing MODE alone
may not fix their text layouts, screen-memory assumptions or machine code.

## Bitmap coordinates and colours

Modes 8 and 9 retain BBC's signed 1280x1024 logical coordinate space, graphics
origin, clipping windows, relative plotting, GCOL actions and plot history.
The coordinate conversion is small and runs when coordinates are transformed,
not for every rasterized pixel. Logical origin (0,0) is at the bottom left.

- MODE 8: `pixel_x = floor(x/4)` and
  `pixel_y = 199 - floor(floor(y/4)*25/32)`.
- MODE 9: `pixel_x = floor(x/5)` and
  `pixel_y = 239 - floor(floor(y/4)*15/16)`.

Thus the logical screen fits each native bitmap, with reduced detail. These
modes do not reproduce BBC pixel grids, aspect ratios, screen RAM or timing.
MODE 8 is 56 pixel rows shorter than the BBC's 256-row bitmap modes; MODE 9 is
16 rows shorter. Neither native bitmap preserves BBC MODE 0's 640-pixel width.

`GCOL action,colour` implements replace (0), OR (1), AND (2), XOR (3) and invert
(4). `POINT(x,y)` returns the stored unsigned logical index, including 128-255,
or -1 outside the graphics window. `MOVE`, `DRAW`, `PLOT`, `CLG` and transparent
bitmap graphics text share the same pixel representation.

In **Zeal modes 8-13**, colour arguments use:

- **0-255**: foreground index.
- **256-511**: background index (`256 + index`).

For example, `GCOL 0,200` draws with index 200; `GCOL 0,456` selects background
index 200 for `CLG`. `COLOUR` uses the same foreground/background convention
for text. Four-bit tile text masks the selected index to palette bank 0's
0-15 range. GCOL does not enable pixel drawing in a tilemap mode.

In **BBC text selectors 3 and 6**, traditional `COLOUR 128+index` selects the
background. This exception preserves ordinary BBC text colour syntax. The
native text palette exposes 16 indices; flashing colours are not emulated.

VDU 17/18 carry a one-byte colour, so they select foreground indices 0-255 in
Zeal graphics modes. Use `COLOUR`/`GCOL` for their extended background arguments.
In modes 3/6, VDU 17/18 retain the traditional byte background flag.

Eight-bit modes start with an RGB332 palette expanded to RGB565. Native text
and four-bit modes repeat the eight non-flashing BBC physical colours across
the 256 hardware entries. `VDU 20` resets the palette and text/graphics colours.
`VDU 19,index,physical,0,0,0` maps BBC physical colours 0-7, while
`VDU 19,index,16,r,g,b` supplies RGB888. All 256 hardware palette entries are
programmable in Zeal graphics modes, including the 16 banks of a 4-bit tilemap.

## Native tilemaps and the BASIC console

Modes 10-13 are native tilemap surfaces, not emulated pixel framebuffers.
`DRAW`, `PLOT`, `POINT`, `CLG` and graphics text raise error 255 there. Pixel
plotting is deliberately not translated into dynamically allocated tiles.

BASIC reserves space for a visible prompt, `PRINT`, `INPUT`, `GET`, text-window
scrolling and `CLS`. The console uses background layer 0 and palette bank 0.

| Resource | 8-bit tilemaps | 4-bit tilemaps |
| --- | --- | --- |
| Font tile IDs | **160-255** | **160-255**, lower tileset bank |
| Font tileset byte offsets | **&A000-&FFFF** | **&5000-&7FFF** |
| Font palette entries | **254 foreground, 255 background** | **14 foreground, 15 background** |
| Initial text grid | 20x15 or 40x30 | 20x15 or 40x30 |

ASCII 32-127 corresponds to font tile ID `character + 128`. Printable ASCII
is supported; other character codes raise error 255. VDU 23 definitions for
ASCII characters refresh the reserved font tiles. Bitmap/native text modes
also support the higher character codes of the native font.

Tilemap `COLOUR` changes the two reserved font palette entries, so it changes
all existing console text, not just subsequently printed characters. The
remaining palette entries and nonreserved tiles belong to the application.
Applications must preserve the font tile ranges and reserved palette entries
while using BASIC text. In 8-bit modes, keep tile 0 transparent while unused
foreground-layer cells still reference it; otherwise that layer can cover the
console. Foreground layer graphics or sprites may cover console
text; applications must leave the console area visible when interaction is
required, or switch back to MODE 3/6 for text interaction.

Selecting a tilemap mode clears both 80x40 tilemap storage planes, makes tile 0
empty, hides sprites and uploads the reserved font. `CLS` clears the current
text window to the space glyph; it does not erase application tileset data.
The existing ZVB uses tilemap planes at physical &100000 and &101000 and a
64KB tileset at &110000. Four-bit mode interprets the second plane as tile
attributes; eight-bit mode uses it as a foreground layer. Native tile/sprite
uploads can be performed by machine-code routines called from BASIC; dedicated
BASIC tile/sprite loading keywords are not added by this mode-selection change.

## Implementation and validation

Mode selection, hardware setup, descriptors, palette defaults and tile-font
initialization live in `src/zeal_modes.asm`. Platform adapters and MMU-safe
video access live in `src/zeal_video.asm`; Zeal runtime buffers live in
`src/zeal_workspace.asm`. The inherited `src/hardware.asm` is not built.
No new mode code is embedded into the original interpreter modules.

The old approximate BBC graphics aliases, sampled bitmap text widths/heights
and variable-height scrolling implementation have been removed. Regression
tests cover the mode contract, native geometry, complete palettes, upper colour
indices, text windows, mode changes, native font restoration and tile-font
storage. Real-kernel tests exercise keyboard input and text in all four tilemap
modes. Physical-hardware validation remains separate.

Hardware reference: [ZVB video modes](https://zeal8bit.com/docs/zvb/en/video_modes/).
