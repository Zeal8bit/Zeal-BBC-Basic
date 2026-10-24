# Lunar Lander: BBC Micro versus Zeal

Measured on 2026-10-24 with the graphics-text erasure fix included in the Zeal
binary. These are **game-loop updates per simulated second**, not monitor
refresh rates or emulator speed on the host computer.

| Machine | Emulator | CPU clock | Display | Cycles for 100 updates | Simulated seconds | Updates/s | ms/update |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BBC Micro Model B | jsbeeb 2.11.0, B-DFS1.2 | 2 MHz | BBC MODE 5, 160x256 | 45,360,701 | 22.680351 | **4.409103** | 226.804 |
| Zeal, current BASIC port | Zeal Native Emulator | 10 MHz | Zeal MODE 9, 256x240 | 329,850,982 | 32.985098 | **3.031672** | 329.851 |

All three fresh-machine trials on each emulator returned the same cycle count.
Zeal achieves **68.76% of the BBC update rate** for this workload: **31.24% fewer
updates per second**, or **45.43% more time per update**. This measures the
current interpreter, OS adapter and graphics implementation together. It does
not establish that a Z80 or Zeal hardware is generally slower than a BBC Micro.

## What is measured

Both machines run the historical Lunar Lander game on an **unpowered coast**,
with no keys pressed. Setup, ROM boot, tokenization/loading and the crash
animation are excluded. The first ten complete updates are warm-up; the next
100 complete updates form the sample.

Boundaries are the nonblocking input call in the original main loop, line 180:

- BBC: the documented MOS OSBYTE entry, `&FFF4`, with A=129 and X=Y=0.
- Zeal: the BASIC adapter's `OSKEY`, restricted to that main-input call site.
  Additional INKEY calls used to emulate the original keyboard-buffer flush
  are allowed to execute and contribute to elapsed cycles, but are not counted
  as extra game updates.

The BBC sample uses jsbeeb's monotonically accumulated `elapsedCycles`, including
its rebasing of internal counters. Zeal uses the native debugger's `cyc=` value
after the same first instruction of OSKEY at each boundary. That constant
instruction offset cancels when subtracting timestamps. Neither debugger
pauses nor host processing time contribute emulated cycles.

Divide elapsed cycles by **2,000,000** or **10,000,000**, respectively, then
divide 100 updates by those simulated seconds. This avoids comparing raw
cycle counts from different CPU architectures or relying on BASIC clock
granularity. No in-game benchmark statements are inserted.

## Emulator and program choices

[jsbeeb](https://github.com/mattgodbolt/jsbeeb) is a cycle-accurate BBC emulator
with a supported headless `MachineSession` API. This test uses its real video
implementation, default cycle-accurate CPU, ordinary Model B ROMs and no Tube
processor or CPU multiplier. Its host JavaScript implementation does not affect
the calculated guest update rate.

The BBC run loads `examples/gfx/lander/original.bas`, correcting only the visibly
missing comma on line 8015 in the in-memory source before tokenization. The
reference file remains untouched. Original MODE 5 and BBC keyboard configuration
and flush commands remain active.

Zeal runs `examples/gfx/lander/zos.bas` through the actual Zeal OS kernel and
`LOAD$`. That copy retains the same flight equations, but has the documented
native mode, palette, text-window, keyboard-flush and silent-sound adjustments.
The two displays have different native character cells and pixel arrangements;
this is an application-port comparison, not an identical-framebuffer or pure
CPU benchmark. As simulated time advances at different rates per update, the
two runs also reach different altitudes after 100 updates.

These are emulator measurements, not physical-hardware measurements. In
particular, native ZVB memory/bus timings must be representative for the Zeal
prediction to match a physical board. No external emulator, OS or SDK source
was modified. The scripts use supported debugger/headless APIs.

## Reproduce

Requirements: Node.js 24.15 or later, Python 3, the existing native-emulator
build, and a matching Zeal OS ROM/kernel map. Install the published jsbeeb
package locally; no global installation, Electron or browser is needed:

```sh
npm install --prefix tmp/lander-jsbeeb --ignore-scripts --omit=optional \
  --no-audit --no-fund jsbeeb@2.11.0
zde cmake
python3 tests/benchmark_lander.py \
  --jsbeeb tmp/lander-jsbeeb/node_modules/jsbeeb \
  --rom /path/to/os_with_romdisk.img \
  --kernel-map /path/to/os.map \
  --output tmp/lander-benchmark.json
```

`--jsbeeb` points at the installed package directory itself. The benchmark
creates private HostFS and image copies for each native-emulator trial and
does not modify the supplied ROM, map or emulator installation.

[lander.json](lander.json) contains all trial counts, emulator settings and
SHA-256 hashes of the BBC ROMs, listings, Zeal interpreter, native emulator and
Zeal kernel used for the results above. Rebuild and rerun to assess later
changes; do not treat these performance numbers as a permanent correctness
threshold.
