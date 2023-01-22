let
  wrapPrebuiltToolchain = toolchain: { bl808-linux-2-build-env, runCommand, runtimeShell, ... }:
  runCommand "wrap" {} ''
    mkdir $out/bin -p
    cd ${toolchain}/bin
    for x in * ; do
      echo "#!${runtimeShell}" >$out/bin/"$x"
      echo "exec ${bl808-linux-2-build-env}/bin/build-env -c \"exec '${toolchain}/bin/$x' \\\"\\\$@\\\"\" -- \"\$@\"" >>$out/bin/"$x"
      chmod +x $out/bin/"$x"
    done
  '';
in {
  bl808-linux-2-build-env = { buildFHSUserEnv }:
  buildFHSUserEnv {
    name = "build-env";
    targetPkgs = pkgs: with pkgs;
      [
        autoPatchelfHook zlib flex bison ncurses pkg-config
        #ncurses5
        gcc binutils
        bc
        dtc lz4
      ];
    multiPkgs = pkgs: with pkgs;
      [ glibc
      xorg.libX11
      ];
    runScript = "bash";
    extraOutputsToInstall = [ "dev" ];
  };

  prebuiltGccBaremetalInEnv = { prebuiltGccBaremetal, bl808-linux-2-build-env, runCommand, runtimeShell }@args: wrapPrebuiltToolchain prebuiltGccBaremetal args;
  prebuiltGccLinuxInEnv = { prebuiltGccLinux, bl808-linux-2-build-env, runCommand, runtimeShell }@args: wrapPrebuiltToolchain prebuiltGccLinux args;

  bl808-linux-2-use-prebuilt-toolchain = false;
  xuantie-gnu-toolchain-multilib-newlib-2 = { bl808-linux-2-use-prebuilt-toolchain, prebuiltGccBaremetalInEnv, xuantie-gnu-toolchain-multilib-newlib }:
    if bl808-linux-2-use-prebuilt-toolchain then prebuiltGccBaremetalInEnv else xuantie-gnu-toolchain-multilib-newlib;
  xuantie-gnu-toolchain-multilib-linux-2 = { bl808-linux-2-use-prebuilt-toolchain, prebuiltGccLinuxInEnv, xuantie-gnu-toolchain-multilib-linux }:
    if bl808-linux-2-use-prebuilt-toolchain then prebuiltGccLinuxInEnv else xuantie-gnu-toolchain-multilib-linux;

  bl808-linux-2-opensbi = { stdenv, fetchFromGitHub, xuantie-gnu-toolchain-multilib-linux-2 }:
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
      make PLATFORM=thead/c910 CROSS_COMPILE=${xuantie-gnu-toolchain-multilib-linux-2}/bin/riscv64-unknown-linux-gnu- -j$NIX_BUILD_CORES \
        FW_TEXT_START=0x3EFF0000 \
        FW_JUMP_ADDR=0x50000000
      ${xuantie-gnu-toolchain-multilib-linux-2}/bin/riscv64-unknown-linux-gnu-objdump -dx build/platform/thead/c910/firmware/fw_jump.elf >build/platform/thead/c910/firmware/fw_jump.lst
    '';

    installPhase = ''
      mkdir $out
      cp build/platform/thead/c910/firmware/fw_jump.* $out/
    '';
  };

  bl808-linux-2-low-load-common = {
    stdenv, fetchFromGitHub, python3, git, cmake,
    xuantie-gnu-toolchain-multilib-newlib-2,
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

    patches = [
      ../patches/bl808-linux-enable-jtag.patch
      ../patches/bl808-linux-larger-opensbi.patch
    ];

    postPatch = '' 
      bash ./switch_to_m1sdock.sh
    '';

    buildPhase = ''
      NEWLIB_ELF_CROSS_PREFIX=${xuantie-gnu-toolchain-multilib-newlib-2}/bin/riscv64-unknown-elf-
      cd bl_mcu_sdk_bl808
      make CHIP=bl808 CPU_ID=${cpu} CMAKE_DIR=${cmake}/bin CROSS_COMPILE=$NEWLIB_ELF_CROSS_PREFIX SUPPORT_DUALCORE=y APP=low_load -j$NIX_BUILD_CORES
    '';

    installPhase = ''
      mkdir $out
      cp out/examples/low_load/low_load_bl808_${cpu}.* $out/
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

  bl808-linux-2-kernel = { stdenv, fetchFromGitHub, bison, yacc, flex, bc, kmod, lz4, xuantie-gnu-toolchain-multilib-linux-2 }:
  stdenv.mkDerivation {
    name = "bl808-linux-2-linux";

    src = fetchFromGitHub {
      owner = "BBBSnowball";
      repo = "linux-riscv-bl808";
      rev = "fcd93b59872e7aad4cdabaac6f5578ee640c1f01";
      hash = "sha256-OoxUMEviiZ68s94XyhIjs+KrgV735+Iimh/XpnL0bPU=";
    };

    nativeBuildInputs = [ bison yacc flex bc lz4 kmod ];

    outputs = [ "out" "modules" ];

    buildPhase = ''
      patchShebangs scripts/ld-version.sh
      LINUX_CROSS_PREFIX=${xuantie-gnu-toolchain-multilib-linux-2}/bin/riscv64-unknown-linux-gnu-
      cp c906.config .config

      makeFlags=(ARCH=riscv CROSS_COMPILE=$LINUX_CROSS_PREFIX -j$NIX_BUILD_CORES INSTALL_MOD_PATH=$modules DEPMOD=${kmod}/bin/depmod)
      make ''${makeFlags[@]} Image modules
      lz4 -9 -f arch/riscv/boot/Image arch/riscv/boot/Image.lz4
    '';

    installPhase = ''
      mkdir $out
      cp arch/riscv/boot/Image.lz4 $out/
      cp vmlinux $out/Image.elf

      make ''${makeFlags[@]} modules_install
      rm $modules/lib/modules/*/{build,source}
    '';
  };

  bl808-linux-2 = { python3, stdenv, bl808-linux-2-opensbi, bl808-linux-2-low-load-m0, bl808-linux-2-low-load-d0, bl808-linux-2-dtb, bl808-linux-2-kernel, bl808-rootfs }:
  stdenv.mkDerivation {
    name = "bl808_linux";
    dontUnpack = true;

    nativeBuildInputs = [ python3 ];
  
    buildPhase = ''
      mkdir out
      cp -s ${bl808-linux-2-opensbi}/* out/
      cp -s ${bl808-linux-2-low-load-m0}/* out/
      cp -s ${bl808-linux-2-low-load-d0}/* out/
      cp -s ${bl808-linux-2-dtb}/* out/
      cp -s ${bl808-linux-2-kernel}/* out/
      ln -s ${bl808-linux-2-kernel.modules}/ out/linux-modules
      cp -s ${bl808-rootfs} out/squashfs_test.img
      ( cd out && python3 ${../bl808-flash}/merge_7_5Mbin.py )
    '';
  
    installPhase = ''
      cp -r out $out
    '';
  };

  bl808-linux-2-flash-script = { bl808-linux-2, bflb-mcu-tool, bflb-iot-tool, writeShellScriptBin }:
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
