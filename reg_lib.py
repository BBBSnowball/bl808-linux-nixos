import ffi
import uctypes
from uctypes import BFUINT32, BF_POS, BF_LEN
import machine
from machine import mem32
import time

class Mmapper(object):
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

    mappings = []
    devmem = None

    @classmethod
    def map_dev_mem(cls, address, size):
        if cls.devmem is None:
            cls.devmem = cls.c_open("/dev/mem", cls.O_RDWR | cls.O_SYNC)
        base = address / 4096 * 4096
        size = (size+4095)/4096*4096
        for m in cls.mappings:
            if base >= m[0] and base+size <= m[1]:
                base = m[0]
                return m[2] + (address-base)
        if 0x20000000 <= base and base+size <= 0x50000000:
            # map 0x20000000 to 0x5000000 because many peripherals are in that range
            base = 0x20000000
            size = 0x30000000
        vma = cls.mmap(0, size, cls.PROT_READ | cls.PROT_WRITE, cls.MAP_SHARED, cls.devmem, base)
        cls.mappings.append((base, size, vma))
        return vma + (address-base)

class HexInt(int):
    def __repr__(self):
        if self > 0xffff:
            return "0x%08x" % self
        else:
            return "0x%x" % self

class Register(object):
    __slots__ = ("name", "uctype", "offset", "peripheral", "_ref")

    def __init__(self, name, offset, *args):
        self.name = name
        self.peripheral = None
        self.offset = offset
        self._ref = None

        self.uctype = {"value32": uctypes.UINT32 | 0}
        for name, pos, len in args:
            self.uctype[name] = BFUINT32 | 0 | pos << BF_POS | len << BF_LEN

    @property
    def ref(self):
        if self._ref is None:
            self._ref = uctypes.struct(self.peripheral.mmap_address + self.offset, self.uctype)
        return self._ref

    def pos(self, name):
        return (self.uctype[name] >> BF_POS) & 0x1f

    def len(self, name):
        return (self.uctype[name] >> BF_LEN) & 0x1f

    @property
    def address(self):
        return self.peripheral.address + self.offset

    def __repr__(self):
        if self.peripheral is None:
            return "<Register %s at 0x%08x>" % (self.name, self.offset)
        else:
            return "<Register %s of %s at 0x%08x>" % (self.name, self.peripheral.name, self.address)

    @property
    def value(self):
        return HexInt(self.ref.value32)

#class AttrDict(dict):
#    def __getattr__(self, name):
#        if name in self:
#            return self[name]
#        else:
#            super().__getattr__(name)

#class AttrDict(object):
#    __slots__ = ("_dict")
#
#    def __init__(self, value={}):
#        object.__setattr__(self, "_dict", value)
#
#    def __getattr__(self, name):
#        if name != "_dict" and name in self._dict:
#            return self._dict[name]
#        else:
#            #object.__getattr__(self, name)
#            raise AttributeError("object has no attribute %r" % (name,))
#
#    #def __setattr__(self, name, value):
#    #    self._dict[name] = value
#
#    def __setitem__(self, name, value):
#        self._dict[name] = value
#
#    @property
#    def dict(self):
#        return self._dict
#
#    def __repr__(self):
#        return repr(self._dict)

class AttrDict(object):
    def __setitem__(self, name, value):
        setattr(self, name, value)

    def __repr__(self):
        return repr(self.__dict__)

class Peripheral(object):
    __slots__ = ("_uctype", "_registers", "name", "_address", "_mmap_address", "_size", "_lazy_init", "_ref")

    def __init__(self, name, address, lazy_init):
        self.name = name
        self._address = address
        self._lazy_init = lazy_init
        self._size = 0
        self._ref = None

    def _init(self):
        regs = self._lazy_init()

        self._uctype = {}
        self._registers = AttrDict()
        size = max(0x1000, self._size)
        for reg in regs:
            reg.peripheral = self
            self._registers[reg.name] = reg
            self._uctype[reg.name] = (reg.offset, reg.uctype)
            if reg.offset+4 > size:
                size = reg.offset+4
        self._size = size

        self._lazy_init = None

    def _init_mmap(self):
        if self._lazy_init is not None:
            self._init()
        self._mmap_address = Mmapper.map_dev_mem(self.address, self._size)
        self._ref = uctypes.struct(self._mmap_address, self.uctype)

    def __repr__(self):
        return "<Peripheral %s at 0x%08x>" % (self.name, self._address)

    # address is readonly because it will be cached by child objects
    @property
    def address(self):
        return self._address
    # the others are properties due to lazy initialization
    @property
    def uctype(self):
        if self._lazy_init is not None:
            self._init()
        return self._uctype
    @property
    def regs(self):
        if self._lazy_init is not None:
            self._init()
        return self._registers
    @property
    def size(self):
        if self._lazy_init is not None:
            self._init()
        return self._size
    @property
    def mmap_address(self):
        if self._ref is None:
            self._init_mmap()
        return self._mmap_address
    @property
    def ref(self):
        if self._ref is None:
            self._init_mmap()
        return self._ref

def _glb_regs():
    return [
            Register("soc_info0", 0x0, ("chip_rdy", 27, 1), ("id", 28, 4)),
            Register("gpio_8", 0x8e4, ("ie", 0, 1), ("oe", 6, 1), ("o", 24, 1)),
    ]
GLB = Peripheral("GLB", 0x20000000, _glb_regs)

