# Build the DirectInput probes with llvm-mingw.
#   make MINGW=/path/to/llvm-mingw-*/bin
MINGW ?= $(dir $(firstword $(wildcard $(HOME)/cx-build/toolchain/llvm-mingw-*/bin/x86_64-w64-mingw32-gcc)))
CC     = $(MINGW)x86_64-w64-mingw32-gcc
LIBS   = -ldinput8 -ldxguid -lole32 -luuid -luser32

all: dienum.exe padwatch.exe rawinput.exe

%.exe: %.c
	$(CC) -O1 -o $@ $< $(LIBS)

clean:
	rm -f *.exe
