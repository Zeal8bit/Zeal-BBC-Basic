# Adapter regression tests

Build BBC BASIC with the Zeal development environment, then run:

```sh
python3 tests/run.py --build-dir build
```

The runner needs a host C compiler and an unmodified, current
[Zeal-NativeEmulator](https://github.com/Zeal8bit/Zeal-NativeEmulator) checkout
alongside this project. Supply `--emulator /path/to/Zeal-NativeEmulator` or
`ZEAL_EMULATOR_PATH` for another location.

These checks execute the assembled routines with the emulator's Z80 CPU core.
The harness supplies user RAM, banked ZVB video memory/registers, the emulator's
standard font, and deterministic Zeal syscall responses, including
short transfers, OS failures and virtual-page constraints. It does not replace
end-to-end testing on Zeal OS or physical hardware.

Keyboard checks inject an interrupt handler that destroys the alternate CPU
register bank. They verify that polling and blocking input preserve BASIC's
registers, Escape releases are ignored, ordinary keys remain available to GET,
and an infinite GOTO loop can return to the prompt with error 17 (Escape).
Private IM2 wrappers preserve the alternate bank while delegating the standard
Zeal default and PIO interrupts to the kernel. Interrupts remain enabled during
arithmetic and device reads; keyboard events are polled every 20 execution checks.
The syscall adapter restores the kernel's vector table while the kernel remaps
user RAM, and the parent's original I register is restored on exit. A private
vector page lowers initial HIMEM from &F800 to &F700 (256 bytes less BASIC memory).
Polling retains up to 16 ordinary keypresses; additional keys are dropped while
the queue is full, but Escape is still recognized. Non-keyboard redirected
input is not polled; GET continues to read it as a byte stream.

Raw GET/GET$ input translates left/right Shift and Ctrl, Caps Lock, US-ASCII
shifted punctuation and keypad characters. Modifier keys and unsupported
non-character keys are not returned as characters. Modifier state is cleared
when entering cooked input: the current keyboard API exposes neither the cooked
modifier/lock state nor a nonblocking character-translation service. Consequently
non-US shifted punctuation and modifiers already held across that mode change
are not inferred by this port.

OS failures reported by this port use BASIC `ERR = 128 + Zeal OS error code`
and the message `Zeal OS error`. `OPENIN`/`OPENOUT`/`OPENUP` retain their BASIC
contract of returning channel zero when opening fails.

File-interface checks exercise OPENOUT truncation and overwrite behavior,
OPENUP read/write access, non-consuming EOF checks, and 32-bit EXT sizes through
the evaluator as well as the adapters. The syscall model enforces access flags
and seek positions. Close-all tests cover multiple owned descriptors, inherited
standard streams and other caller handles, failed opens, temporary load/save
handles, repeated cleanup, close failures and retry, program END, error unwinding,
and exit. Cleanup attempts all owned closes, retains failed handles for retry,
and preserves the original BASIC error during best-effort error cleanup.

Line-input checks cover bounded cooked reads, missing terminators, read failures,
EOF, redirected CRLF streams and overlong-line recovery. Redirected input reads
through one LF at a time; overlong lines are drained and reported as errors.

`LOAD$` checks import the four graphics source listings through the file adapter
and compare their records with the original tokenizer. They cover arbitrary
filename extensions, filename expressions, blank/indented lines, line endings,
an unterminated final line, empty files, malformed input, line-number ordering,
source/token buffer limits, memory exhaustion and file failures. Failed imports
discard incomplete text and release their file handle, retaining failed closes
for retry. The ZShell integration also imports and runs all four graphics demos
through the real kernel and compares them with their saved `.bbc` copies.

Cursor checks compare numeric PRINT output with and without two-coordinate TAB,
including a video driver that overwrites scratch registers. Example checks use
the assembled BASIC lexer: Hamurabi's binary must match its numbered text source,
land purchases must update acreage and grain, and planting retries must preserve
stack depth. Blackjack's text source is tokenized and its score procedure is run
with a one-player hand through the pause and return. These are focused gameplay
checks rather than complete interactive playthroughs.

## ZShell integration

A separate headless kernel is unnecessary. The native emulator's `--console
--debug` mode drives the same video/PS2 kernel used interactively. Build a ROM
with ZShell and HostFS enabled (the existing `zshell/emu` configuration):

```sh
zde kernel zshell/emu
zde cmake
python3 tests/zshell_integration.py --build-dir build \
  --rom /path/to/os_with_romdisk.img --kernel-map /path/to/os.map
```

The ROM and map must come from the same kernel build. Supply `--emulator` for
another native-emulator executable, `--tf` for a TF image, and `--log` to retain
the debugger transcript. The test creates private ROM, EEPROM, TF and HostFS
copies; it does not write to the supplied images or emulator configuration.
It exposes the newly built BASIC through HostFS and launches `h:/bbcbasic` from
ZShell, so an older BASIC in ROM or on a TF card cannot be selected accidentally.
The ROM still needs ZShell itself and its normal startup files.

Assertions cover inherited raw/nonblocking stdin, the cooked/blocking mode
change, idle blocking, read status/count and LF termination, numeric PRINT,
INPUT, raw GET, numbered program entry/RUN, floating-point arithmetic during
hardware interrupts, physical Escape from an infinite loop, SAVE, return to
ZShell and filename auto-run after relaunch. These tests execute real kernel
syscalls and the emulated PS/2 device; physical hardware remains unverified.


## Display checks

The normal regression runner also executes BBC command parsing, VDU sequences,
all supported GCOL actions, signed/relative plotting, clipping/origin changes,
POINT, triangles, rectangles, horizontal fills, custom characters, text windows,
scrolling, raw line editing, and both graphics demonstration programs. Bitmap
text uses native 8x12 cells and must not write into adjacent cells. An interrupt is injected while video memory is mapped
to verify arithmetic registers and restoration of the temporary page mapping.
The font snapshot and other display scratch buffers are deliberately seeded
with junk before the demo, proving they do not depend on zero-filled file data.

The build runs `tests/check_layout.py` to verify that the image excludes runtime
workspace, preserves required page alignment, leaves room below HIMEM, and keeps
video helpers and interrupt wrappers below the temporary video mapping at &8000.
The 3KB font backup and 960-byte triangle workspace occupy runtime RAM only.

For a bitmap preview of the assembled graphics demonstration, set
`BBC_GRAPHICS_PREVIEW=/absolute/path/preview.ppm` when running `tests/run.py`.
The preview uses the actual indexed pixels and palette written by BASIC.

The ZShell integration now also covers bitmap DRAW/GCOL/PLOT/POINT, INPUT and GET
with display-owned echo, POS/VPOS in text mode, repeated mode changes, Escape in
bitmap mode, and restoration of the shell's text display. Blocking raw reads are
used while waiting for display input; nonblocking raw mode is restored before
echo or drawing, so scrolling and Escape polling cannot block on a key.

Size optimizations preserve the original interpreter modules. Graphics checks
compare line pixels against a wide-integer reference across all supported line
styles, both directions, and extreme signed endpoints. They also verify fills
bounded by a different colour, asymmetric glyphs in every bitmap mode,
transparent XOR text, video spans crossing MMU pages with an interrupt pending,
and cold-start initialization of graphics state in poisoned runtime RAM.
The span writer keeps its two mapped-access bytes below &8000; all relocated
video state and scratch are checked as a separate runtime workspace region.
Additional checks sample signed Y-coordinate scaling across the full input
range, verify text-window bounds and clearing in all eight supported modes, and compare
every default palette entry and BBC physical colour against RGB565 values.

Native-mode checks reject BBC graphics selectors before video I/O, verify both
text grids and font restoration, cover 320x200 and 256x240 bitmap geometry and
9-bit colour arguments, and inspect 8/4-bit tile-font pixels, reserved colours,
palette banks and text input. Mode selection lives in a separate Zeal module;
the inherited hardware module is excluded from the build. The original command
module has small hooks for display error recovery and `LOAD$`; the executor,
expression evaluator and floating-point interpreter modules remain unchanged.
