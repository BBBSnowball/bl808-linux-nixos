let
  common = f: { stdenv, fetchFromGitHub, python3, git
    , prebuiltCmake, prebuiltGccBaremetal, prebuiltGccLinux, bl808-linux-2-build-env }@args:
  let env = bl808-linux-2-build-env; in
  stdenv.mkDerivation ({
    src = fetchFromGitHub {
      owner = "bouffalolab";
      repo = "bl808_linux";
      rev = "561ee61222e5d5e7d028b5cf237c0ddf4a616f1e";
      hash = "sha256-k8wm4e7/ynPoY+ZVGnHIoq7o1yCrBKInFsUDL2xqK1w=";
    };
  
    postPatch = ''
      mkdir toolchain
      ln -s ${prebuiltCmake}        toolchain/cmake
      ln -s ${prebuiltGccBaremetal} toolchain/elf_newlib_toolchain
      ln -s ${prebuiltGccLinux}     toolchain/linux_toolchain
  
      bash ./switch_to_m1sdock.sh
    '';
  
    nativeBuildInputs = [ python3 git ];
  } // f (args // { inherit env; }));
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

  bl808-linux-2-opensbi = { stdenv, fetchFromGitHub, prebuiltGccLinux, bl808-linux-2-build-env }:
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

    buildScript = ''
      grep 0x00401502 platform/thead/c910/platform.c
      make PLATFORM=thead/c910 CROSS_COMPILE=${prebuiltGccLinux}/bin/riscv64-unknown-linux-gnu- -j$(nproc) \
        FW_TEXT_START=0x3EFF0000 \
        FW_JUMP_ADDR=0x50000000
      ${prebuiltGccLinux}/bin/riscv64-unknown-linux-gnu-objdump -dx build/platform/thead/c910/firmware/fw_jump.elf >build/platform/thead/c910/firmware/fw_jump.lst
    '';
    passAsFile = [ "buildScript" ];

    buildPhase = ''
      ${bl808-linux-2-build-env}/bin/build-env $buildScriptPath
    '';

    installPhase = ''
      mkdir $out
      cp build/platform/thead/c910/firmware/fw_jump.* $out/
    '';
  };

  bl808-linux-2-low-load = common ({ env, ... }: {
    name = "bl808-linux-2-low-load";
    patches = [
      ../patches/bl808-linux-enable-jtag.patch
      ../patches/bl808-linux-larger-opensbi.patch
    ];

    buildPhase = ''
      ${env}/bin/build-env build.sh low_load
    '';

    installPhase = ''
      mkdir $out
      cp out/low_load* $out/
    '';
  });

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

  bl808-linux-2-kernel = common ({ env, ... }: {
    name = "bl808-linux-2-linux";
    buildPhase = ''
      ${env}/bin/build-env build.sh kernel
    '';
    installPhase = ''
      mkdir $out
      cp out/Image.lz4 $out/
    '';
  });

  bl808-linux-2 = { python3, stdenv, bl808-linux-2-opensbi, bl808-linux-2-low-load, bl808-linux-2-dtb, bl808-linux-2-kernel, bl808-rootfs }:
  stdenv.mkDerivation {
    name = "bl808_linux";
    src = bl808-linux-2-kernel.src;
    dontUnpack = true;

    nativeBuildInputs = [ python3 ];
  
    buildPhase = ''
      mkdir out
      cp -s ${bl808-linux-2-opensbi}/* out/
      cp -s ${bl808-linux-2-low-load}/* out/
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
