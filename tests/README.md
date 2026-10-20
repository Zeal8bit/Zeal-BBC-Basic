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

OS failures reported by this port use BASIC `ERR = 128 + Zeal OS error code`
and the message `Zeal OS error`. `OPENIN`/`OPENOUT`/`OPENUP` retain their BASIC
contract of returning channel zero when opening fails.
