#!/usr/bin/env python3
"""Compare 100 complete Lander updates using emulated cycles, not host time."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import tempfile

from zshell_integration import Console, ROOT, symbols


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def zeal_trial(args, b, console_factory=Console):
    with tempfile.TemporaryDirectory(prefix='lander-benchmark-') as temporary:
        directory = Path(temporary)
        shutil.copy2(args.build_dir / 'bbcbasic.bin', directory / 'bbcbasic')
        shutil.copy2(ROOT / 'examples/gfx/lander.bas', directory / 'lander.bas')
        shutil.copy2(args.rom, directory / 'rom.img')
        (directory / 'empty.ini').write_text('')
        (directory / 'eeprom.img').write_bytes(b'\xff' * 65536)
        with (directory / 'tf.img').open('wb') as stream:
            stream.truncate(4 * 1024 * 1024)
        c = console_factory([str(args.emulator.resolve()), '--console', '--debug',
                     '--config', str(directory / 'empty.ini'), '--rom', str(directory / 'rom.img'),
                     '--map', str(args.kernel_map.resolve()), '--hostfs', str(directory),
                     '--tf', str(directory / 'tf.img'), '--eeprom', str(directory / 'eeprom.img')], directory)
        try:
            def done():
                return b['LINE_DISPLAY_DONE'] if c.memory(b['D_ACTIVE'], 1) != b'\0' else b['LINE_DONE']

            def line(text):
                c.type(text + '\n')
                r = c.until(done())
                assert c.memory(r['HL'] - len(text), len(text) + 1) == (text + '\n').encode()
                c.clear(done())

            c.run(50_000_000)
            c.bp(b['OSLINE'])
            c.type('h:/bbcbasic\n')
            c.until(b['OSLINE'])
            c.clear(b['OSLINE'])
            c.bp(done())
            c.run()
            line('LOAD$ "H:/lander.bas"')
            c.bp(b['OSLINE'])
            c.until(b['OSLINE'])
            assert c.memory(b['ERR'], 1) == b'\0'
            c.clear(b['OSLINE'])
            c.bp(done())
            c.run()
            line('RUN')
            c.bp(b['OSKEY'])
            c.bp(b['OSLINE'])
            timestamps, site = [], None
            for _ in range(1000):
                c.run(30_000_000)
                registers = c.regs()
                assert registers['PC'] == b['OSKEY'], 'Game stopped before completing the sample'
                assert c.memory(b['ERR'], 1) == b'\0'
                assert c.memory(b['D_MODE_NO'], 1) == b'\x09'
                if site is None:
                    site = registers['IY']
                # step reports the exact CPU cycle count after one instruction.
                # Taking every boundary at the same instruction cancels that
                # constant offset. Debugger/host waiting contributes no cycles.
                reply = c.send('step')
                cycles = int(re.search(r'cyc=(\d+)', reply)[1])
                if registers['IY'] == site:
                    timestamps.append(cycles)
                    if len(timestamps) == 11 and hasattr(c, 'start_profile'):
                        c.start_profile(b, cycles)
                # ZOS uses additional INKEY calls to flush input. Exclude them
                # by counting only the first game's main-input call site.
                if len(timestamps) == 111:
                    break
            assert len(timestamps) == 111, 'Insufficient main-loop boundaries'
            cycles = timestamps[110] - timestamps[10]
            seconds = cycles / 10_000_000  # native emulator's fixed CPUFREQ
            result = dict(cycles=cycles, seconds=seconds, updates_per_second=100 / seconds)
            if hasattr(c, 'finish_profile'):
                result['profile'] = c.finish_profile(cycles)
            return result
        except Exception:
            print(c.log[-4000:])
            raise
        finally:
            c.close()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--jsbeeb', type=Path, required=True, help='Installed jsbeeb package directory')
    p.add_argument('--rom', type=Path, required=True)
    p.add_argument('--kernel-map', type=Path, required=True)
    p.add_argument('--emulator', type=Path, default=ROOT.parent / 'Zeal-NativeEmulator/build/zeal-native')
    p.add_argument('--build-dir', type=Path, default=ROOT / 'build')
    p.add_argument('--output', type=Path, help='Write results and input hashes as JSON')
    args = p.parse_args()
    process = subprocess.run(['node', str(ROOT / 'tests/benchmark_lander_bbc.mjs'),
                              str(args.jsbeeb.resolve()),
                              str(ROOT / 'examples/gfx/lander_bbc.bas')],
                             capture_output=True, text=True)
    if process.returncode:
        raise RuntimeError(process.stdout + process.stderr)
    bbc = json.loads(next(line.removeprefix('BENCHMARK_JSON:') for line in process.stdout.splitlines()
                          if line.startswith('BENCHMARK_JSON:')))
    b = symbols(args.build_dir / 'bbcbasic.map')
    runs = []
    for trial in range(3):
        runs.append(zeal_trial(args, b))
        print(f'Zeal trial {trial + 1}: {runs[-1]["updates_per_second"]:.6f} updates/s', flush=True)
    bbc_rate = statistics.median(run['updates_per_second'] for run in bbc['runs'])
    zeal_rate = statistics.median(run['updates_per_second'] for run in runs)
    result = dict(
        benchmark='Lunar Lander unpowered coast', measured_updates=100, warmup_updates=10,
        timing='Emulated CPU cycles; startup and host/debugger waiting excluded',
        bbc=bbc,
        zeal=dict(emulator='Zeal-NativeEmulator', cpu_hz=10_000_000, basic_mode=9,
                  binary_sha256=sha256(args.build_dir / 'bbcbasic.bin'),
                  emulator_sha256=sha256(args.emulator), kernel_sha256=sha256(args.rom),
                  kernel_map_sha256=sha256(args.kernel_map),
                  source_sha256=sha256(ROOT / 'examples/gfx/lander.bas'), runs=runs),
        median_updates_per_second=dict(bbc=bbc_rate, zeal=zeal_rate),
        zeal_relative_rate=zeal_rate / bbc_rate,
    )
    if args.output:
        args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(f'BBC Model B: {bbc_rate:.6f} updates/s; Zeal: {zeal_rate:.6f} updates/s; '
          f'Zeal/BBC: {zeal_rate / bbc_rate:.4f}')


if __name__ == '__main__':
    main()
