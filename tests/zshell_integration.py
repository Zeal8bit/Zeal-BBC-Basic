#!/usr/bin/env python3
"""Exercise BASIC through ZShell, real kernel syscalls and emulated PS/2 keys."""
import argparse
import os
from pathlib import Path
import re
import select
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def symbols(path):
    found = {}
    for line in path.read_text().splitlines():
        match = re.match(r'(\w+)\s+= \$([0-9a-fA-F]+)', line)
        if match and (match[1] not in found or ', public,' in line):
            found[match[1]] = int(match[2], 16)
    return found


class Console:
    def __init__(self, command, directory):
        self.log = ''
        self.pending = b''
        self.process = subprocess.Popen(command, stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                        cwd=directory)
        self.read()

    def read(self):
        deadline = time.monotonic() + 15
        while b'debug> ' not in self.pending:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise RuntimeError('Emulator console timed out')
            if not select.select([self.process.stdout], [], [], remaining)[0]:
                continue
            chunk = os.read(self.process.stdout.fileno(), 65536)
            if not chunk:
                raise RuntimeError('Emulator exited before its console prompt')
            self.pending += chunk
        reply, self.pending = self.pending.split(b'debug> ', 1)
        text = reply.decode(errors='replace')
        self.log += text
        return text

    def send(self, command):
        self.log += '\n> ' + command + '\n'
        self.process.stdin.write((command + '\n').encode())
        self.process.stdin.flush()
        return self.read()

    def regs(self):
        return {name: int(value, 16) for name, value in re.findall(
            r'\b(PC|SP|AF|BC|DE|HL|IX|IY|I)=([0-9a-fA-F]+)', self.send('regs'))}

    def memory(self, address, count):
        reply = self.send(f'rb {address} {count}')
        data = bytes(int(byte, 16) for line in re.findall(
            r'\[DBG\] [0-9a-f]+: ([0-9a-f ]+)', reply) for byte in line.split())
        assert len(data) == count, f'Could not read {count} bytes at {address:04x}'
        return data

    def bp(self, address):
        self.send(f'bp {address}')

    def clear(self, address):
        self.send(f'bc {address}')

    def run(self, states=1_000_000):
        self.send(f'run {states}')

    def until(self, address):
        registers = self.regs()
        if registers.get('PC') != address:
            self.run(30_000_000)
            registers = self.regs()
        assert registers.get('PC') == address, f'Expected PC={address:04x}, got {registers}'
        return registers

    def type(self, text):
        keys = {'.': 'PERIOD', '/': 'SLASH', ':': 'SEMICOLON', ' ': 'SPACE',
                '\n': 'ENTER', '%': '5', '=': 'EQUAL', '+': 'EQUAL',
                '"': 'APOSTROPHE', '*': '8', ',': 'COMMA', ';': 'SEMICOLON',
                '(': '9', ')': '0', '-': 'MINUS'}
        for char in text:
            shift = char in ':%+"*()' or char.isupper()
            if shift:
                self.send('press SHIFT')
                self.run(100_000)
            self.send('tap ' + keys.get(char, char.upper()))
            self.run(300_000)
            if shift:
                self.send('release SHIFT')
                self.run(100_000)

    def close(self):
        try:
            if self.process.poll() is None:
                self.process.stdin.write(b'quit\n')
                self.process.stdin.flush()
                self.process.wait(timeout=5)
        finally:
            if self.process.poll() is None:
                self.process.kill()
                self.process.wait()
            self.process.stdin.close()
            self.process.stdout.close()


def exercise(c, b, k, directory):
    def line_done():
        return b['LINE_DISPLAY_DONE'] if c.memory(b['D_ACTIVE'], 1) != b'\0' else b['LINE_DONE']

    def check_error():
        assert c.memory(b['ERR'], 1) == b'\0', 'Unexpected BASIC error'

    def line(text):
        c.type(text + '\n')
        r = c.until(line_done())
        assert r['AF'] >> 8 == 0, f'Line read failed: {r}'
        # INPUT uses a different page-aligned buffer from the command prompt.
        assert c.memory(r['HL'] - len(text), len(text) + 1) == (text + '\n').encode()
        c.clear(line_done())

    def prompt():
        c.bp(b['OSLINE'])
        c.run()
        c.until(b['OSLINE'])
        check_error()
        c.clear(b['OSLINE'])
        c.bp(line_done())
        c.run()

    def integer(name):
        address = b['STAVAR'] + (ord(name) - ord('@')) * 4
        return int.from_bytes(c.memory(address, 4), 'little', signed=True)

    c.run(50_000_000)
    c.bp(k['keyboard_read'])
    c.run()
    c.until(k['keyboard_read'])
    assert c.memory(k['kb_mode'], 1) == b'\x04', 'ZShell must start in raw nonblocking mode'
    assert c.regs()['I'] == k['interrupt_vector_table'] >> 8
    c.clear(k['keyboard_read'])
    c.bp(b['OSLINE'])
    c.type('h:/bbcbasic\n')
    assert c.until(b['OSLINE'])['I'] == b['IRQ_TABLE'] >> 8
    c.clear(b['OSLINE'])
    c.bp(k['keyboard_read'])
    c.run()
    r = c.until(k['keyboard_read'])
    assert c.memory(k['kb_mode'], 1) == b'\x01', 'BASIC did not select cooked blocking mode'
    assert r['I'] == k['interrupt_vector_table'] >> 8, 'Kernel vectors not restored for syscall'
    assert r['BC'] == 255 and r['DE'] == b['ACCS'], 'Wrong stdin read buffer or length'
    c.clear(k['keyboard_read'])
    c.bp(line_done())
    c.run(30_000_000)
    assert c.regs()['PC'] != b['LINE_DONE'], 'Idle stdin read returned instead of blocking'
    check_error()
    print('PASS: ZShell launch, inherited stdin, cooked mode and idle blocking')

    line('PRINT 1')
    c.bp(b['OSWRCH'])
    c.bp(b['OSLINE'])
    printed = bytearray()
    for _ in range(80):
        c.run()
        r = c.regs()
        if r['PC'] == b['OSLINE']:
            break
        assert r['PC'] == b['OSWRCH'], f'PRINT did not return: {r}'
        printed.append(r['AF'] >> 8)
    else:
        raise AssertionError('Too much output; possible error loop')
    assert b'         1\n' in printed, repr(printed)
    c.clear(b['OSWRCH'])
    c.clear(b['OSLINE'])
    c.bp(line_done())
    c.run()
    line('A%=1+2')
    prompt()
    assert integer('A') == 3
    line('INPUT A%')
    prompt()
    line('42')
    prompt()
    assert integer('A') == 42
    print('PASS: PRINT, arithmetic and INPUT with successful LF-terminated reads')

    def get_key():
        c.bp(b['OSRDCH'])
        c.run()
        c.until(b['OSRDCH'])
        c.clear(b['OSRDCH'])
        c.bp(b['OSLINE'])
        c.type('x')
        c.until(b['OSLINE'])
        assert integer('B') == ord('x'), 'GET did not receive the raw keypress'
        check_error()
        c.clear(b['OSLINE'])
        c.bp(line_done())
        c.run()

    line('B%=GET')
    get_key()
    line('10 A%=A%+1')
    prompt()
    line('20 END')
    prompt()
    line('RUN')
    prompt()
    assert integer('A') == 43
    print('PASS: raw GET, numbered program entry and RUN')

    line('NEW')
    prompt()
    for statement in ('10 C=0', '20 FOR A%=1 TO 100', '30 C=C+0.5', '40 NEXT', '50 C%=C:END'):
        line(statement)
        prompt()
    line('RUN')
    prompt()
    assert integer('C') == 50, 'Floating-point loop was corrupted by interrupts'
    print('PASS: floating-point arithmetic with asynchronous hardware interrupts')
    line('NEW')
    prompt()
    line('10 INPUT A%')
    prompt()
    line('20 B%=GET')
    prompt()
    line('30 END')
    prompt()
    line('SAVE "H:/input.bbc"')
    prompt()
    assert (directory / 'input.bbc').is_file(), 'SAVE did not create the program'
    line('NEW')
    prompt()
    line('10 GOTO 10')
    prompt()
    line('RUN')
    c.run(3_000_000)
    c.bp(b['OSLINE'])
    c.send('tap ESC')
    c.run()
    c.until(b['OSLINE'])
    assert c.memory(b['ERR'], 1) == b'\x11', 'Escape did not interrupt the loop'
    c.clear(b['OSLINE'])
    c.bp(line_done())
    c.run()
    print('PASS: physical Escape event interrupts an infinite GOTO loop')
    line('*BYE')
    c.bp(k['keyboard_read'])
    c.run()
    c.until(k['keyboard_read'])
    assert c.regs()['I'] == k['interrupt_vector_table'] >> 8, 'Parent interrupt table not restored'
    assert c.memory(k['kb_mode'], 1) == b'\x04', 'ZShell did not restore raw mode after exit'
    c.clear(k['keyboard_read'])
    c.bp(b['OSLINE'])
    c.type('h:/bbcbasic h:/input.bbc\n')
    c.until(b['OSLINE'])
    c.clear(b['OSLINE'])
    c.bp(line_done())
    c.run()
    line('73')
    get_key()
    assert integer('A') == 73
    print('PASS: SAVE, exit to ZShell, filename auto-run, INPUT and GET after relaunch')

    line('MODE 1')
    prompt()
    assert c.memory(b['D_BITMAP'], 1) == b'\1'
    line('GCOL 0,2:MOVE 0,0:DRAW 80,80:A%=POINT(80,80)')
    prompt()
    assert integer('A') == 2
    line('GCOL 3,2:PLOT 69,80,80:A%=POINT(80,80)')
    prompt()
    assert integer('A') == 0
    line('INPUT A%')
    prompt()
    line('42')
    prompt()
    assert integer('A') == 42
    line('B%=GET')
    get_key()
    line('MODE 3')
    prompt()
    assert c.memory(b['D_BITMAP'], 1) == b'\0'
    line('PRINT TAB(5,10);"BBC text";:A%=POS:B%=VPOS')
    prompt()
    assert integer('A') == 13 and integer('B') == 10
    line('MODE 1')
    prompt()
    line('GCOL 0,1:MOVE 0,0:DRAW 1279,1023:A%=POINT(0,0)')
    prompt()
    assert integer('A') == 1
    print('PASS: bitmap drawing, XOR, POINT, graphics INPUT/GET, text mode and repeated mode changes')
    line('REPEAT:UNTIL FALSE')
    c.run(3_000_000)
    # Escape must leave the display usable and restore the VDU parser.
    c.bp(b['OSLINE'])
    c.send('tap ESC')
    c.run(30_000_000)
    c.until(b['OSLINE'])
    assert c.memory(b['ERR'], 1) == b'\x11'
    assert c.memory(b['D_PENDING'], 1) == b'\0'
    c.clear(b['OSLINE'])
    c.bp(line_done())
    c.run()
    line('*BYE')
    c.bp(k['keyboard_read'])
    c.run()
    c.until(k['keyboard_read'])
    assert c.regs()['I'] == k['interrupt_vector_table'] >> 8
    assert c.memory(b['D_ACTIVE'], 1) == b'\0'
    assert c.memory(k['kb_mode'], 1) == b'\x04'
    print('PASS: Escape in bitmap mode and restoration of ZShell text display')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--emulator', type=Path, default=ROOT.parent / 'Zeal-NativeEmulator/build/zeal-native')
    parser.add_argument('--build-dir', type=Path, default=ROOT / 'build')
    parser.add_argument('--rom', type=Path, required=True, help='ZShell kernel image with HostFS enabled')
    parser.add_argument('--kernel-map', type=Path, required=True, help='os.map matching --rom')
    parser.add_argument('--tf', type=Path, help='Optional TF image; test runs against a private copy')
    parser.add_argument('--log', type=Path, help='Save full debugger transcript')
    args = parser.parse_args()
    b = symbols(args.build_dir / 'bbcbasic.map')
    k = symbols(args.kernel_map)
    with tempfile.TemporaryDirectory(prefix='bbc-zshell-') as temporary:
        directory = Path(temporary)
        shutil.copy2(args.build_dir / 'bbcbasic.bin', directory / 'bbcbasic')
        shutil.copy2(args.rom, directory / 'rom.img')
        (directory / 'empty.ini').write_text('')
        (directory / 'eeprom.img').write_bytes(b'\xff' * 65536)
        if args.tf:
            shutil.copy2(args.tf, directory / 'tf.img')
        else:
            with (directory / 'tf.img').open('wb') as stream:
                stream.truncate(4 * 1024 * 1024)
        command = [str(args.emulator.resolve()), '--console', '--debug',
                   '--config', str(directory / 'empty.ini'), '--rom', str(directory / 'rom.img'),
                   '--map', str(args.kernel_map.resolve()), '--hostfs', str(directory),
                   '--tf', str(directory / 'tf.img'), '--eeprom', str(directory / 'eeprom.img')]
        c = Console(command, directory)
        try:
            exercise(c, b, k, directory)
        except Exception:
            print(c.log[-6000:])
            raise
        finally:
            c.close()
            if args.log:
                args.log.write_text(c.log)


if __name__ == '__main__':
    main()
