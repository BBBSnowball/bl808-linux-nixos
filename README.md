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

Even quicker start
==================

This will assume that you know how nix works and how to flash the M1s dock board. If not, consider reading the longer
instructions below.

NOTE: This has not been tested on a new board, yet. I have tested it after erasing the flash so there is a good chance
that it will work.

- Connect M1s dock in bootloader mode and run:
  `nix run github:BBBSnowball/bl808-linux-nixos#bl808-linux-2-flash --port /dev/ttyUSB1`
- Connect picocom to `/dev/ttyUSB0` with 2 Mbaud.
- Press the RST button. You should see Linux booting. Login is "root" without password.

Goals
=====

- DONE: Include all the tools that are needed, e.g. compilers and flash tools.
  - This is using nix so everything will be pinned to known-good versions.
- Get rid of as many "blobs" and non-standard repos as we can.
  - DONE: Compile toolchain from source.
  - DONE: Build the rootfs with packages from nixpkgs. Bouffallo's is a blob without any sources.
  - DONE: We are using programming tools from Bouffallo but they are Open-Source (Python, MIT license). We remove some binaries
    that would only be needed for alternative transports (ck-link, j-link).
  - Apply patches on top of upstream Linux rather than using Bouffallo's copy without history.
    - We can maybe remove the patches altogether because current Linux can handle ASIDs and T-Head's custom TLB bits
      and we can let OpenSBI handle the UART.
  - Boot without `low_load_d0` firmware by using OpenSBI's `FW_PAYLOAD` option. Use XIP for OpenSBI to save some RAM.
- DONE: Have things working out-of-the-box, ideally with a single command (assuming nix is already installed).
- Essential drivers:
  - remoteproc
    - communication between M0 and D0 cpus
    - load M0 firmware from Linux (if possible; my experiments haven't worked so far)
      - If that doesn't work, find a way to provide the resource table, e.g. make a dummy-remoteproc driver and load an ELF
        that only has that table.
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
      - The headers seem to be constant.
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

Tale of a soft-bricked board
============================

- How did it happen?
  - I was programming with the Lab Dev GUI in MCU mode and forgot to detach picocom from ttyUSB1.
  - This was not the first time I made this mistake so that alone won't brick your board.
  - The payloads were ok. I had previously used them so we know that they aren't broken and they even would have booted to Linux.
    I was re-programming the board to determine whether Dev Cube would change the bootheader for different payloads.
  - I noticed my error when the GUI failed to "shake hands" and I tried to detach picocom - probably while it was trying
    its handshake again.
  - I would have pressed C-a C-Q to quit picocom and usually the target shouldn't see any of this. As it did go wrong, let's assume
    that I made some mistake and the target may have received C-a, C-q, C-b (alternative escape for when I was using picocom+screen)
    or C-s (don't ask).
  - This is the usual behaviour when a tty port is opened by more than one program: The target will see data written by all clients
    (most likely intermingled) but only one client will see the reply. Picocom got a lot of these "questionmark in a white diamond"
    characters, i.e. some binary data.
  - The bootloader is still usable after programming one thing so we can write several parts of flash without resetting to the bootloader again.
    This usually even works after aborting the previous write process (which I wouldn't recommend). It didn't work here, which is a bit odd.
  - Then, I tried to reset to bootloader again. I might have accidentally reset to normal mode before RST+BOOT but I don't think so.
- How does it behave now?
  - It doesn't reply at all when the programming tools try their handshake.
  - It still gets warm initially like it usually does (i.e. it is doing something) but when I don't reset it for some minutes, it will get cold.
- What could have gone wrong? Some ideas:
  1. The bootloader understood this as some destructive command that we wouldn't usually use, e.g. program efuses to whatever happened to be
     the next bytes. This isn't really meant to destroy the chip but there are probably many ways to configure things such that it won't boot
     on that board anymore.
    - ~~That's possible. I would hope that such commands would be protected by a CRC but I may have been extremely unlucky.~~
    - It has fixed itself (see below) so that's not it.
  2. The GUI was doing something beside writing flash, e.g. write efuses, and my key presses messed that up.
    - I think the GUI never finished the handshake so it probably didn't start writing anything. Unfortunately, I don't have that log anymore so we don't know for sure.
    - The log says something about efuses but I think that may be about the bootheader - at least that's my best guess based on the
      Python code.
  3. The bootloader did write values into the flash and those got messed up. This will break Linux, of course, but the bootloader should
     still be ok.
    a. The bootloader won't work without some specific data in the flash.
      - This would be bad. It would be bad design but this is the first revision of bl808 and that would be exactly how one would work
        around bugs in BOOTROM.
      - Fortunately, it doesn't seem to be so: I see CS pulses on the scope for a normal boot but not when I reset to the bootloader.
        (I have removed the metal shield and the scope is connected to pin 1 of the flash, which is chip select (CS).)
      - This is with the bricked chip so this doesn't say whether a working bootloader would access the flash.
      - I am using a DSO nano, which is not fast enough to actually capture the CS pulses so there is some chance that there are so few
        pulses that I don't see them.
      - We can be quite certain that the bootloader won't access the flash in quad mode because IO3 is also connected to the BOOT button
        but I think that it will be more likely to use the simpler modes anyway (and then maybe switch to a faster mode if the config in
        flash says that that's ok).
    b. The bootloader (or the hardware) will work with an empty flash but if it seems valid, it will use some values.
      - The .ini file has some info that looks like it could be patches for BOOTROM. This is written to the bootheader so I guess it will
        be used in *some* way.
      - Again, that doesn't seem to be the case because I would see CS pulses on the scope.
      - But it would be a plausible theory for why it has fixed itself (see below) - assuming that I shorted flash pins by accident.
    c. The BOOTROM will read the bootheader and update efuses.
      - ~~That's possible.~~
      - It has fixed itself (see below) so that's not it.
  4. That hardware could be broken in some unrelated way, e.g. ESD strike.
    - This is rather unlikely. It was still sending something to picocom (which it doesn't do anymore) so the unrelated error would have to
      have happened at exactly the right time.
- Is there a way to rescue it? (assume it is bad efuses)
  - For an ARM, we would usually break communication with the flash and hope that it will enter FEL mode.
    - It doesn't seem to read the flash at all in bootloader mode and it doesn't stop reading it in normal mode. So, I guess not.
    - But it would be a plausible theory for why it has fixed itself (see below) - assuming that I shorted flash pins by accident. If you get into
      this situation and you don't have any better ideas, you may want to consider this. It might break things so try non-destructive ideas first, though.
  - Some settings could be wrong, e.g. pinout for crystal or flash.
    - It does something with the flash in normal boot mode so there must be some clock. It doesn't seem to read from flash in bootloader mode.
    - The bootloader is likely to use some internal clock to not rely on specific external components. It is not doing any USB so there is no
      need for a truly high-precision clock. Nonetheless, UART wants below 2% error and cheap RC oscillators can easily have much more than that.
      I would be using auto-baud as a workaround but who knows what they did.
    - If they are using auto-baud and the clocks are wrong for some reason (e.g. too small), it might work with a lower baudrate.
  - ...
- And... it is fixed!
  - Wait... what?
  - The GUI was still open and set to 115200 baud because I had tried that a few days ago. I clicked on "Log" (which reads a log from the MCU,
    I think) and got back `ack is b'4f4b'`. I had also tried that some days ago and I still see the errors when I scroll up (including a
    Python exception because the GUI *is* using Python internally).
  - So, why does it work, now? I don't know.
  - What is different?
    - A few days have passed.
    - OTG port is not connected.
    - Metal shield removed.
    - DSO nano connected to CS pin of the flash.
    - There is a small chance that the probe is sometimes shorting pins 1 (CS) and 2 (D0) of the flash but Linux is working fine now so it
      doesn't do so all the time.
  - Things that could be different but not really:
    - I had powered the board on with the BOOT switch pressed but I had tried that before. This time, I only did this to look at the CS pin
      because I knew that it wouldn't work.
    - The laptop was in standby and the USB hub was disconnected during that time but I also tried that before.
    - The debugger isn't connected anymore but that was one of the first things that I had tried.
  - None of this should make a difference.
  - Well, I guess it was time for some lucky accident..?

- Some random observations while I have the scope connected to CS:
  - The CS pin is low-ish when entering the bootloader but it is high after programming. This is not unexpected because BOOT pulls
    it low and the bootloader probably doesn't drive it before it is told to talk to the flash.
  - We seem to indeed have auto-baud in the bootloader because it did reply on 115200 baud as well as 2 Mbaud.
  - When erasing flash, there are single short pulses on CS. When writing data, there long pulses (50 us) with short pulses around.
  - For normal boot in the broken state, I was seeing the kind of noise that is typical when the signal is faster than the scope can record,
    i.e. I think there were many short accesses.
  - Normal boot to Linux could be a mix of short and long pulses but I really cannot tell with any certainty with the cheap scope.
  - I don't notice any access to flash for things like `ls -l /bin/*`. This is because of the cache, of course, but it doesn't quite match
    my earlier experience when previously unused busybox applets weren't working as soon as the flash was "broken" (pinmux reconfigured).
    The list of symlinks should be all that is needed for that. I was using tmpfs - not enough to fill the RAM, I think, but maybe.

Can we replace the Lab Dev GUI for programming?
===============================================

- It writes our programs to fixed offsets in flash but it does add some headers.
  - The programs are padded by zeroes, I think to a multiple of 16 bytes.
  - The printed sha-256 checksums match those of the files if we add the padding.
- The `bootheader_group0.bin` and `bootheader_group1.bin` that are written to /tmp remain the same regardless of what we select for the MCU image.
- Unfortunately, they differ from what is actually written and the header for group0 is much longer in flash.
- We can read flash like this:
  - `from bl808_regs import *; SF_CTRL.regs.SF_ID1_OFFSET.ref.value32 = 0`  (This will break further access to the rootfs.)
  - `from reg_lib import hexdump; hexdump(0x58000000, 0x2010)`
  - We want to compare it to the bootheader files so let's convert them to the same format:
    `hexdump --format '"%07.7_ax: " 4/4 "%08x " "\r\n"' file.bin`
- Group1 (D0):
  - The length matches and the data is mostly the same but some parts are different.
  - I add 16 zero bytes to `low_load_bl808_d0.bin`.
  - 0x108c seems to be related to the length. It is increased by 16 with the longer firmware. In fact, it is really just the plain size.
  - 0x1090 to 0x10b0 is completely different. This could be the hash. Indeed, it matches the sha-256 hash of the firmware.
  - 0x115c is also quite different. I assume that this is some hash over the header.
  - Both 0f 0x1090 and 0x115c are 0xdeadbeef in `bootheader_group1.bin`.
- Group0 (M0):
  - The length and hashes seem to be the same for group0 but there are additional changes from 0x00b0 to 0x0120 and there is lot of additional
    data after the bootheader file (from 0x0160 to 0x560). The word at 0x560 could be another checksum.
- Let's have a look at the Bouffallo tools.
  - `bflb_iot_tool/libs/bl808/bootheader_cfg_keys.py`:
    - There are lots of offsets.
    - `bootcfg_start_pos` is 0x80.
    - `group_image_offset` is 0x84. The data matches the offset of the payload in flash.
    - `img_len_cnt` is 0x8c. This is were the length of the payload is stored.
    - `hash_0` is at 0x90 and `hash_7` matches with the end of the sha-256 hash that we have seen.
    - `bootcpucfg_start_pos` is 0xb0 so I guess the data after that is more configuration for the M0 core. This explains why we don't see this
      for group1.
    - Actually, there seems to be 24 bytes each for M0, D0 and LP but all in group0 regardless of which group the core is assigned to (I assume).
    - I hope that we can start the LP core at runtime but this might be another way to do it. There even seem to be default values for some fields
      although the core is disabled at the moment.
    - `m0_image_address_offset` is set to zero and `m0_boot_entry` is set to 0x58000000. I would have expected it the other way around.
    - `m0_msp_val` is probably the initial stack pointer. This is zero but that's ok because it is customary that the RISC-V init code sets this itself.
    - Ah, actually, the config *is* in the group for the core. D0 has its enable set to zero in group0 and it is 1 in group1 and all the config is
      in group1.
    - `flashCfgTableAddr` is 0x160 so that's the data that is added after the bootheader. Well, at least part of it. It ends at 0x318 according to
      the length field. Indeed, the pattern of numbers changes at that point. The last word is different so I assume that's another checksum.
    - `patch_on_read` has only zeroes but `patch_on_jump` seems to have two entries.
    - The last field is called `crc32`.
    - I assume that most of this will match what we find in `efuse_bootheader_cfg.conf`.
  - Section hash:
    - `./libs/bflb_utils.py` has `get_crc32_bytearray` which calls `binascii.crc32`. The Python documentation says this:
      "The algorithm is consistent with the ZIP file checksum."
    - The checksum in group0 matches what `binascii.crc32` gives us for the whole block except the checksum.
  - Flash config table:
    - `segdata_file` refers to files like `chiptest_ipc_basic_D0.bin` but we don't seem to have those. That's probably not were the flashcfg table comes from.
    - `flash_select_do.py` is looking at the files in `utils/flash`. There seem to be config files for various types of flash chips.
    - They are selecting the correct file based on the JEDEC ID they read from the actual flash on the board.
    - This means that we cannot (or rather should not) hardcode this data. If we do, we will run into trouble when a new batch of boards has a differnt
      flash. It is quite common to buy these chips from more than one vendor (even before the current shortages).
- Ok, we have to work with the tool, it seems.
  - The only reason not to use it was the lack of dual-core support. We could fix that or we could program M0 (and the flash table) with the tool and
    then handle group1 for D0 ourselves.
  - Another option would be to check that there is a valid table in the expected position and leave it alone. If not, we can just program anything in
    the normal way and the table will exist. We would need read access via the bootloader to check it and we don't have that.
  - What happens when we flash the M0 firmware in `--mcu` mode? Will it write a different config? Maybe it even still boots?
    - `./result-tools/bin/bflb-iot-tool --chipname bl808 --baudrate 2000000 --port /dev/ttyUSB1 --firmware result-2f/low_load_bl808_m0.bin`
    - Nope. This is using completely different addresses.
    - `./result-tools/bin/bflb-mcu-tool --chipname bl808 --baudrate 2000000 --port /dev/ttyUSB1 --firmware result-2f/low_load_bl808_m0.bin`
    - This is looking good. In fact, this is looking *very* good. The hash for both parts matches what we got with the GUI.
    - Does it boot? (after I fix the mess that I had created with the bflb-iot-too)
      - Program M0 and D0 firmware with the GUI.
      - Program M0 firmware with bflb-mcu-tool.
      - Change flake.nix to use bflb-mcu-tool for flashing the image. -> Actuall, don't. It doesn't have `--single` mode.
      - `nix run -L .#bl808-linux-2-flash-img`
      - Now, we should have group0 programmed by bflb-mcu-tool, including flash config.
      - And it *does* boot. Nice.
      - Side node: I seem to be getting boot failures when I press the reset button for only a short time. Maybe the scope probe is shorting the pins
        when I press the button..?
    - Next check:
      - `./result-tools/bin/bflb-mcu-tool --chipname bl808 --baudrate 2000000 --port /dev/ttyUSB1 --firmware result-2f/low_load_bl808_m0.bin --erase`
        - "Flash Chip Erase All"
        - This has regular, single spikes on CS. I would have assumed that there is an erase-all command (which should be faster than erasing individual
          sectors). Or maybe there is and the CS is only polling the busy bit.
        - "Chip erase time cost(ms): 36507.719482421875"
      - `./result-tools/bin/bflb-iot-tool --chipname bl808 --baudrate 2000000 --port /dev/ttyUSB1 --addr 0x1000 --firmware x2.bin --single`
        - Copy hexdump data, remove address, write to x2.txt.
        - `python -c 'f = open("x2.txt"); x = f.read(); f.close(); import struct; x = struct.pack("<88I", *(int(y, 16) for y in x.split())); f = open("x2.bin", "wb"); f.write(x); f.close()'`
        - `sha256sum -c <<<"3e67637e5dd98df5afc71563d7d02a42e94e1d3bbea47fb56e6e555b87f5a81b  x2.bin"`
      - `./result-tools/bin/bflb-iot-tool --chipname bl808 --baudrate 2000000 --port /dev/ttyUSB1 --addr 0x52000 --firmware x3.bin --single`
        - `cp result-2f/low_load_bl808_d0.bin x3.bin`
        - `chmod u+w x3.bin`
        - `echo -ne '\0\0\0\0' >>x3.bin`
        - `sha256sum -c <<<"fb22a9bf164fd35fae9bec49b5c6af6a3e8df28eeaf4a912c5210735e367640f  x3.bin"`
      - `nix run -L .#bl808-linux-2-flash-img`
    - And it boots.
- I read something about appending a checksum to the image. I should check whether there is a CRC32 after the firmware in flash.
  - We have written the M0 firmware with bflb-mcu-tool so let's check that one.
  - `hex(mem32[0x58000000+0x2000+0x95e0-4])` -> last word of the image
  - `hex(mem32[0x58000000+0x2000+0x95e0])` -> 0xffffffff
  - There doesn't seem to be any checksum.
- Ok, so we do have a way to flash everything without using the GUI.
  - We are using bflb-mcu-tool and bflb-iot-tool, which I found on Pypi.
  - I don't know of any git repo for those tools or some way to contribute. This is not ideal.
  - They do have a license file, which states that they are under MIT license. I guess this makes them even proper open source.

