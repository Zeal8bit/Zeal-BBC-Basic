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
