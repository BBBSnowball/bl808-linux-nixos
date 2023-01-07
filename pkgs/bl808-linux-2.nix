let
in {
  bl808-linux-2-opensbi = { stdenv, fetchFromGitHub, xuantie-gnu-toolchain-multilib-linux }:
  stdenv.mkDerivation {
    name = "bl808-linux-2-opensbi";

    src = fetchFromGitHub {
      owner = "riscv-software-src";
      repo = "opensbi";
      rev = "v0.9";
      hash = "sha256-W39R1RHsIM3yNwW/eukO+mPd9joPZLw+/XIJoH8agN8=";
    };

    patches = [
      ../patches/bl808-opensbi-01-bl808-support-v0.9.patch
      ../patches/bl808-opensbi-02-m1sdock_uart_pin_def.patch
      #../patches/bl808-opensbi-03-debug.patch
    ];

    buildPhase = ''
      make PLATFORM=thead/c910 CROSS_COMPILE=${xuantie-gnu-toolchain-multilib-linux}/bin/riscv64-unknown-linux-gnu- -j$NIX_BUILD_CORES \
        FW_TEXT_START=0x3EFF0000 \
        FW_JUMP_ADDR=0x50000000
      ${xuantie-gnu-toolchain-multilib-linux}/bin/riscv64-unknown-linux-gnu-objdump -dx build/platform/thead/c910/firmware/fw_jump.elf >build/platform/thead/c910/firmware/fw_jump.lst
    '';

    installPhase = ''
      mkdir $out
      cp build/platform/thead/c910/firmware/fw_jump.* $out/
    '';
  };

  bl808-linux-2-low-load-common = {
    stdenv, fetchFromGitHub, python3, git, cmake,
    xuantie-gnu-toolchain-multilib-newlib,
    cpu ? "xx",
  }@args:
  stdenv.mkDerivation {
    name = "bl808-linux-2-low-load-${cpu}";

    src = fetchFromGitHub {
      owner = "bouffalolab";
      repo = "bl808_linux";
      rev = "561ee61222e5d5e7d028b5cf237c0ddf4a616f1e";
      hash = "sha256-k8wm4e7/ynPoY+ZVGnHIoq7o1yCrBKInFsUDL2xqK1w=";
    };
  
    nativeBuildInputs = [ git ];

    postPatch = '' 
      bash ./switch_to_m1sdock.sh
    '';

    buildPhase = ''
      NEWLIB_ELF_CROSS_PREFIX=${xuantie-gnu-toolchain-multilib-newlib}/bin/riscv64-unknown-elf-
      cd bl_mcu_sdk_bl808
      make CHIP=bl808 CPU_ID=${cpu} CMAKE_DIR=${cmake}/bin CROSS_COMPILE=$NEWLIB_ELF_CROSS_PREFIX SUPPORT_DUALCORE=y APP=low_load -j$NIX_BUILD_CORES
    '';

    installPhase = ''
      mkdir $out
      cp -f out/examples/low_load/low_load_bl808_${cpu}.bin $out
    '';
  };

  bl808-linux-2-low-load-m0 = { bl808-linux-2-low-load-common }: bl808-linux-2-low-load-common.override { cpu = "m0"; };
  bl808-linux-2-low-load-d0 = { bl808-linux-2-low-load-common }: bl808-linux-2-low-load-common.override { cpu = "d0"; };

  bl808-linux-2-dtb = { stdenv, dtc }:
  stdenv.mkDerivation {
    name = "bl808-linux-2-dtb";
    src = ../dts/hw808c.dts;
    dontUnpack = true;

    nativeBuildInputs = [ dtc ];

    buildPhase = ''
      dtc -I dts -O dtb -o hw.dtb.5M $src
    '';
    installPhase = ''
      mkdir $out
      cp hw.dtb.5M $out/
    '';
  };

  bl808-linux-2-kernel = { stdenv, fetchFromGitHub, bison, yacc, flex, bc, lz4, xuantie-gnu-toolchain-multilib-linux }:
  stdenv.mkDerivation {
    name = "bl808-linux-2-linux";

    src = fetchFromGitHub {
      owner = "BBBSnowball";
      repo = "linux-riscv-bl808";
      rev = "fcd93b59872e7aad4cdabaac6f5578ee640c1f01";
      hash = "sha256-OoxUMEviiZ68s94XyhIjs+KrgV735+Iimh/XpnL0bPU=";
    };

    nativeBuildInputs = [ bison yacc flex bc lz4 ];

    buildPhase = ''
      patchShebangs scripts/ld-version.sh
      LINUX_CROSS_PREFIX=${xuantie-gnu-toolchain-multilib-linux}/bin/riscv64-unknown-linux-gnu-
      cp c906.config .config
      make ARCH=riscv CROSS_COMPILE=$LINUX_CROSS_PREFIX Image -j$NIX_BUILD_CORES
      lz4 -9 -f arch/riscv/boot/Image arch/riscv/boot/Image.lz4
    '';

    installPhase = ''
      mkdir $out
      cp arch/riscv/boot/Image.lz4 $out/
    '';
  };

  bl808-linux-2 = { python3, stdenv, bl808-linux-2-opensbi, bl808-linux-2-low-load-m0, bl808-linux-2-low-load-d0, bl808-linux-2-dtb, bl808-linux-2-kernel, bl808-rootfs }:
  stdenv.mkDerivation {
    name = "bl808_linux";
    src = bl808-linux-2-low-load-m0.src;
    dontUnpack = true;

    nativeBuildInputs = [ python3 ];
  
    buildPhase = ''
      mkdir out
      cp -s ${bl808-linux-2-opensbi}/* out/
      cp -s ${bl808-linux-2-low-load-m0}/* out/
      cp -s ${bl808-linux-2-low-load-d0}/* out/
      cp -s ${bl808-linux-2-dtb}/* out/
      cp -s ${bl808-linux-2-kernel}/* out/
      cp -s ${bl808-rootfs} out/squashfs_test.img
      ( cd out && python3 $src/out/merge_7_5Mbin.py )
    '';
  
    installPhase = ''
      cp -r out $out
    '';
  };
}
