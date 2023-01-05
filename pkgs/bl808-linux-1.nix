{
  bl808-linux-1-build-env = { buildFHSUserEnv }:
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

  bl808-linux-1 = { stdenv, fetchFromGitHub, bl808-rootfs, python3, git
    , prebuiltCmake, prebuiltGccBaremetal, prebuiltGccLinux, bl808-linux-1-build-env }:
  let env = bl808-linux-1-build-env; in
  stdenv.mkDerivation {
    name = "bl808_linux";
  
    src = fetchFromGitHub {
      owner = "bouffalolab";
      repo = "bl808_linux";
      rev = "561ee61222e5d5e7d028b5cf237c0ddf4a616f1e";
      hash = "sha256-k8wm4e7/ynPoY+ZVGnHIoq7o1yCrBKInFsUDL2xqK1w=";
    };
  
    patches = [
      ../patches/bl808-linux-dts.patch
      ../patches/bl808-linux-enable-jtag.patch
    ];
  
    rootfs = bl808-rootfs;
  
    postPatch = ''
      mkdir toolchain
      ln -s ${prebuiltCmake}        toolchain/cmake
      ln -s ${prebuiltGccBaremetal} toolchain/elf_newlib_toolchain
      ln -s ${prebuiltGccLinux}     toolchain/linux_toolchain
  
      #set -x
      #ls -l toolchain/
      #ls -l toolchain/linux_toolchain/
      #${env}/bin/build-env -c "ldd toolchain/linux_toolchain/bin/riscv64-unknown-linux-gnu-gcc"
      #patchelf --print-interpreter toolchain/linux_toolchain/bin/riscv64-unknown-linux-gnu-gcc
      #${env}/bin/build-env -c "ls -l /lib64/ld-linux-x86-64.so.2"
      ${env}/bin/build-env -c "toolchain/linux_toolchain/bin/riscv64-unknown-linux-gnu-gcc --version"
  
      bash ./switch_to_m1sdock.sh
  
      rm out/squashfs_test.img
      cp $rootfs out/squashfs_test.img
    '';
  
    nativeBuildInputs = [ python3 git ];
  
    buildPhase = ''
      ${env}/bin/build-env build.sh all
    '';
  
    installPhase = ''
      cp -r out $out
    '';
  };
}
