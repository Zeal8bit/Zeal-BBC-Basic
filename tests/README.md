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
The harness supplies flat RAM and deterministic Zeal syscall responses, including
short transfers, OS failures and virtual-page constraints. It does not replace
end-to-end testing on Zeal OS or physical hardware.

Keyboard checks inject an interrupt handler that destroys the alternate CPU
register bank. They verify that polling and blocking input preserve BASIC's
registers, Escape releases are ignored, ordinary keys remain available to GET,
and an infinite GOTO loop can return to the prompt with error 17 (Escape).
Interrupts remain disabled during interpreter arithmetic and are serviced in
guarded polling windows every 20 execution checks, and during blocking input.
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

Cursor checks compare numeric PRINT output with and without two-coordinate TAB,
including a video driver that overwrites scratch registers. Example checks use
the assembled BASIC lexer: Hamurabi's binary must match its numbered text source,
land purchases must update acreage and grain, and planting retries must preserve
stack depth. Blackjack's text source is tokenized and its score procedure is run
with a one-player hand through the pause and return. These are focused gameplay
checks rather than complete interactive playthroughs.
