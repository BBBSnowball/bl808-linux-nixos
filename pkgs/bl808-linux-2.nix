let
in {
  xuantie-gnu-toolchain-multilib-linux-2 = { xuantie-gnu-toolchain-multilib-linux, ... }: xuantie-gnu-toolchain-multilib-linux;

  bl808-linux-2-opensbi = { stdenv, fetchFromGitHub, xuantie-gnu-toolchain-multilib-linux, python3, opensbi-source, buildroot_bouffalo, ... }:
  stdenv.mkDerivation {
    name = "bl808-linux-2-opensbi";
    src = opensbi-source;

    nativeBuildInputs = [ python3 ];

    patches = [
      #../patches/bl808-opensbi-01-bl808-support-v0.9.patch
      #../patches/bl808-opensbi-02-m1sdock_uart_pin_def.patch
      ##../patches/bl808-opensbi-03-debug.patch
      "${buildroot_bouffalo}/board/pine64/ox64/patches/opensbi/0001-lib-utils-serial-Add-Bouffalo-Lab-serial-driver.patch"
      "${buildroot_bouffalo}/board/pine64/ox64/patches/opensbi/0002-update-opensbi-firmware-base-image-and-dtb-addresses.patch"
    ];

    postPatch = ''
      patchShebangs scripts/carray.sh
      patchShebangs scripts/Kconfiglib/*.py
    '';

    buildPhase = ''
      make CROSS_COMPILE=${xuantie-gnu-toolchain-multilib-linux}/bin/riscv64-unknown-linux-gnu- PLATFORM=generic -j$NIX_BUILD_CORES
      ${xuantie-gnu-toolchain-multilib-linux}/bin/riscv64-unknown-linux-gnu-objdump -dx build/platform/generic/firmware/fw_jump.elf >build/platform/generic/firmware/fw_jump.lst
    '';

    installPhase = ''
      mkdir $out
      cp build/platform/generic/firmware/fw_jump.* $out/
    '';

    dontFixup = true;
  };

  bl808-linux-2-low-load-common = {
    stdenv, fetchFromGitHub, python3, git, cmake,
    xuantie-gnu-toolchain-multilib-newlib,
    cpu ? "xx",
    oblfr-source, bl_mcu_sdk-source,
    ...
  }@args:
  stdenv.mkDerivation {
    name = "bl808-linux-2-low-load-${cpu}";
    src = oblfr-source;
  
    nativeBuildInputs = [ git python3 ];

    postPatch = ''
      patchShebangs tools/kconfig/gensdkconfig.py
    '';

    buildPhase = ''
      NEWLIB_ELF_CROSS_PREFIX=${xuantie-gnu-toolchain-multilib-newlib}/bin/riscv64-unknown-elf-
      export BL_SDK_BASE=${bl_mcu_sdk-source}
      #cd bl_mcu_sdk_bl808
      #make CHIP=bl808 CPU_ID=${cpu} CMAKE_DIR=${cmake}/bin CROSS_COMPILE=$NEWLIB_ELF_CROSS_PREFIX SUPPORT_DUALCORE=y APP=low_load -j$NIX_BUILD_CORES
      cd apps/${cpu}_lowload
      make CMAKE=${cmake}/bin/cmake CROSS_COMPILE=$NEWLIB_ELF_CROSS_PREFIX
    '';

    installPhase = ''
      mkdir $out
      cp build/build_out/${cpu}_lowload_bl808_${cpu}.{asm,bin,elf,map} $out/
    '';

    dontFixup = true;
  };

  bl808-linux-2-low-load-m0 = { bl808-linux-2-low-load-common, ... }: bl808-linux-2-low-load-common.override { cpu = "m0"; };
  bl808-linux-2-low-load-d0 = { bl808-linux-2-low-load-common, ... }: bl808-linux-2-low-load-common.override { cpu = "d0"; };

  bl808-linux-2-dtb = { stdenv, dtc, kernel-source, bison, yacc, flex, bc, ... }:
  stdenv.mkDerivation {
    name = "bl808-linux-2-dtb";
    src = kernel-source;

    nativeBuildInputs = [ dtc bison yacc flex bc ];

    buildPhase = ''
      #cpp -nostdinc -I "${kernel-source}/arch/riscv/boot/dts/bouffalolab/" -undef -x assembler-with-cpp $src tmp.dts
      #dtc -I dts -O dtb -o hw.dtb.5M tmp.dts

      make ARCH=riscv bl808_defconfig
      make ARCH=riscv dtbs
    '';
    installPhase = ''
      mkdir $out
      make ARCH=riscv dtbs_install INSTALL_PATH=$out
      cp arch/riscv/boot/dts/bouffalolab/bl808-pine64-ox64.dtb $out/hw.dtb.5M
    '';
  };

  bl808-linux-2-kernel = { stdenv, fetchFromGitHub, bison, yacc, flex, bc, kmod, lz4, xuantie-gnu-toolchain-multilib-linux, kernel-source, ... }:
  stdenv.mkDerivation {
    name = "bl808-linux-2-linux";

    src = kernel-source;

    nativeBuildInputs = [ bison yacc flex bc lz4 kmod ];

    outputs = [ "out" "modules" "dtb" ];

    buildPhase = ''
      patchShebangs scripts/ld-version.sh
      LINUX_CROSS_PREFIX=${xuantie-gnu-toolchain-multilib-linux}/bin/riscv64-unknown-linux-gnu-

      makeFlags=(ARCH=riscv CROSS_COMPILE=$LINUX_CROSS_PREFIX -j$NIX_BUILD_CORES INSTALL_MOD_PATH=$modules DEPMOD=${kmod}/bin/depmod)
      make ''${makeFlags[@]} bl808_defconfig
      make ''${makeFlags[@]} Image modules dtbs
      lz4 -9 -f arch/riscv/boot/Image arch/riscv/boot/Image.lz4
    '';

    installPhase = ''
      mkdir $out
      cp arch/riscv/boot/Image.lz4 $out/
      cp vmlinux $out/Image.elf

      make ''${makeFlags[@]} modules_install
      rm $modules/lib/modules/*/{build,source}

      make ''${makeFlags[@]} dtbs_install INSTALL_PATH=$dtb
      cp arch/riscv/boot/dts/bouffalolab/bl808-pine64-ox64.dtb $dtb/hw.dtb.5M
    '';
  };

  bl808-linux-2 = { python3, stdenv, bl808-linux-2-opensbi, bl808-linux-2-low-load-m0, bl808-linux-2-low-load-d0, bl808-linux-2-dtb, bl808-linux-2-kernel, bl808-rootfs, ... }:
  stdenv.mkDerivation {
    name = "bl808_linux";
    dontUnpack = true;

    nativeBuildInputs = [ python3 ];
  
    buildPhase = ''
      mkdir out
      cp -s ${bl808-linux-2-opensbi}/* out/
      cp -s ${bl808-linux-2-low-load-m0}/* out/
      cp -s ${bl808-linux-2-low-load-d0}/* out/
      cp -s ${bl808-linux-2-kernel.dtb}/hw.dtb.5M out/
      cp -s ${bl808-linux-2-kernel}/* out/
      ln -s ${bl808-linux-2-kernel.modules}/ out/linux-modules
      cp -s ${bl808-rootfs} out/squashfs_test.img
      ln -s m0_lowload_bl808_m0.bin out/low_load_bl808_m0.bin
      ln -s d0_lowload_bl808_d0.bin out/low_load_bl808_d0.bin
      ( cd out && python3 ${../bl808-flash}/merge_7_5Mbin.py --obflr-layout )
    '';
  
    installPhase = ''
      cp -r out $out
    '';

    passthru = {
      opensbi = bl808-linux-2-opensbi;
      low-load-m0 = bl808-linux-2-low-load-m0;
      low-load-d0 = bl808-linux-2-low-load-d0;
      kernel = bl808-linux-2-kernel;
      dtb = bl808-linux-2-kernel.dtb;
      rootfs = bl808-rootfs;
    };
  };

  bl808-linux-2-flash-script = { bl808-linux-2, bflb-mcu-tool, bflb-iot-tool, writeShellScriptBin, ... }:
  (writeShellScriptBin "flash-bl808-linux-2" ''
    files=${bl808-linux-2}
    bflb_mcu_tool=${bflb-mcu-tool}/bin/bflb-mcu-tool
    bflb_iot_tool=${bflb-iot-tool}/bin/bflb-iot-tool
    flash_args=(--chipname bl808 --baudrate 2000000 --port /dev/ttyUSB1 "$@")

    set -xe
    $bflb_mcu_tool "''${flash_args[@]}" --firmware $files/low_load_bl808_m0.bin
    sleep 1
    $bflb_iot_tool "''${flash_args[@]}" --addr 0x1000 --firmware $files/bootheader_group1.bin --single
    sleep 2
    $bflb_iot_tool "''${flash_args[@]}" --addr 0x52000 --firmware $files/low_load_bl808_d0_padded.bin --single
    sleep 2
    $bflb_iot_tool "''${flash_args[@]}" --addr 0xd2000 --firmware $files/whole_img_linux.bin --single

    : You can reset the board to boot into Linux. The console is on the first ttyUSB with 2 Mbaud.
    : ELF files with debug symbols are in: $files/
  '').overrideAttrs (old: {
    buildCommand = old.buildCommand + ''
      ln -s ${bl808-linux-2} $out/files
    '';
  });
}
