#!/usr/bin/env python3
"""Execute the assembled Zeal adapters using the native emulator's Z80 core."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--build-dir', type=Path, default=ROOT / 'build')
p.add_argument('--emulator', type=Path, default=Path(os.environ.get(
    'ZEAL_EMULATOR_PATH', str(ROOT.parent / 'Zeal-NativeEmulator'))))
args = p.parse_args()
with tempfile.TemporaryDirectory(prefix='bbc-regression-') as directory:
    runner = Path(directory) / 'zos-regression'
    subprocess.run([os.environ.get('CC', 'cc'), '-std=c99', '-O2',
                    '-I', str(args.emulator / 'include'),
                    str(ROOT / 'tests/zos_regression.c'),
                    str(args.emulator / 'hw/z80.c'),
                    str(args.emulator / 'hw/zvb/default_font.c'), '-o', str(runner)], check=True)
    subprocess.run([str(runner), str(args.build_dir / 'bbcbasic.bin'),
                    str(args.build_dir / 'bbcbasic.map')], check=True, cwd=ROOT)
