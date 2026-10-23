# Small Zeal graphics demos

Each demo includes a numbered `.bas` source listing and a loadable, tokenized
`.bbc` copy. The `.bbc` files were entered and saved by BBC BASIC running in the
native emulator's headless console, then loaded and run again for verification.

With this repository's root directory exposed as HostFS, start BASIC and enter:

```basic
LOAD "H:/examples/gfx/rainbow.bbc"
RUN
```

Change the filename to choose another demo. If your HostFS root is the
`examples/gfx` directory itself, use `LOAD "H:/rainbow.bbc"` instead.

To load the readable source directly, use the Zeal `LOAD$` extension:

```basic
LOAD$ "H:/examples/gfx/bounce.bas"
RUN
```

`LOAD$` tokenizes each numbered source line while reading the file; its filename
extension is unrestricted. Ordinary `LOAD` and filename autorun expect `.bbc`
tokenized contents. To edit a demo, load either version and replace numbered
lines from the BASIC prompt, then use `SAVE` to write a tokenized copy. The
native emulator does not support clipboard paste into the emulated screen.

| Source | Loadable program | Mode | Try it for |
| --- | --- | --- | --- |
| [rainbow.bas](rainbow.bas) | [rainbow.bbc](rainbow.bbc) | 8: 320x200 bitmap | A colourful string-art fan using `MOVE`, `DRAW` and `GCOL`. |
| [fireworks.bas](fireworks.bas) | [fireworks.bbc](fireworks.bbc) | 8: 320x200 bitmap | Five bursts at random positions. Press a key for each burst, then once more to finish. |
| [bounce.bas](bounce.bas) | [bounce.bbc](bounce.bbc) | 9: 256x240 bitmap | A bouncing filled box. `GCOL 3,7` uses XOR: drawing twice erases the box. |
| [tileparty.bas](tileparty.bas) | [tileparty.bbc](tileparty.bbc) | 10, 11, 12, 13: native tilemaps | An ASCII party on each tilemap display. Press a key to advance. |

Every demo finishes in Zeal's native 80x40 text mode (`MODE 3`). Press Escape
to interrupt a demo, then enter `MODE 3` to restore text yourself.

Bitmap demos use BBC logical coordinates: `(0,0)` is the bottom left and the
screen spans 1280x1024 logical units in both bitmap modes. Text `TAB` coordinates
start at the top left. Modes 8 and 9 have 40x16 and 32x20 text grids respectively.
The bitmap demos explicitly map colour indices 1-7 to familiar BBC colours;
the default eight-bit palette has a different arrangement.

For a quick experiment, change the fan's `STEP 32`, the fireworks' radius `180`,
or the box's `DX%` and `DY%`. The bounce delay is a simple counted loop on line 90;
increase `80` for slower movement. Its speed depends on the machine/emulator.

The tilemap demo uses only ASCII text, with a layout that fits the smallest
20x15 grid. `COLOUR` changes all existing tilemap console text at once, so it
recolours the pattern after printing it. In Zeal modes, `COLOUR 256+index`
selects the background: `259` means index 3, and `260` means index 4. The demo
uses the default RGB332 palette in eight-bit modes and BBC colours in four-bit
modes. Tilemap modes do not support `DRAW`, `PLOT` or `CLG`; this example uses
the reserved console font tiles rather than uploading custom tile artwork.

See the [mode reference](../../docs/video-modes.md) for supported modes, palette
conventions and the differences from BBC Micro displays.
