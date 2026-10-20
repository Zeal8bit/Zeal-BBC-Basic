# BBC Basic for Zeal 8-bit Computer

This is a modified source code based on [BBC BASIC+ for Z80](https://github.com/jblang/bbcbasic-z80) by (J.B. Langston)[@jblang],
originally modified from the [BBC BASIC (Z80)](http://www.bbcbasic.co.uk/bbcbasic/z80basic.html) by R.T. Russell, which is released under the [zlib](COPYING) licese at the request of David Given. David published the sources as part of his [cpmish](https://github.com/davidgiven/cpmish) project.

The original sources released by R.T. Russell are in the initial commit.  The following modifications have been made:

- Modified sources to assemble with [z88dk](https://github.com/z88dk/z88dk)'s z80asm
- Fixed a [bug](https://github.com/davidgiven/cpmish/issues/20) that causes the RUN command to hang under emulators.
- Moved hardware-specific functions from patch.asm to hardware.asm.
- Implemented CLS, TAB, and COLOUR using ANSI escape codes
- Added a Makefile and this README
- Reformatted the source with [z80-macroasm](https://marketplace.visualstudio.com/items?itemName=mborik.z80-macroasm) for VSCode

## Build Instructions

Use the [Zeal development environment](https://github.com/Zeal8bit/zeal-dev-environment) to build `build/bbcbasic.bin`:

```sh
zde cmake
```
