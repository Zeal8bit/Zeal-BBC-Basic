#!/usr/bin/env python3
"""Attribute the existing Zeal Lander benchmark using debugger breakpoints only."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re

from benchmark_lander import sha256, zeal_trial
from zshell_integration import Console, ROOT, symbols


class ProfileConsole(Console):
    def start_profile(self, b, _cycles):
        self.entries = {b[name]: name for name in (
            'OSWRCH', 'D_DRAW_GLYPH', 'G_TRANSFORM', 'G_PLOT',
            'POLL_INPUT', 'Z_TIME_REFRESH', 'GETIME')}
        self.b = b
        self.stack = []
        self.cost = Counter()
        self.calls = Counter()
        self.characters = Counter()
        self.active = True
        for address in self.entries:
            self.bp(address)

    def run(self, states=1_000_000):
        if not getattr(self, 'active', False):
            return super().run(states)
        while True:
            reply = self.send('continue')
            match = re.search(r'Paused @ 0x([0-9a-f]+) \(cyc=(\d+)\)', reply)
            assert match, reply
            pc, cycles = int(match[1], 16), int(match[2])
            returned = False
            # Tail calls can make multiple measured routines share one return.
            while self.stack and pc == self.stack[-1]['return']:
                returned = True
                frame = self.stack.pop()
                elapsed = cycles - frame['start']
                self.cost[frame['name']] += elapsed - frame['children']
                if self.stack:
                    self.stack[-1]['children'] += elapsed
                if pc not in self.entries and not any(f['return'] == pc for f in self.stack):
                    self.clear(pc)
            if pc not in self.entries:
                if returned:
                    continue
                if self.stack:
                    raise AssertionError(f'Unexpected stop inside profile: {pc:04x}')
                return
            name = self.entries[pc]
            r = self.regs()
            if name == 'OSWRCH':
                state = self.memory(self.b['D_GRAPH_TEXT'], 1)[0]
                char = r['AF'] >> 8
                kind = ('graphics delete' if char == 127 else 'graphics character' if char >= 32
                        else 'graphics control') if state else ('text character' if char >= 32 else 'text control')
                name += ': ' + kind
                self.characters[kind] += 1
            if name == 'D_DRAW_GLYPH':
                name += ': ' + self.stack[-1]['name'].split(': ', 1)[-1]
            target = int.from_bytes(self.memory(r['SP'], 2), 'little')
            self.stack.append({'name': name, 'start': cycles, 'children': 0, 'return': target})
            self.calls[name] += 1
            self.bp(target)
            # run resumes past the current breakpoint; no guest code is changed.

    def finish_profile(self, total):
        assert not self.stack
        accounted = sum(self.cost.values())
        self.cost['interpreter and other'] = total - accounted
        return dict(total_cycles=total, exclusive_cycles=dict(self.cost), calls=dict(self.calls),
                    output_bytes=dict(self.characters))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--rom', type=Path, required=True)
    p.add_argument('--kernel-map', type=Path, required=True)
    p.add_argument('--emulator', type=Path, default=ROOT.parent / 'Zeal-NativeEmulator/build/zeal-native')
    p.add_argument('--build-dir', type=Path, default=ROOT / 'build')
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    result = zeal_trial(args, symbols(args.build_dir / 'bbcbasic.map'), ProfileConsole)
    result['inputs'] = {
        'binary_sha256': sha256(args.build_dir / 'bbcbasic.bin'),
        'source_sha256': sha256(ROOT / 'examples/gfx/lander.bas'),
        'emulator_sha256': sha256(args.emulator),
        'kernel_sha256': sha256(args.rom),
    }
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    for name, cycles in sorted(result['profile']['exclusive_cycles'].items(), key=lambda pair: -pair[1]):
        print(f'{name:30} {cycles:12,d} {cycles / result["cycles"]:7.2%}')
    print(f'Total: {result["cycles"]:,} cycles; {result["updates_per_second"]:.6f} updates/s')


if __name__ == '__main__':
    main()
