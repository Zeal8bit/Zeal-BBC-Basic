SRCS = src/main.asm src/exec.asm src/eval.asm src/fpp.asm src/hardware.asm src/zeal-os.asm src/ram.asm

all: build bbc.bin

build:
	mkdir build/

bbc.bin:
	z88dk-z80asm -I$(ZOS_PATH)/kernel_headers/z88dk-z80asm/ -O=build -o=bbc.bin -b -d -l -m $(SRCS)

clean:
	rm -fr build/*
