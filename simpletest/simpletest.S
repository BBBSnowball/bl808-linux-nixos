# result-toolchain-newlib/bin/riscv64-unknown-elf-gcc x.S -march=rv32ec -nostartfiles -Tx.ld
.globl _start
_start:
.option norvc
.option pic
li x1, 123
li x2, 0x3effc840
sw x1, 0(x2)
1: j 1b
