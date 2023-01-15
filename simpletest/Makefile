CROSS_COMPILE=../result-toolchain-newlib/bin/riscv64-unknown-elf-
.PHONY: all simpletest-python

all: build/simpletest.bin build/simpletest.lst simpletest-python

build/simpletest.elf: simpletest.S simpletest.ld
	mkdir -p build
	$(CROSS_COMPILE)gcc $< -march=rv32ec -nostartfiles -Tsimpletest.ld -o $@
build/simpletest.lst: build/simpletest.elf
	$(CROSS_COMPILE)objdump -d $< >$@
build/simpletest.bin: build/simpletest.elf
	$(CROSS_COMPILE)objcopy $< $@ -O binary
simpletest-python: build/simpletest.bin
	echo""; echo "from bl808 import *; write_hex_to_mem(0x22020000, \"$$(hexdump $< -v --format '1/1 "%02x"')\")"

