# This will only work with micropython.
import ffi
import uctypes
from uctypes import BF_POS, BF_LEN
import machine
from machine import mem32
import time

#libc = ffi.open("libc.so")
libc = ffi.open(None)  # libc is also used by micropython so this will work

c_open = libc.func("i", "open", "si")
mmap = libc.func("p", "mmap", "pIiiii")

O_RDWR = 2
O_SYNC = 0x101000
PROT_READ = 1
PROT_WRITE = 2
PROT_EXEC = 4
MAP_SHARED = 1
MAP_PRIVATE = 2
MAP_FIXED = 0x10

devmem = c_open("/dev/mem", O_RDWR | O_SYNC)
#glb = mmap(0, 0x1000, PROT_READ | PROT_WRITE, MAP_SHARED, devmem, 0x20000000)
# map 0x20000000 to 0x5000000 because many peripherals are in that range
glb = mmap(0, 0x30000000, PROT_READ | PROT_WRITE, MAP_SHARED, devmem, 0x20000000)

def mkgpio(num):
    if num < 0 or num > 63:
        raise Exception("invalid gpio num")
    return uctypes.struct(glb + 0x8c4 + num*4, {
        "ie":           uctypes.BFUINT32 | 0 |  0 << BF_POS | 1 << BF_LEN,
        "smt":          uctypes.BFUINT32 | 0 |  1 << BF_POS | 1 << BF_LEN,
        "drv":          uctypes.BFUINT32 | 0 |  2 << BF_POS | 2 << BF_LEN,
        "pu":           uctypes.BFUINT32 | 0 |  4 << BF_POS | 1 << BF_LEN,
        "pd":           uctypes.BFUINT32 | 0 |  5 << BF_POS | 1 << BF_LEN,
        "oe":           uctypes.BFUINT32 | 0 |  6 << BF_POS | 1 << BF_LEN,
        "func_sel":     uctypes.BFUINT32 | 0 |  8 << BF_POS | 5 << BF_LEN,
        "int_mode_set": uctypes.BFUINT32 | 0 | 16 << BF_POS | 4 << BF_LEN,
        "int_clr":      uctypes.BFUINT32 | 0 | 20 << BF_POS | 1 << BF_LEN,
        "int_stat":     uctypes.BFUINT32 | 0 | 21 << BF_POS | 1 << BF_LEN,
        "int_mask":     uctypes.BFUINT32 | 0 | 22 << BF_POS | 1 << BF_LEN,
        "out":          uctypes.BFUINT32 | 0 | 24 << BF_POS | 1 << BF_LEN,
        "set":          uctypes.BFUINT32 | 0 | 25 << BF_POS | 1 << BF_LEN,
        "clr":          uctypes.BFUINT32 | 0 | 26 << BF_POS | 1 << BF_LEN,
        "invalue":      uctypes.BFUINT32 | 0 | 28 << BF_POS | 1 << BF_LEN,
        "mode":         uctypes.BFUINT32 | 0 | 30 << BF_POS | 2 << BF_LEN
    })
led = mkgpio(8)

gpios = uctypes.struct(glb, {
    #"value": uctypes.UINT64 | 0xac4  # segfaults
    "in0": uctypes.UINT32 | 0xac4,
    "in1": uctypes.UINT32 | 0xac8,
    "out0": uctypes.UINT32 | (0xae4-0xac4),
    "out1": uctypes.UINT32 | (0xae8-0xac4),
    "set0": uctypes.UINT32 | (0xaec-0xac4),
    "set1": uctypes.UINT32 | (0xaf0-0xac4),
    "clr0": uctypes.UINT32 | (0xaf4-0xac4),
    "clr1": uctypes.UINT32 | (0xaf8-0xac4),
    "pads": (uctypes.ARRAY | 0x8c4, 64, {
        "ie":           uctypes.BFUINT32 | 0 |  0 << BF_POS | 1 << BF_LEN,
        "smt":          uctypes.BFUINT32 | 0 |  1 << BF_POS | 1 << BF_LEN,
        "drv":          uctypes.BFUINT32 | 0 |  2 << BF_POS | 2 << BF_LEN,
        "pu":           uctypes.BFUINT32 | 0 |  4 << BF_POS | 1 << BF_LEN,
        "pd":           uctypes.BFUINT32 | 0 |  5 << BF_POS | 1 << BF_LEN,
        "oe":           uctypes.BFUINT32 | 0 |  6 << BF_POS | 1 << BF_LEN,
        "func_sel":     uctypes.BFUINT32 | 0 |  8 << BF_POS | 5 << BF_LEN,
        "int_mode_set": uctypes.BFUINT32 | 0 | 16 << BF_POS | 4 << BF_LEN,
        "int_clr":      uctypes.BFUINT32 | 0 | 20 << BF_POS | 1 << BF_LEN,
        "int_stat":     uctypes.BFUINT32 | 0 | 21 << BF_POS | 1 << BF_LEN,
        "int_mask":     uctypes.BFUINT32 | 0 | 22 << BF_POS | 1 << BF_LEN,
        "out":          uctypes.BFUINT32 | 0 | 24 << BF_POS | 1 << BF_LEN,
        "set":          uctypes.BFUINT32 | 0 | 25 << BF_POS | 1 << BF_LEN,
        "clr":          uctypes.BFUINT32 | 0 | 26 << BF_POS | 1 << BF_LEN,
        "invalue":      uctypes.BFUINT32 | 0 | 28 << BF_POS | 1 << BF_LEN,
        "mode":         uctypes.BFUINT32 | 0 | 30 << BF_POS | 2 << BF_LEN
    })
})

mcu_misc = uctypes.struct(0x20009000, {
    "mcu1_mcause": uctypes.UINT32 | 0x110,
    "mcu1_mintstatus": uctypes.UINT32 | 0x114,
    "mcu1_mstatus": uctypes.UINT32 | 0x118,
    "mcu1_sp": uctypes.BFUINT32 | 0x11c | 0 << BF_POS | 1 << BF_LEN,
    "mcu1_pc": uctypes.BFUINT32 | 0x11c | 1 << BF_POS | 31 << BF_LEN,
    "mcu1_lockup": uctypes.BFUINT32 | 0x120 | 24 << BF_POS | 1 << BF_LEN,
    "mcu1_halted": uctypes.BFUINT32 | 0x120 | 25 << BF_POS | 1 << BF_LEN,
    "mcu1_ndm_rstn_req": uctypes.BFUINT32 | 0x120 | 28 << BF_POS | 1 << BF_LEN,
    "mcu1_hart_rstn_req": uctypes.BFUINT32 | 0x120 | 29 << BF_POS | 1 << BF_LEN,
})

def core_id():
    return machine.mem32[0xF0000000]

EF_DATA_BASE     = 0x20056000
EF_CTRL_BASE     = 0x20056000
SF_CTRL_BASE     = 0x2000b000
SF_CTRL_BUF_BASE = 0x2000b600

SF_CTRL_READ = 0
SF_CTRL_WRITE = 1
SF_CTRL_CMD_1_LINE = 0
SF_CTRL_CMD_4_LINES = 1
SF_CTRL_ADDR_1_LINE = 0
SF_CTRL_ADDR_2_LINE = 1
SF_CTRL_ADDR_4_LINE = 2

SF_CTRL_0_OFFSET = 0
SF_CTRL_SF_IF_32B_ADR_EN_POS = 19
SF_CTRL_SF_ID0_OFFSET_OFFSET = 0xa0
SF_CTRL_SF_ID1_OFFSET_OFFSET = 0xa4
SF_CTRL_SF_BK2_ID0_OFFSET_OFFSET = 0xa8
SF_CTRL_SF_BK2_ID1_OFFSET_OFFSET = 0xac
SF_CTRL_2_OFFSET = 0x70
SF_CTRL_SF_ID_OFFSET_LOCK_POS = 7

def sflash_sendcmd(TODO):
    #https://github.com/bouffalolab/bl_mcu_sdk/blob/da1fa7a2895c2f18e6221aecf17684c65669a9bc/drivers/soc/bl808/std/src/bl808_sf_ctrl.c#L1467
    raise Exception("not implemented, yet")

def sflash_is_busy():
    x = mem32[SF_CTRL_BASE + SF_CTRL_SF_IF2_CTRL_1_OFFSET]
    if (x & (1<<SF_CTRL_SF_IF2_EN_POS)) != 0 and (x & (1<<SF_CTRL_SF_IF2_FN_SEL_POS)) != 0:
        offset = SF_CTRL_BASE + SF_CTRL_IF2_SAHB_OFFSET_OFFSET
    else:
        offset = SF_CTRL_BASE + SF_CTRL_IF1_SAHB_OFFSET_OFFSET
    return (mem32[offset] & (1<<SF_CTRL_IF_BUSY_POS)) != 0

def sflash_wait_not_busy(timeout=5 * 320 * 1000):
    for _ in range(timeout):
        if sflash_is_busy():
            return
        time.sleep(0.000001)
    raise Exception("timeout while waiting for flash to be not busy")

def sflash_read_reply(nb_data):
    x = b""
    while len(x) < nb_data:
        y = machine.mem32[SF_CTRL_BUF_BASE + len(x)]
        x += struct.pack("@I", y)
    return x[0:nb_data]

def sflash_transfer(nb_data, **kwargs):
    sflash_sendcmd(nb_data=nb_data, **kwargs)
    sflash_wait_not_busy()
    return sflash_read_reply(nb_data)

def sflash_get_unique_id(length):
    return sflash_transfer(cmd=[0x4b<<24], dummy_clks=4, rwflag=SF_CTRL_READ, nb_data=length)

def sflash_get_jedec_id():
    return sflash_transfer(cmd=[0x9f<<24], dummy_clks=0, rwflag=SF_CTRL_READ, nb_data=3)

def sflash_is_32bitaddrmode():
    x = mem32[SF_CTRL_BASE + SF_CTRL_0]
    return (x & (1 << SF_CTRL_SF_IF_32B_ADR_EN_POS)) != 0

def sflash_get_device_id():
    if sflash_is_32bitaddrmode:
        cmd = [(0x94<<24) | (addr>>8), (addr<24) | (readMode << 16)]
        addrSize = 5
    else:
        cmd = [(0x94<<24) | addr, (readMode << 24)]
        addrSize = 4
    return sflash_transfer(cmd=cmd, dummy_clks=2, rwflag=SF_CTRL_READ, nb_data=2, addr_mode=SF_CTRL_ADDR_4_LINES, data_mode=SF_CTRL_DATA_4_LINES)

def sflash_get_image_offset():
    return {
        "group0": {
            "bank0": mem32[SF_CTRL_BASE + SF_CTRL_SF_ID0_OFFSET_OFFSET] & ((1<<28)-1),
            "bank1": mem32[SF_CTRL_BASE + SF_CTRL_SF_BK2_ID0_OFFSET_OFFSET] & ((1<<28)-1)
        },
        "group1": {
            "bank0": mem32[SF_CTRL_BASE + SF_CTRL_SF_ID1_OFFSET_OFFSET] & ((1<<28)-1),
            "bank1": mem32[SF_CTRL_BASE + SF_CTRL_SF_BK2_ID1_OFFSET_OFFSET] & ((1<<28)-1)
        },
        "lock": (mem32[SF_CTRL_BASE + SF_CTRL_2_OFFSET] >> SF_CTRL_SF_ID_OFFSET_LOCK_POS) & 1,
    }

