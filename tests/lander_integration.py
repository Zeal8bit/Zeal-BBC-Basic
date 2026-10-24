#!/usr/bin/env python3
"""Play the unmodified ZOS Lander listing using real OS time and PS/2 keys."""
import argparse
import math
from pathlib import Path
import shutil
import tempfile

from zshell_integration import Console, ROOT, symbols


def exercise(c, b, directory):
    def line_done():
        return b['LINE_DISPLAY_DONE'] if c.memory(b['D_ACTIVE'], 1) != b'\0' else b['LINE_DONE']

    def line(text):
        c.type(text + '\n')
        r = c.until(line_done())
        assert c.memory(r['HL'] - len(text), len(text) + 1) == (text + '\n').encode()
        c.clear(line_done())

    def prompt():
        c.bp(b['OSLINE'])
        c.until(b['OSLINE'])
        assert c.memory(b['ERR'], 1) == b'\0', 'BASIC reported an error'
        c.clear(b['OSLINE'])
        c.bp(line_done())
        c.run()

    addresses = {}

    def number(name):
        # Read the original interpreter's scalar-variable list without writing
        # game state or evaluating injected statements during its main loop.
        if name not in addresses:
            index = ord(name[0]) - ord('@')
            if index >= 27:
                index -= 4
            address = int.from_bytes(c.memory(b['DYNVAR'] + 2 * index - 2, 2), 'little')
            while address:
                entry = c.memory(address, 64)
                end = entry.index(0, 2)
                if entry[2:end].decode() == name[1:]:
                    addresses[name] = address + end + 1
                    break
                address = int.from_bytes(entry[:2], 'little')
            else:
                raise AssertionError('Missing game variable ' + name)
        value = c.memory(addresses[name], 5)
        mantissa = int.from_bytes(value[:4], 'little')
        if value[4] == 0:
            return int.from_bytes(value[:4], 'little', signed=True)
        sign = -1 if mantissa & 0x80000000 else 1
        return sign * math.ldexp(1 + (mantissa & 0x7fffffff) / 2**31, value[4] - 128)

    c.run(50_000_000)
    c.bp(b['OSLINE'])
    c.type('h:/bbcbasic\n')
    c.until(b['OSLINE'])
    c.clear(b['OSLINE'])
    c.bp(line_done())
    c.run()
    line('LOAD$ "H:/lander.bas"')
    prompt()
    for controlled in (False, True):
        addresses.clear()
        line('RUN')
        c.bp(b['OSKEY'])
        c.bp(b['OSLINE'])
        thrust_seen = False
        first_height = None
        key_site = None
        frames = 0
        for frames in range(1, 2001):
            for _ in range(20):
                c.run(30_000_000)
                pc = c.regs()['PC']
                if pc == b['OSKEY']:
                    site = c.regs()['IY']
                    if key_site is None:
                        key_site = site
                    if site != key_site:  # let the equivalent *FX buffer flush run
                        c.send('step')
                        continue
                if pc in (b['OSKEY'], b['OSLINE']):
                    break
            if pc == b['OSLINE']:
                break
            assert pc == b['OSKEY'], f'Game stalled at {pc:04x}'
            assert c.memory(b['ERR'], 1) == b'\0'
            assert c.memory(b['D_MODE_NO'], 1) == b'\x09'
            height, speed = number('height'), number('speed')
            fuel, mass = number('fuel'), number('totalmass')
            if first_height is None:
                first_height = height
            if controlled:
                # Feedback controller presses normal game keys; no physics,
                # clock, variables or source are altered to force an outcome.
                deceleration = max(0.001, 540 / mass - 0.001)
                target = min(0.4, 0.65 * math.sqrt(max(0, 2 * deceleration * height)))
                if speed > target and fuel > 0:
                    c.send('tap 9')
                    thrust_seen = True
            if frames < 5 or frames % 100 == 0:
                elapsed = int.from_bytes(c.memory(b['TIME_VALUE'], 4), 'little') / 100
                print(f'{"controlled" if controlled else "coast"}: {frames} frames, '
                      f'{elapsed:.1f}s, height={height:.5f}, speed={speed:.5f}, fuel={fuel:.1f}', flush=True)
            c.send('step')
        else:
            raise AssertionError('Game did not reach a landing')
        c.clear(b['OSKEY'])
        assert first_height == 46
        assert number('height') == 0
        assert c.memory(b['ERR'], 1) == b'\0', 'Error handler hid a failure'
        elapsed = int.from_bytes(c.memory(b['TIME_VALUE'], 4), 'little') / 100
        speed, fuel = number('speed'), number('fuel')
        if controlled:
            assert thrust_seen and 0 < fuel < 16500
            assert speed <= 0.004, f'Controlled flight crashed at {speed * 3600:.2f} mph'
            assert number('X') == 12, 'Success/fanfare branch did not complete'
        else:
            assert speed > 0.004 and fuel == 16500
            assert number('X') == 101, 'Crash graphics branch did not complete'
        print(f'PASS: {"soft landing" if controlled else "unpowered crash"}: '
              f'{frames} frames, {elapsed:.2f}s, {speed * 3600:.2f} mph, {fuel:.1f} lb fuel', flush=True)
        c.clear(b['OSLINE'])
        c.bp(line_done())
        c.run()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--build-dir', type=Path, default=ROOT / 'build')
    p.add_argument('--emulator', type=Path, default=ROOT.parent / 'Zeal-NativeEmulator/build/zeal-native')
    p.add_argument('--rom', type=Path, required=True)
    p.add_argument('--kernel-map', type=Path, required=True)
    p.add_argument('--log', type=Path)
    args = p.parse_args()
    with tempfile.TemporaryDirectory(prefix='bbc-lander-') as temporary:
        directory = Path(temporary)
        shutil.copy2(args.build_dir / 'bbcbasic.bin', directory / 'bbcbasic')
        shutil.copy2(ROOT / 'examples/gfx/lander.bas', directory / 'lander.bas')
        shutil.copy2(args.rom, directory / 'rom.img')
        (directory / 'empty.ini').write_text('')
        (directory / 'eeprom.img').write_bytes(b'\xff' * 65536)
        with (directory / 'tf.img').open('wb') as stream:
            stream.truncate(4 * 1024 * 1024)
        c = Console([str(args.emulator.resolve()), '--console', '--debug',
                     '--config', str(directory / 'empty.ini'), '--rom', str(directory / 'rom.img'),
                     '--map', str(args.kernel_map.resolve()), '--hostfs', str(directory),
                     '--tf', str(directory / 'tf.img'), '--eeprom', str(directory / 'eeprom.img')], directory)
        try:
            exercise(c, symbols(args.build_dir / 'bbcbasic.map'), directory)
        except Exception:
            print(c.log[-5000:])
            raise
        finally:
            c.close()
            if args.log:
                args.log.write_text(c.log)


if __name__ == '__main__':
    main()
