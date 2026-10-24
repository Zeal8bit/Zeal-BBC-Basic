# Lunar Lander: BBC Micro versus Zeal

Baseline measured on 2026-10-24 with the graphics-text erasure fix included in
the Zeal binary, before row/span rendering optimization. These are **game-loop updates per simulated second**, not monitor
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

The BBC run loads `examples/gfx/lander_bbc.bas`, correcting only the visibly
missing comma on line 8015 in the in-memory source before tokenization. The
reference file remains untouched. Original MODE 5 and BBC keyboard configuration
and flush commands remain active.

Zeal runs `examples/gfx/lander.bas` through the actual Zeal OS kernel and
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

## Where the baseline Zeal build spends its time

A debugger-only profile of the same 100-update window reproduced **329,850,982
cycles exactly**, both before and after separating glyph-rendering categories.
No interpreter, game, kernel or emulator code was changed. The measured costs
below are exclusive: nested routines are subtracted from their callers.

| Work | ms/update | Share of total |
| --- | ---: | ---: |
| Dashboard glyph pixels (36 characters/update) | 128.411 | 38.93% |
| Rocket/flame cell erasure (5 cells/update) | 78.429 | 23.78% |
| Rocket glyph pixels (3 characters/update) | 29.783 | 9.03% |
| Interpreter and other uninstrumented work | 71.416 | 21.65% |
| Output handling outside glyph pixels | 16.976 | 5.15% |
| Graphics coordinate transformation | 2.465 | 0.75% |
| Keyboard polling, excluding timer | 1.122 | 0.34% |
| Timer refresh, including calls from polling | 1.062 | 0.32% |
| Plot handling, excluding coordinate transformation | 0.162 | 0.05% |
| TIME read wrapper, excluding refresh | 0.025 | 0.01% |

The dominant cost is **character rendering: 236.623 ms/update, or 71.74%**.
That alone exceeds the BBC's entire 226.804 ms/update. The uninstrumented
remainder includes interpreter arithmetic, parsing, statement dispatch and any
other work outside the selected routines; it is not a pure arithmetic profile.

### Why rendering costs so much

`D_DRAW_GLYPH` walks every pixel of an 8x12 native font cell. For opaque dashboard
text, each pixel calls `V_WRITE`, which saves registers, maps video memory,
writes one byte, restores the mapping and restores registers. The dashboard
therefore performs **3,456 individually mapped pixel writes per update**,
including spaces used to pad numeric fields. Glyph loading separately reads
12 font bytes through individually mapped accesses for each character.

Graphics deletion is more expensive per cell: all 96 pixels go through
`G_TEXT_ERASE_PIXEL`, the general clipping/address path and `V_PAINT` with a
count of one. That repeats clipping, address arithmetic, span setup and mapping
**480 times per update**. The normal rocket glyphs use this general graphics
path for their set pixels too. The small logical-coordinate conversion is
outside the pixel loop and accounts for less than 1% overall.

BBC MODE 5 uses packed 2-bit pixels and a different native display arrangement;
Zeal MODE 9 uses one byte per pixel. Higher Z80 clock speed cannot by itself
compensate for this software overhead and different storage format. This profile
identifies Zeal's costs; it does not separately profile the BBC ROM routines or
establish the relative performance of the two CPUs on equal instruction work.

### Recommended optimization order

1. Add a Zeal bitmap glyph-row writer that maps once per row and emits its eight
   pixels while mapped, keeping mapping-sensitive code below &8000. Preserve
   the existing font, opaque foreground/background behavior, page boundaries
   and interrupt safety. This targets the largest cost without modifying the
   original interpreter or game.
2. Clear graphics character cells with clipped horizontal spans rather than 96
   independent pixel operations. Preserve graphics-window clipping, background
   replacement, cursor state and the existing deletion regression tests.
3. Batch transparent graphics glyph runs, retaining GCOL operations and clipping.
   Consider bulk font reads after measuring the first two changes.

Do not start with floating-point changes, coordinate conversion or the timer:
none is supported by this profile as the first target. Avoid changing the game
to skip dashboard updates; improve the backend used by existing programs.

As a rough budget, halving the combined glyph-rendering cost with all other
costs fixed would reduce 329.851 ms/update to **211.539 ms/update (~4.73 updates/s)**,
already faster than the measured BBC run. This is an estimate, not a demonstrated
speedup: changed update timing changes the game's trajectory and printed values.

### Reproduce the profile

```sh
python3 tests/profile_lander.py \
  --rom /path/to/os_with_romdisk.img \
  --kernel-map /path/to/os.map \
  --output tmp/lander-profile.json
```

The profiler reuses the benchmark's warm-up and main-loop boundaries. It sets
entry breakpoints and temporary return-address breakpoints through the native
emulator's supported console. Nested calls are tracked on a host-side stack;
no tracing code is injected into the guest. Host/debugger pauses add no guest
cycles. Interrupt service during a measured routine is included in its cost.
The profiler is scoped to this workload and selected returning routines, not a
general profiler for arbitrary control flow. [lander-profile.json](lander-profile.json)
records exclusive cycles, call counts and input hashes.


## Row/span optimization results

The Zeal backend now writes each opaque eight-pixel character row with one
video mapping, and erases graphics character cells through the existing clipped
rectangle/span writer. Transparent glyphs retain the general GCOL pixel path,
with the per-pixel text/erase mode dispatch removed. No original interpreter,
game, OS or emulator source was changed.

| Build | Cycles / 100 updates | ms/update | Updates/s |
| --- | ---: | ---: | ---: |
| BBC reference | 45,360,701 at 2 MHz | 226.804 | 4.409103 |
| Zeal baseline | 329,850,982 at 10 MHz | 329.851 | 3.031672 |
| Zeal row/span writer | 150,409,487 at 10 MHz | 150.409 | **6.648517** |

All three fresh-machine trials reproduced the optimized result exactly. Zeal
now delivers **2.19 times its previous update rate**, and **50.79% more updates
per simulated second than the BBC reference**. This is the same early-coast
benchmark; it does not establish a universal speed ratio across BBC programs.
[lander-optimized.json](lander-optimized.json) preserves results and input hashes.
The original baseline and profile JSON files remain available for comparison.

Validation: build and memory-layout checks passed, along with **32,453 adapter
regression checks**. New tests cover opaque glyphs on both sides of video MMU
page boundaries in both bitmap modes, non-default foreground/background colours,
neighbouring pixels and restored mappings. Existing tests cover all graphics
colour actions, clipped cell erasure, cursor state and the Lander trail regression.
The real-kernel gameplay test completed an unpowered crash and a controlled soft
landing at **8.70 mph**, with **2,438.4 lb fuel** remaining; its 115.53 simulated
seconds also cross the hardware timer wrap. Physical hardware remains untested.

The binary is **19,621 bytes**, up **55 bytes**, still 3,237 bytes above the soft
16 KiB goal. Runtime workspace remains 5,376 bytes and PAGE remains &A200.
