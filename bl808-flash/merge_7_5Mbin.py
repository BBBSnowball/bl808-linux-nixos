import struct
from math import inf
import argparse
import os.path
import sys
import binascii
import hashlib

kB = 1024
MB = 1024*1024

def format_size(x):
    if (x % MB) == 0:
        return "%d MB" % (x/MB)
    elif (x % kB) == 0:
        return "%d kB" % (x/kB)
    else:
        return "%d bytes" % x

class FlashRegion(object):
    def __init__(self, from_file, flash_offset, load_address, max_size=inf, optional=False):
        self.from_file = from_file
        self.flash_offset = flash_offset
        self.load_address = load_address
        self.max_size = max_size
        self.optional = optional

    def read(self):
        if self.from_file is None:
            self.data = b""
        elif self.optional and not os.path.isfile(self.from_file):
            self.data = b""
        else:
            with open(self.from_file, 'rb') as f:
                self.data = f.read()

class FlashRegions(object):
    def __init__(self, flash_size):
        self.flash_size = flash_size
        self.regions = {}

    def add(self, name, *args, **kwargs):
        v = FlashRegion(*args, **kwargs)
        self.regions[name] = v
        setattr(self, name, v)

    def read(self):
        for k,v in self.regions.items():
            v.read()

    def check(self, do_check):
        # reduce max_size based on where the next item starts in flash
        next_start = self.flash_size
        for region in sorted(self.regions.values(), key=lambda x: x.flash_offset, reverse=True):
            #print("DEBUG: offset=%08x, next=%08x, diff=%08x" % (region.flash_offset, next_start, next_start - region.flash_offset))
            region.max_size = min(region.max_size, next_start - region.flash_offset)
            next_start = region.flash_offset

        for k,v in self.regions.items():
            currsz = len(v.data)
            maxsz = v.max_size
            print("%-23s %8d (%3d %%, max %7s)" % (k + " size:", currsz, 100*currsz/maxsz, format_size(maxsz)))
            if do_check and len(v.data) > v.max_size:
                raise Exception("Region %s is too big: %d > %d" % (k, currsz, maxsz))

    def collect_data(self):
        data = bytearray(b'\xff' * self.flash_size)
        for k,v in self.regions.items():
            data[v.flash_offset:v.flash_offset+len(v.data)] = v.data
        return data

#NOTE We are only generating the bootheader for group1 here because
#     bflb-mcu-tool can generate group0 for single-core M0 just fine.
#     In addition, we need bflb-mcu-tool to do this because the header
#     for group0 is written together with the flash config, which
#     is adjusted to whatever flash is found on the board, i.e. we
#     cannot generate it in advance.

# This template is based on what the Dev Lab GUI writes into flash.
# The fields are listed in libs/bl808/bootheader_cfg_keys.py in
# bflb-mcu-tool and bflb-iot-tool.
bootheader_group1_template = (
    0x50414642, 0x00000001, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x74ccea76, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x0fd59b8d,
    0x65400100, 0x00052000, 0x00000000, 0xcccccccc, # 0x0080
    0xcccccccc, 0xcccccccc, 0xcccccccc, 0xcccccccc, # 0x0090
    0xcccccccc, 0xcccccccc, 0xcccccccc, 0xcccccccc,
    0x00000000, 0x00000000, 0x00000000, 0x00052000,
    0xd8000000, 0x00000000, 0x00000001, 0x00000000,
    0x00000000, 0x00000000, 0x58000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00082000,
    0x58040000, 0x00000000, 0x00000000, 0x00000000,
    0x00000160, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x20000320, 0x00000000,
    0x2000f038, 0x18000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0xcccccccc, # 0x0150
)

def make_bootheader_group1(regions):
    words = list(bootheader_group1_template)
    data = bytearray(struct.pack("<88I", *bootheader_group1_template))

    firmware = regions.low_load_d0.data
    struct.pack_into("<I", data, 0x008c, len(firmware))
    data[0x0090:0x00b0] = hashlib.sha256(firmware).digest()

    struct.pack_into("<I", data, 0x015c,
                     binascii.crc32(data[0:-4]))

    regions.bootheader_group1.data = data

whole_img_base = 0xD2000

def make_regions(flash_size=8*MB):
    regions = FlashRegions(flash_size)
    regions.add("bootheader_group0", None, 0x00000000, 0)
    regions.add("bootheader_group1", None, 0x00001000, 0)

    #NOTE There are additional size requirements, which are checked by the linker scripts for low_load.
    # Both low_load regions have the same load address because it will be "loaded" by XIP mapping. We make them
    # optional when we are only generating the later part of the flash.
    regions.add("low_load_m0", "low_load_bl808_m0.bin", 0x00002000, 0x58000000)
    regions.add("low_load_d0", "low_load_bl808_d0.bin", 0x00052000, 0x58000000)

    # These regions will be included in whole_img_linux.bin.
    regions.add("dtb",         "hw.dtb.5M",             whole_img_base, 0x51ff8000)
    regions.add("opensbi",     "fw_jump.bin",           whole_img_base+0x10000, 0x3eff0000, max_size=0xc800)  # only with patched low_load_d0; otherwise, 0xc000
    regions.add("linux",       "Image.lz4",             whole_img_base+0x20000, 0x50000000)
    regions.add("linux_header", None,                   regions.linux.flash_offset - 8, 0)
    regions.add("rootfs",      "squashfs_test.img",     whole_img_base+0x480000, 0x58400000)

    return regions

def build_image(args):
    regions = make_regions(args.flash_size_mb * MB)
    regions.read()

    # The BL Dev Cube GUI is padding the files so let's do the same. This probably not necessary
    # (and 0xff might be more suitable padding for flash) but let's do the same, for now.
    for region in [regions.low_load_m0, regions.low_load_d0]:
        if (len(region.data) % 16) != 0:
            region.data += b"\0" * (16 - len(region.data) % 16)

    # generate bootheader for group1 (must be done after reading and padding low_load_d0)
    make_bootheader_group1(regions)

    # add header to Linux image (TODO: what does it do? is this for LZ4?)
    regions.linux_header.data = b'\0\0\0\x50' + struct.pack('<I', len(regions.linux.data))

    regions.check(args.check_size)

    flash_data = regions.collect_data()

    for output_file, data in (
            (args.out_bootheader_group1, regions.bootheader_group1.data),
            (args.out_low_load_d0_padded, regions.low_load_d0.data),
            # low_load_* is programmed seperately; we start at dtb
            (args.out, flash_data[whole_img_base:])
        ):
        if output_file:
            with open(output_file, "wb") as f:
                f.write(data)

def parse_bool(x):
    if x == "false" or x == "False" or x == "no" or x == "0":
        return False
    elif x == "true" or x == "True" or x == "yes" or x == "1":
        return True
    else:
        raise Exception("invalid boolean: %r" % (x,))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        prog="merge_7_5Mbin.py",
        description="Merge parts of Linux for bl808 into a complete image. Input files will be read from the current directory.")
    parser.add_argument("--check-size", type=parse_bool, default=True,
        help="set to 'no' to disable size checks")
    parser.add_argument("--out", default="whole_img_linux.bin",
        help="output file for linux image, default 'whole_img_linux.bin'")
    parser.add_argument("--out-bootheader-group1", default="bootheader_group1.bin",
        help="output file for bootheader of group1, default 'bootheader_group1.bin'")
    parser.add_argument("--out-low-load-d0-padded", default="low_load_bl808_d0_padded.bin",
        help="output file for padded low_load_d0, default 'low_load_bl808_d0_padded.bin'")
    parser.add_argument("--flash-size-mb", type=int, default=8,
        help="flash size in megabytes (1024*1024 bytes), default 8 MB")
    args = parser.parse_args()

    build_image(args)

