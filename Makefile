SRCS = main.asm exec.asm eval.asm fpp.asm hardware.asm zos.asm ram.asm

all: build bbcbasic.com

build:
	rm -rf build/
	mkdir build/

bbcbasic.com: $(SRCS)
	z88dk-z80asm -I$(ZOS_PATH)/kernel_headers/z88dk-z80asm/ -obbcbasic.com -b -d -l -m $(SRCS)
	mv *.o *.lis *.map build/

clean:
	rm -fr *.o *.err *.lis *.map *.com *.bin build/
