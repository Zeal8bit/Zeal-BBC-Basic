BIN=../bbcbasic.bin
SRCS = src/main.asm src/exec.asm src/eval.asm src/fpp.asm src/hardware.asm src/zos.asm src/ram.asm
BUILDDIR=build

all: build ${BIN}

build:
	mkdir ${BUILDDIR}

${BIN}:
	z88dk-z80asm -I$(ZOS_PATH)/kernel_headers/z88dk-z80asm/ -O=${BUILDDIR} -o=${BIN} -b -d -l -m $(SRCS)

clean:
	rm -fr ${BUILDDIR}/*
