{ source, stdenv, gnumake, gcc, yacc, bison, flex, openssl, bc, ncurses, pkg-config, ... }:
stdenv.mkDerivation
{
  name = "uboot";
  src = source;

  depsBuildBuild = [
    gcc openssl
    #FIXME Can we make it so these are only added when we start a dev shell? (only needed for `make menuconfig`)
    #pkg-config ncurses
  ];
  nativeBuildInputs = [ gnumake yacc bison flex bc ];

  buildPhase = ''
    make CROSS_COMPILE=riscv32-unknown-linux-gnu- ox64_m0_defconfig
    make CROSS_COMPILE=riscv32-unknown-linux-gnu- -j$NIX_BUILD_CORES
  '';

  installPhase = ''
    mkdir $out
    cp u-boot{,.bin,.cfg,.dtb,-dtb.bin,.elf,.lds,.map,.sym} $out/
  '';

  dontFixup = true;

  # bflb-mcu-tool --chipname bl808 --port /dev/ttyUSB1 --baudrate 5000000 --firmware uboot-m0.bin
  # Reset the board.
  # picocom -b 115200 /dev/ttyUSB1
  # > fastboot 0
  # nix run .#uuu -- -lsusb
  # nix run .#uuu -- -V -b uuu.script
  # uuu.script is something like this:

  # CFG: FB:  -vid 0x18d1 -pid 0x4e40
  # FB: getvar version
  # #FB: ucmd setenv fastboot_buffer 0x51000000
  # FB: download -f out/fw_payload.elf
  # FB: ucmd rproc init 0
  # FB: ucmd rproc load 0 51000000 1000000
  # FB: ucmd rproc start 0
  # FB: Done
}
