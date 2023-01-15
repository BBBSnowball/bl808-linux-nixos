My first steps with BL808 and Linux.

I'm using M1s dock, for now (because of its easy-to-use JTAG adapter) but my long-term plan is to use Ox64 boards.

We are using Nix to orchestrate the build and we are using nixpkgs to provide dependencies. Nonetheless, you don't
need NixOS to build it.

Quickstart
==========

This will assume that you know how nix works and how to flash the M1s dock board. If not, consider reading the longer
instructions below.

- Build: `nix build github:BBBSnowball/bl808-linux-nixos -o result-linux`
- Start Dev Cube: `nix run github:BBBSnowball/bl808-linux-nixos#BLDevCube -o result-linux`
- Flash `low_load` binaries (from `result-linux` directory) according to the usual instructions.
- Flash root image: `nix run github:BBBSnowball/bl808-linux-nixos#bl808-linux-2-flash-img --port /dev/ttyUSB1`

Goals
=====

- Include all the tools that are needed, e.g. compilers and flash tools.
  - This is using nix so everything will be pinned to known-good versions.
- Get rid of as many "blobs" and non-standard repos as we can.
  - Compile toolchain from source.
  - Apply patches on top of upstream Linux rather than using Bouffallo's copy without history.
  - Build the rootfs with packages from nixpkgs. Bouffallo's is a blob without any sources.
  - TODO: Avoid closed-source GUI tools for flashing. Use Bouffallo's Python tools and remove prebuilt libraries (e.g. we don't have to support ck-link).
- Have things working out-of-the-box, ideally with a single command (assuming nix is already installed).
  - TODO: We still need the GUI to flash `low_load` because Bouffallo's CLI tools don't seem to be able to do this, yet.
    (Or at least I couldn't get them to do it. They don't seem to support multi-core and even a single core doesn't start if I use those tools.)
  - TODO: Fix exit code of Bouffallo's tools. This is ok for now because it works in the GUI and we only have one
    flash command after that (i.e. the user is likely to notice errors).
  - TODO: Or look into how much work it would be to make [blisp](https://github.com/pine64/blisp) work for bl808.
- Essential drivers:
  - remoteproc
    - communication between M0 and D0 cpus
    - load M0 firmware from Linux (if possible; my experiments haven't worked so far)
    - Linux seems to support virtio over rpmsg channels so we can use this to bridge drivers in `bl_mcu_sdk` or `bl_iot_sdk`
      to Linux, e.g. wifi.
    - I would like to also have this for the LP cpu. It is smaller but it would still make an excellent real-time
      co-processor, I think. Unfortunately, there isn't much documentation on this.
      - This will need a gcc that supports RV32E, e.g. the t-head / xuantie fork. We want to use that anyway because
        it has some other improvements.
  - USB (UDC)
    - This will be very useful development - especially while we don't have any WiFi driver, yet.
  - WiFi
    - There isn't much documentation about the low-level implementation so we will have to use the driver in `bl_iot_sdk`,
      which has a precompiled library that will most likely only work on the M0 core.
    - We will want a proper driver with the supplicant running in Linux. However, we may start with a virtio-net driver.
  - ~~Thread / Matter (`lmac154`)~~
    - `bl_iot_sdk` has a driver for another SoC but it is unclear whether we will get one for bl808 and whether it would support
      Thread or only Zigbee. I have read in the Bouffallo form that `lmac154` for bl808 will only be available under NDA.
    - There is Matter support for some of Bouffallo's SoCs but that's only WiFi and BLE (but I haven't looked in any details so
      I could be mistaken).
    - This would be a good reason to "upgrade" from ESP32. If we don't get it and new Espressif SoCs get good support for it,
      that's bad news for bl808.
  - pinctrl, DMA, etc.
- Network boot:
  - The boards are cheap so an SD card adds significant cost.
  - I would mostly use them to replace ESP32 for home-automation so in many cases they will have a good WiFi connection anyway.
    RAM is much larger than flash so we should be able to load most things over network.
  - If we are really lucky, we might even be able to fit the netboot stub into 2 MB to make it work with the cheaper board.
    However, the current kernel+rootfs barely fits into 8 MB so this is not so likely.
    - We *could* have a non-Linux netboot firmware that boots into Linux. My goal is to get away from vendor wifi implementations
      so I don't think that I will go down that route just to save $2.
  - All the things that are needed for WiFi must be available without WiFi, of course. If parts are identical to what netboot uses,
    we can mount it from flash. Otherwise, we copy it to RAM (e.g. tmpfs or squashfs in RAM) as part of netboot.
- Write some drivers for linux-iio (if I find the time).
- Make device trees easier.
  - If Linux for bl808 becomes popular, we will have users switching from ESP32. We should make this easy.
  - At the minimum, we need good documentation on how to write device trees for the easy cases ("I want an ADC on that pin").
  - It would be useful to also explain advanced cases that wouldn't be possible without device trees, e.g. load a driver for an
    HD44780 display that is attached via an I2C port expander.
  - Maybe even create a config GUI.

How to use it
=============

NOTE: This is not much more than the very bare-bones linux that is provided by Bouffallo, i.e. you will have UART
and busybox but not much more.

NOTE: We will need a board with at least 8 MB of flash (8 MB = 256 Mbit). In addition, the UART pinout is different for
M1s dock and Ox64 so this will only work for M1s dock, for now (but a variant for Ox64 can and will be added).

1. Install nix, see [here](https://nixos.org/download.html):
  - `sh <(curl -L https://nixos.org/nix/install) --daemon`
  - Nix can be installed on any Linux and on Mac OS. However, this has only been tested with 64-bit Linux, so far.
    Some parts of the build use prebuilt tools from Bouffallo and we only download the 64-bit Linux variants of those, for now.
2. Enable flakes, see [here](https://nixos.wiki/wiki/Flakes#Enable_flakes):
  - Add `experimental-features = nix-command flakes` to `/etc/nix/nix.conf`.
3. Build Linux image and firmware/bootloader/OpenSBI:
  - This assumes that you have cloned this git. `.` or `.#` in these instructions refers to the path of the git.
  - `nix build -L . -o result-linux`
  - This will build the toolchain from source so expect this to take some time. The results will be cached in
    `/nix/store` so further runs will be faster.
4. Download Bouffallo tools and create symlinks for easy access (optional):
  - `nix build -L .#bflb-tools -o result-tools` (e.g. BLDevCube, optional if you already have BLDevCube)
  - `nix build -L .#keep-downloads -o keep-downloads` (raw downloads, optional)
4. Flash first stage loader (`low_load`):
  - `nix run .#BLDevCube` (or download Dev Cube from Bouffallo and start that, e.g. for Mac OS)
  - This is step 2 of `keep-downloads/prebuilt-linux/steps.md` but use the files in `./result-linux` (see above).
    This instruction is rather short (so read on) but the image is useful.
  - Here is a step-by-step guide of what to do:
    - Connect to "UART" USB port of M1s dock. There will be two tty ports, e.g. ttyUSB0 and ttyUSB1.
      The one with the higher number is for the M0 cpu. We need that one for programming.
    - Put the board into bootloader mode: Press and hold the BOOT button, then press the reset (RST) button, then release BOOT.
      - You can usually do the same by pressing BOOT while connecting power. This won't work for M1s dock because it will also
        boot the BL702 in a different mode.
      - TODO: RST/PU_CHIP is connected to U1RTS and BOOT to U1DTR. Can we automatically enter the bootloader with that?
        (I think that I have seen something about DTR in some log but I always had to manually enter the bootloader.)
        - `bflb_interface_uart.py` indeed uses DTR and RTS. There are several options to invert things so I should certainly
          check this out as soon as I have working hardware again.
    - Switch to the MCU tab of Dev Cube.
    - M0 Group: Set `group0`, image address 0x58000000, file `./result-linux/low_load_bl808_m0.bin` ("m0" and ".bin")
    - D0 Group: Set `group1`, image address 0x58000000, file `./result-linux/low_load_bl808_d0.bin` ("d0" and ".bin")
    - On the right side, select UART, the higher one of the ttyUSB ports (e.g. ttyUSB1) and 2000000 baud (2Mbaud).
    - Click "Create & download".
  - In case you want to know what that does:
    - The settings will be written into two config headers at the start of flash. The one for group0 is at 0x0000, the one
      for group1 is at 0x1000. The bootrom will read these headers and start our firmware accordingly.
    - `load_load_bl808_*.bin` are written to address 0x2000 (group0, M0) resp. 0x52000 (group1, D0). The files contain
      raw RISC-V instructions. The `result-linux` directory also includes ".elf" (with debug symbols) and ".asm" (assembly text)
      files of these programs. Have a look at the ".asm" if you are curious.
      - Actually, the GUI creates the files `img_group0.bin` and `img_group1.bin`, which are slightly different from our
        binaries. As far as I can tell, they are just zero-padded to a multiple of 16 bytes.
    - 0x58000000 is the start of the flash execute-in-place (XIP) region. The bootrom will map the start of our `low_load`
      binaries to this address. Execute-in-place means that the flash will act like a memory-mapped ROM so we can
      run programs from flash without loading them into RAM.
    - We are using the same address for both processors/groups. This might seem unusual but each processor (or rather each
      group, I assume) have there own memory mapping. Therefore, M0 and D0 will see different data when looking at 0x58000000,
      namely the start of their own `low_load` program. That way, we can use a similar linker script for both `low_load` programs
      and the hardware will adjust the offset for us.
    - As a side note, this mapping is a simple offset in the flash and 0x58000000 is the start of the range. This means that
      `low_load` can access later parts of the flash (e.g. OpenSBI and kernel image) but addresses near the start of flash will
      fall out of the XIP memory range and thus they are not accessible via XIP (unless we change the offset, which we can
      do at runtime if we want). We can still access these parts, of course, but we have to use the `SF_CTRL` peripheral for that.
    - `low_load` for M0 won't do much, yet. It can communicate with D0 and provide firmware services but these parts still have to be
      written. @alexhorner and @arm000 seem to be working on that.
      - My variant of `low_load` will enable JTAG on the SD card pins. This is useful with M1s dock board and the Sipeed RV-Debugger
        but it will interfere with normal usage of SD card, of course.
    - `low_load` for D0 will copy OpenSBI, device tree and Linux kernel to RAM. Then, it will jump to OpenSBI, which will initialize
      some peripherals and then start Linux. OpenSBI will remain in memory because it provides service calls for Linux.
    - If we figure out how to generate the config headers, we should be able to program these parts without using the GUI.
      - Good news on that: The headers seem to be constant.
      - Not so good news: The tool also seems to write efuses every time - which I found out because that seems to have bricked my
        test board when I was programming with the GUI while picocom was still attached to the tty. Oops. This is only weak evidence
        because it could also be that bad data in flash is breaking the bootloader or the hardware could be broken in other ways.
      - This file is probably also constant and `bflb_eflash_loader.py` in bflb-mcu-tool calls `self.efuse_load_specified` with such
        a file, i.e. I think we will be able to do this without the GUI.
    - In addition, it would be very useful if we can switch 
5. Flash OpenSBI, device tree, Linux kernel and rootfs:
  - You should still be in bootloader mode. If not, see previous step.
  - `nix run .#bl808-linux-2-flash-img --port /dev/ttyUSB1`
  - (or if you prefer the manual way: `result-tools/bin/bflb-iot-tool --chipname bl808 --port /dev/ttyUSB1 --baudrate 2000000 --addr 0xD2000  --firmware result-linux/whole_img_linux.bin  --single`)
  - The Bouffallo tools love to swallow errors so don't trust the exit code. It should print "All success" when successful.
  - You can repeat this step if you want to update the rootfs.
6. Connect terminal to D0 cpu:
  - `picocom -b 2000000 /dev/ttyUSB0`
7. Press the reset button (RST). You should see Linux booting. You can login as `root` with no password.
  - The rootfs has `screen` but this isn't working so well over UART. If you use it, you might want to change the escape key for picocom (e.g. `--escape b`).
  - The rootfs has `rz` and `sz` for z-modem file transfer. If you want to use that, don't use screen (the z-modem support in screen doesn't help here).
8. Some interaction with peripherals (optional).
  - We don't have many drivers, yet (not even pinctrl and gpio), so we are using `/dev/mem`, for now.
  - This will only work if the memory range of the `GLB` peripheral is mapped by the MMU. The device tree in this repo takes care of that.
  - You can use the `devmem` tool that is included with busybox to "peek and poke" peripherals. The rootfs in this repo includes
    two scripts for that: `/usr/bin/led` and `/usr/bin/buttons`.
  - The scripts are for M1s dock. If you use a different board, adjust the offsets. GPIO0 is at 0x200008c4, GPIO1 is at 0x200008c8.
  - The BOOT button on M1s dock shouldn't be used at runtime because it shares a pin with flash. If you reconfigure it to GPIO function,
    you will see squashfs error next time the kernel tries to read a page from flash.
9. Debugging (optional - except you are an early adopter so you probably want this):
  - There doesn't seem to be any default pinout for JTAG. Instead, `low_load` will have to set the pinmux and thereby choose which
    processor is available on which pins.
    - This is very unfortunate because it means that we cannot use JTAG for unbricking and we cannot debug through a reset (if you do press
      reset, do `target remote ...` again or DebugServer and sometimes gdb will crash).
    - Fun fact: The datasheet only mentions JTAG mappings for M0 and D0 but they omit function 25, which is for LP (the low-power processor)
      according to the header files.
    - Unfortunately, debugging has only worked for the D0 cpu, for me. This could be simple user error, though (e.g. I might have to
      use a different DebugServer for 32-bit RISC-V or change its configuration).
  - We should be able to use OpenOCD eventually but I haven't tried this, yet. I may have to switch to a different JTAG adapter for that.
  - Start Bouffallo's debug server: `./result-tools/bin/DebugServerConsole`
  - Start gdb: `./result-toolchain-linux/bin/riscv64-unknown-linux-gnu-gdb`
  - Setup gdb:
    - `target remote 127.0.0.1:1025` (connect to debug server)
    - `file ./result-linux/Image.elf` (load symbols for Linux kernel - make sure that it matches the one on the board or the result will be confusing)
    - `continue`
  - If you want to poke at peripherals:
    - Keep in mind that there is an MMU, i.e. addresses for D0 may be different from physical addresses in the datasheet. The linux kernel
      will add mappings for peripherals in the device tree, e.g. you can add them as type "generic-uio". This is necessary if you want to
      use `/dev/mem` in Linuxl
    - However, there is an easier way for gdb: Tell debug server to use physical addresses.
      - The following two commands are for DebugServer but its cli is lacking readline support so it is easier to send them from gdb with the `monitor` command.
      - `monitor set mem-access progbuf` (use RISC-V instructions in a special area to access memory because abscmd and sysbus don't seem to support physical addresses for this cpu)
      - `monitor set virtual-mem-access off` (skip MMU for debug memory access, i.e. use physical addresses)
      - Keep in mind that this may yield confusing results for normal debugging because the debugger will see memory differently than the program.
      - If you get implausible data, have a look at the DebugServer output. It will warn when the read might have failed (but it isn't always right
        about this). If reads fail, they will often read back the address itself (or sometimes zero).
      - Some addresses are documented but we cannot seem to access them, e.g. BOOTROM at 0x90000000. This might be because the bus master of D0
        doesn't have access to that address range or it could be that BOOTROM deactivates something before jumping to our code. However, part of
        this range must be available (at least for M0) because `bl_mcu_sdk` has an option to call functions in that space.
    - Read config for GPIO 8 (the LED on M1s dock):
      `p/x *(uint32_t*)0x200008e4`
    - Toggle LED:
      - low / on: `set *0x200008e4 = 0x00400b42`
      - high / off: `set *0x200008e4 = 0x01400b42`
    - Read state of the side buttons (GPIO22 and GPIO23):
      - set input enable: `set *0x2000091c = 0x00400B13; set *0x20000920 = 0x00400B13`
      - read state: `x/2x 0x2000091c`
      - (This is only a demonstration. If you want to do this for real, have a look at register 0x20000ac4, which reports the input value of GPIO0 to GPIO31.)
    - I don't have a way to debug cpu M0, yet, but there are some limited means available in the `MCU_MISC` peripheral, e.g. we can read its `mstatus`
      register and program counter.
- 10. Micropython
  - The compile-flash-test loop for `low_load` and the kernel is rather long so we want some high-level scripting language to test our understanding of
    peripherals and maybe write some driver skeletons.
  - Why Micropython?
    - It should be tiny. I can't use the SD card while I use the Sipeed debugger. We could load larger binaries into RAM but that's not much
    - Tcl is a bit larger than I would like, Lua is quit small but pulls in too many libraries (and Lua without readline seems to have very bare-bones
      editing support), Python is absurdely large (over 100 MB, could surely be reduced but I don't want to spend the time).
    - Micropython was the first one that just works well enough so I'm running with that.
    - The Linux port is lacking some things, e.g. peripheral libraries and calling subprocesses and the heap has a fixed size. I assume that it is mostly
      for testing without hardware. We can work around some of the limitations with the `ffi` module.

