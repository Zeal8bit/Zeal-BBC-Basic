#!/usr/bin/env python3
"""Reject overlap between the flat image, runtime workspace and BASIC memory."""
from pathlib import Path
import re
import sys

binary, map_file = map(Path, sys.argv[1:])
symbols = {}
for line in map_file.read_text().splitlines():
    match = re.match(r'(\w+)\s+= \$([0-9A-Fa-f]+)', line)
    if match and (match[1] not in symbols or ', public,' in line):
        symbols[match[1]] = int(match[2], 16)


def require(condition, message):
    if not condition:
        raise SystemExit('Invalid BASIC memory layout: ' + message)


size = binary.stat().st_size
require(symbols['__head'] == 0x4000, 'wrong load address')
require(symbols['__tail'] == 0x4000 + size, 'image length disagrees with linker')
require(symbols['WORKSPACE_BASE'] >= symbols['__tail'], 'workspace overlaps executable')
require(symbols['WORKSPACE_END'] <= symbols['USER'] < 0xE000, 'insufficient BASIC memory')
for name in ('ACCS', 'BUFFER', 'STAVAR', 'USER'):
    require(symbols[name] % 256 == 0, name + ' must be page aligned')
require(symbols['INCREM'] < symbols['STAVAR'] + 256, 'cold-start variable purge is too short')
regions = [('ACCS', 256), ('BUFFER', 256), ('STAVAR', 256),
           ('D_ORIGINAL_FONT', 3072), ('G_SPANS', 800), ('D_PARAMS', 9),
           ('D_GLYPH', 12), ('D_CURSOR', 2), ('FILE_CHANNELS', 128),
           ('OPTVAL', 1), ('KEY_QUEUE', 16), ('KEY_EVENTS', 64), ('ZOS_BUFFER', symbols['ZOS_STAT_SIZE'])]
previous_end = symbols['__tail']
for name, length in regions:
    require(previous_end <= symbols[name], name + ' overlaps preceding region')
    previous_end = symbols[name] + length
require(previous_end == symbols['WORKSPACE_END'], 'workspace end disagrees with buffers')
for name in ('VIDEO_ACCESS_END', 'IRQ_RETURN', 'ZOS_SYSCALL'):
    require(symbols[name] < 0x8000, name + ' must remain below the video mapping')
print(f'Image {size} bytes; runtime workspace '
      f'{symbols["USER"] - symbols["WORKSPACE_BASE"]} bytes; PAGE=&{symbols["USER"]:04X}')
