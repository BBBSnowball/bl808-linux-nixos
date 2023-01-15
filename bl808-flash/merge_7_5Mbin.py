import struct
from math import inf
import argparse
import os.path
import sys

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

whole_img_base = 0xD2000

def make_regions(with_bootheader, bootheader_dir, flash_size=8*MB):
    regions = FlashRegions(flash_size)
    if with_bootheader:
        regions.add("bootheader_group0", os.path.join(bootheader_dir, "bootheader_group0.bin"), 0x00000000, 0)
        regions.add("bootheader_group1", os.path.join(bootheader_dir, "bootheader_group1.bin"), 0x00001000, 0)
    #NOTE There are additional size requirements, which are checked by the linker scripts for low_load.
    # Both low_load regions have the same load address because it will be "loaded" by XIP mapping. We make them
    # optional when we are only generating the later part of the flash.
    regions.add("low_load_m0", "low_load_bl808_m0.bin", 0x00002000, 0x58000000, optional=not with_bootheader)
    regions.add("low_load_d0", "low_load_bl808_d0.bin", 0x00052000, 0x58000000, optional=not with_bootheader)
    regions.add("dtb",         "hw.dtb.5M",             whole_img_base, 0x51ff8000)
    regions.add("opensbi",     "fw_jump.bin",           whole_img_base+0x10000, 0x3eff0000, max_size=0xc800)  # only with patched low_load_d0; otherwise, 0xc000
    regions.add("linux",       "Image.lz4",             whole_img_base+0x20000, 0x50000000)
    regions.add("linux_header", None,                   regions.linux.flash_offset - 8, 0)
    regions.add("rootfs",      "squashfs_test.img",     whole_img_base+0x480000, 0x58400000)

    return regions

def build_image(args):
    regions = make_regions(
        with_bootheader = (args.type=="whole-flash"),
        bootheader_dir = args.bootheader_dir,
        flash_size = args.flash_size_mb * MB)
    regions.read()

    # The BL Dev Cube GUI is padding the files so let's do the same. This probably not necessary
    # (and 0xff might be more suitable padding for flash) but let's do the same, for now.
    for region in [regions.low_load_m0, regions.low_load_d0]:
        if (len(region.data) % 16) != 0:
            region.data += b"\0" * (16 - len(region.data) % 16)

    # add header to Linux image (TODO: what does it do? is this for LZ4?)
    regions.linux_header.data = b'\0\0\0\x50' + struct.pack('<I', len(regions.linux.data))

    regions.check(args.check_size)

    flash_data = regions.collect_data()
    if args.type == "linux":
        # low_load_* is programmed with BLDevCube; we start at dtb
        flash_data = flash_data[whole_img_base:]
    elif args.type == "whole-flash":
        pass
    else:
        raise Exception("unexpected value for image type: %r" % (args.type,))

    with open(args.out, "wb+") as f:
        f.write(flash_data)

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
    parser.add_argument("--type", choices=["linux", "whole-flash"], default="linux",
        help="'linux' will only include OpenSBI, Linux, dtb and rootfs like the original script in bl808_linux (\"whole_img_linux.bin\"), "
        + "'whole-flash' will also include bootheader and low_load firmware")
    parser.add_argument("--out", default="whole_img_linux.bin",
        help="output file, default 'whole_img_linux.bin'")
    parser.add_argument("--flash-size-mb", type=int, default=8,
        help="flash size in megabytes (1024*1024 bytes), default 8 MB")
    parser.add_argument("--bootheader-dir", default=os.path.dirname(sys.argv[0]),
        help="directory that contains the bootheader files")
    args = parser.parse_args()

    build_image(args)

