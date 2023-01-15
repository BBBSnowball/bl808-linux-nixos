from bl808_regs import *
import time
from ubinascii import hexlify, unhexlify
import ustruct
from machine import mem32

def delay_us(us):
    time.sleep(us*1e-6)

def glb_halt_cpu(cpu, halt):
    if cpu == GLB_CORE_ID.M0:
        PDS.regs.CPU_CORE_CFG1.ref.REG_MCU1_CLK_EN = !halt
        delay_us(1)
        GLB.regs.SWRST_CFG2.ref.REG_CTRL_SYS_RESET = halt
    elif cpu == GLB_CORE_ID.D0:
        MM_GLB.regs.MM_CLK_CTRL_CPU.ref.REG_MMCPU0_CLK_EN = !halt
        delay_us(1)
        MM_GLB.regs.MM_SW_SYS_RESET.ref.REG_CTRL_MMCPU0_RESET = halt
    elif cpu == GLB_CORE_ID.LP:
        PDS.regs.CPU_CORE_CFG0.ref.REG_PICO_CLK_EN = !halt
        delay_us(1)
        GLB.regs.SWRST_CFG2.ref.REG_CTRL_PICO_RESET = halt
    else:
        raise Exception("invalid cpu")

def glb_set_cpu_reset_address(cpu, address):
    if cpu == GLB_CORE_ID.M0:
        PDS.regs.CPU_CORE_CFG14.ref.value32 = addr
    elif cpu == GLB_CORE_ID.D0:
        MM_MISC.regs.CPU0_BOOT.ref.value32 = addr
    elif cpu == GLB_CORE_ID.LP:
        PDS.regs.CPU_CORE_CFG13.ref.value32 = addr
    else:
        raise Exception("invalid cpu")

def bl_boot_cpu(cpu, address):
    glb_halt_cpu(cpu, True)
    glb_set_cpu_reset_address(cpu, address)
    glb_halt_cpu(cpu, False)
# -> doesn't seem to work for M0
# -> CPU hangs (including JTAG debugger for D0) when I do `mem32[0x22020040]` after LP has written to it
#
# program counter of M0 is in MCU_MISC.regs.MCU1_LOG4.value
# mcause of M0 is in MCU_MISC.regs.MCU1_LOG1.value and we see values that are written by low_load

def write_hex_to_mem(address, hex):
    x = unhexlify(hex)
    words = ustruct.unpack("@%dI"%((len(x)+3)/4), x)
    for i, w in enumerate(words):
        mem32[address+4*i] = w

