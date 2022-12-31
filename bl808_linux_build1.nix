# nix-build bl808_linux_build1.nix -o out
# nix-build bl808_linux_build1.nix -o result-tools
# Flash out/low_load_bl808_{d0,m0}.bin using the GUI.
# Keep chip in bootloader mode and run:
# result-tools/bin/bflb-iot-tool --chipname bl808 --port /dev/ttyUSB1 --baudrate 2000000 --addr 0xD2000  --firmware out/whole_img_linux.bin  --single
# Open /dev/ttyUSB0 with baudrate 2000000 and login as root.
#
# Update only the rootfs:
# nix-build bl808_linux_build1.nix -A rootfs -o result-rootfs && ./result-tools/bin/bflb-iot-tool --chipname bl808 --port /dev/ttyUSB1 --baudrate 2000000 --addr 0x552000 --firmware result-rootfs --single
{ nixpkgs ? <nixpkgs>, pkgs ? import nixpkgs {} }:
let
  env = (pkgs.buildFHSUserEnv {
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
  });

  env2 = (pkgs.buildFHSUserEnv {
    name = "flash-env";
    targetPkgs = pkgs: with pkgs;
      [
        zlib
      ];
    runScript = "bash";
  });

  bflb-lab-dev-cube-env = pkgs.buildFHSUserEnv {
    name = "bflb-lab-dev-cube-env";
    targetPkgs = pkgs: with pkgs;
      [ zlib
        ncurses5
        lz4
        libGL xorg.libxcb
        glibc
        xorg.libX11
      ];
    runScript = "bash";
    extraOutputsToInstall = [ "dev" ];
  };

  prebuiltCmake = pkgs.fetchzip {
    url = "https://cmake.org/files/v3.19/cmake-3.19.3-Linux-x86_64.tar.gz";
    hash = "sha256-r+bdir2TB110Vb8UqRxBoxbYkQIP0gsoSQwQRtphyu0=";
  };
  prebuiltGccBaremetal = pkgs.fetchzip {
    url = "https://occ-oss-prod.oss-cn-hangzhou.aliyuncs.com/resource//1663142243961/Xuantie-900-gcc-elf-newlib-x86_64-V2.6.1-20220906.tar.gz";
    hash = "sha256-7uWcvYl4uySHCCOTThiEHSmlEBdZVRYW3cpqHztwUn4=";
  };
  prebuiltGccLinux = pkgs.fetchzip {
    url = "https://occ-oss-prod.oss-cn-hangzhou.aliyuncs.com/resource//1663142514282/Xuantie-900-gcc-linux-5.10.4-glibc-x86_64-V2.6.1-20220906.tar.gz";
    hash = "sha256-CwruscgjWk+pKd+OxSEoYjclzoazk6J2UaKufSmJz+0=";
  };

  LabDevCube = pkgs.fetchzip {
    url = "https://dev.bouffalolab.com/media/upload/download/BouffaloLabDevCube-v1.8.1.zip";
    stripRoot = false;
    hash = "sha256-qUlVusp+LeHayL0qXrSBZCCNUtOCC82wzNUcSfXRKOc=";
    passthru.version = "1.8.1";
  };

  bflb-iot-tool-pypi = pkgs.python3Packages.fetchPypi {
    pname = "bflb-iot-tool";
    version = "1.8.1";
    hash = "sha256-7kendLur1Fw0bhBJq14gM3fUG/y/K3IdWb5Jj2iP8cE=";
  };
  bflb-mcu-tool-pypi = pkgs.python3Packages.fetchPypi {
    pname = "bflb-mcu-tool";
    version = "1.8.1";
    hash = "sha256-bY5z6bXV2BAd38kjCHCfFd8H+ZXIFFfs0EC+i4mxG4s=";
  };
  pycklink-pypi = pkgs.python3Packages.fetchPypi {
    pname = "pycklink";
    version = "0.1.1";
    hash = "sha256-Ub3a72V15Fkeyo7RkbjMaj6faUrcC8RkRRSbNUuq/ks=";
  };
  bflb-crypto-plus-pypi = pkgs.python3Packages.fetchPypi {
    pname = "bflb_crypto_plus";
    version = "1.0";
    hash = "sha256-sbSDh05dLstJ+fhSWXFa2Ut2+WJ7Pen6Z39spc5mYkI=";
  };
  thead-debugserver-download = pkgs.fetchzip {
    url = "https://dl.sipeed.com/fileList/MAIX/M1s/M1s_Dock/9_Driver/cklink/T-Head-DebugServer-linux-x86_64-V5.16.5-20221021.sh.tar.gz";
    hash = "sha256-IjDf0ynPegwpFukMbPrR54eBK3BjNDRN6ZBKV/I1g84=";
  };
  prebuilt-linux = pkgs.fetchzip {
    url = "https://dl.sipeed.com/fileList/MAIX/M1s/M1s_Dock/7_Firmware/m1sdock_linux_20221116.zip";
    stripRoot = false;
    hash = "sha256-oALCXSI5pK0g/M2cn5kVOos+TnbxyuZoKMFhI0DBsrM=";
  };

  downloads = {
    inherit prebuiltCmake prebuiltGccBaremetal prebuiltGccLinux
      LabDevCube bflb-iot-tool-pypi bflb-mcu-tool-pypi pycklink-pypi bflb-crypto-plus-pypi
      thead-debugserver-download prebuilt-linux;
  };
  keep-downloads = pkgs.linkFarm "bl808_downloads" downloads;

  chrootenv = pkgs.callPackage "${nixpkgs}/pkgs/build-support/build-fhs-userenv/chrootenv" {};
  
  init-env-for-flash-tools = pkgs.writeShellScript "init-env-for-flash-tools" ''
    for i in ${env2}/* /host/*; do
      path="/''${i##*/}"
      [ -e "$path" ] || ${pkgs.coreutils}/bin/ln -s "$i" "$path"
    done

    set -e

    # create a writable copy of the Python package in /tmp because it will be
    # writing temporary files into its tree
    pkg="$1"
    cmd="$2"
    shift
    shift
    pkgtmp=$(mktemp -td bflb-tmp.XXXXXXXX)
    #cp -r "$pkg"/* "$pkgtmp"
    ${pkgs.xorg.lndir}/bin/lndir -silent "$pkg" "$pkgtmp"
    chmod -R u+w "$pkgtmp/"
    for x in "$pkgtmp/bin"/.*[a-z]* ; do
      ${pkgs.gnused}/bin/sed -i "s?$pkg?$pkgtmp?g" "$x"

      # sed has replaced the link by a read-only file from the store
      # and `rm` doesn't like to remove read-only files (and we avoid
      # passing `-f` if possible)
      chmod +w "$x"
    done

    [ -d "$1" ] && [ -r "$1" ] && cd "$1"
    shift

    set +e
    source /etc/profile
    if [ -n "$DBG" ] ; then
      echo "DEBUG: pkgtmp=$pkgtmp"
      strace -o "$pkgtmp/strace" -- "$pkgtmp/$cmd" "$@"
      x=$?
      #rm -r "$pkgtmp"  # don't delete in debug mode
      exit $x
    else
      "$pkgtmp/$cmd" "$@"
      x=$?
      rm -r "$pkgtmp"
      exit $x
    fi
  '';

  bflb-crypto-plus = pkgs.python3Packages.buildPythonPackage {
    pname = "bflb-crypto-plus";
    version = "1.0";
    src = bflb-crypto-plus-pypi;
    propagatedBuildInputs = with pkgs.python3Packages; [
      ecdsa pycryptodome setuptools
    ];
  };
  pycklink = pkgs.python3Packages.buildPythonPackage {
    pname = "pycklink";
    version = "0.1.1";
    src = pycklink-pypi;
  };
  portalocker_2_0 = with pkgs.python3Packages; buildPythonPackage rec {
    pname = "portalocker";
    version = "2.0.0";
    format = "setuptools";
  
    src = fetchPypi {
      inherit pname version;
      hash = "sha256-FEh+7YGqkUEn7fAoTinHyohCwFuzPZbcfkvbRygtJuQ=";
    };
  
    propagatedBuildInputs = [
      redis
    ];

    doCheck = false;
  };
  bflb-common = { pname, ... }@args: pkgs.python3Packages.buildPythonApplication (args // {
    # This doesn't seem to work for us.
    nativeBuildInputs = [ pkgs.python3Packages.pythonRelaxDepsHook ];
    pythonRelaxDeps = [ "pycryptodome" "pylink-square" "portalocker" ];
    #NIX_DEBUG = 1;

    #patches = [ ./bflb_mcu_tool.patch ];

    prePatch = ''
      for x in setup.py *.egg-info/requires.txt ; do
        sed -i 's/\(portalocker\|pylink-square\|pycryptodome\)=[=0-9.]*/\1/' "$x"
      done
    '';

    propagatedBuildInputs = with pkgs.python3Packages; [
      ecdsa pycryptodome bflb-crypto-plus pycklink pyserial pylink-square portalocker
    ];

    # no need to fixup binaries because they are prebuilt but we need fixup for the startup script
    #dontFixup = true;

    postInstall = (args.postInstall or "") + ''
      mv $out/bin/${pname} $out/bin/.${pname}.unwrapped
      ( echo "#! ${pkgs.bash}/bin/bash"; echo "${chrootenv}/bin/chrootenv ${init-env-for-flash-tools} $out bin/.${pname}.unwrapped \"\$(pwd)\" \"\$@\"" ) >$out/bin/${pname}
      chmod +x $out/bin/${pname}
    '';
  });
  bflb-mcu-tool = bflb-common {
    pname = "bflb-mcu-tool";
    version = "1.8.1";
    src = bflb-mcu-tool-pypi;
  };
  bflb-iot-tool = bflb-common {
    pname = "bflb-iot-tool";
    version = "1.8.1";
    src = bflb-iot-tool-pypi;

    postPatch = ''
      echo 'entry_points["console_scripts"].append("bflb_eflash_loader = libs.bflb_eflash_loader:run")' >>setup.py
      #echo 'entry_points["console_scripts"].append("bflb_eflash_loader_client = libs.bflb_eflash_loader_client:...")' >>setup.py
      echo 'entry_points["console_scripts"].append("bflb_eflash_loader_server = libs.bflb_eflash_loader_server:eflash_loader_server_main")' >>setup.py
      echo 'entry_points["console_scripts"].append("bflb_efuse_boothd_create = libs.bflb_efuse_boothd_create:run")' >>setup.py
      echo 'entry_points["console_scripts"].append("bflb_img_create = libs.bflb_img_create:run")' >>setup.py
      #bflb_iot_tool/libs/bflb_img_loader.py:if __name__ == '__main__': -> TODO

      echo 'bflb_eflash_loader = libs.bflb_eflash_loader:run' >>bflb_iot_tool.egg-info/entry_points.txt
      echo 'bflb_eflash_loader_server = libs.bflb_eflash_loader_server:eflash_loader_server_main' >>bflb_iot_tool.egg-info/entry_points.txt
      echo 'bflb_efuse_boothd_create = libs.bflb_efuse_boothd_create:run' >>bflb_iot_tool.egg-info/entry_points.txt
      echo 'bflb_img_create = libs.bflb_img_create:run' >>bflb_iot_tool.egg-info/entry_points.txt
    '';

    postInstall = ''
      #ln -s $out/lib/python3.10/site-packages/bflb_iot_tool/libs/bflb_eflash_loader.py $out/bin/bflb_eflash_loader
      #chmod +x $out/lib/python3.10/site-packages/bflb_iot_tool/libs/bflb_eflash_loader.py
      ( echo "#! /usr/bin/python3"; echo "from bflb_iot_tool.libs.bflb_eflash_loader import run; run()" ) >>$out/bin/bflb_eflash_loader
      chmod +x $out/bin/bflb_eflash_loader
    '';

    patches = [ ./bflb-iot-tool-1.8.1.patch ];
  };

  thead-debugserver = pkgs.stdenv.mkDerivation {
    name = "thead-debugserver";

    src = thead-debugserver-download;

    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = with pkgs; [ libusb libstdcxx5 ];

    # The download is an interactive shell script that doesn't seem to have any provisions
    # for batch processing. No thanks. That way, we will also avoid sudo and 777+suid permissions.
    unpackPhase = ''
      tail -n+282 $src/*.sh | tar -xz
      cd T-HEAD_DebugServer
    '';

    buildPhase = ''
      #FIXME The original script is setting +x and +s on many .elf and .so files. Do we really need suid anywhere?
      chmod +x DebugServerConsole.elf
      find -name "*.so" -exec chmod -x {} \+
    '';

    installPhase = ''
      mkdir -p $out/share $out/bin
      cp -r . $out/share/thead-debugserver

      #ln $out/share/thead-debugserver/DebugServerConsole.elf $out/bin/DebugServerConsole
      # -> would look for further files in the wrong place (and then segfault)
      ( echo "#! ${pkgs.bash}/bin/bash"; echo "exec $out/share/thead-debugserver/DebugServerConsole.elf \"\$@\"" ) \
        >$out/bin/DebugServerConsole
      chmod +x $out/bin/DebugServerConsole

      #patchelf --rpath $out/share/thead-debugserver $out/share/thead-debugserver/DebugServerConsole.elf
      extraAutoPatchelfLibs=($out/share/thead-debugserver)
    '';
  };

  init-env-for-lab-dev-cube = pkgs.writeShellScript "init-env-for-flash-tools" ''
    for i in ${bflb-lab-dev-cube-env}/* /host/*; do
      path="/''${i##*/}"
      [ -e "$path" ] || ${pkgs.coreutils}/bin/ln -s "$i" "$path"
    done

    set -e

    # create a writable copy of the files in /tmp because it will be
    # writing temporary files into its tree
    pkg="$1"
    cmd="$2"
    shift
    shift
    pkgtmp=$(mktemp -td bflb-tmp.XXXXXXXX)
    ${pkgs.xorg.lndir}/bin/lndir -silent "$pkg" "$pkgtmp"
    chmod -R u+w "$pkgtmp/"

    sed -bi "" "$pkgtmp/$cmd"
    chmod +w "$pkgtmp/$cmd"

    [ -d "$1" ] && [ -r "$1" ] && cd "$1"
    shift

    set +e
    source /etc/profile
    if [ -n "$DBG" ] ; then
      echo "DEBUG: pkgtmp=$pkgtmp"
      strace -o "$pkgtmp/strace" -- "$pkgtmp/$cmd" "$@"
      x=$?
      #rm -r "$pkgtmp"  # don't delete in debug mode
      exit $x
    else
      "$pkgtmp/$cmd" "$@"
      x=$?
      rm -r "$pkgtmp"
      exit $x
    fi
  '';

  bflb-lab-dev-cube = pkgs.stdenv.mkDerivation rec {
    pname = "bflb-lab-dev-cube";
    version = src.version;

    src = LabDevCube;
    dontUnpack = true;
    dontBuild = true;

    nativeBuildInputs = [ pkgs.makeWrapper ];

    installPhase = ''
      mkdir -p $out/bin $out/share
      dist=$out/share/bflb-lab-dev-cube
      cp -r $src $dist
      chmod +x $dist/utils/genromfs/genromfs_*

      for x in bflb_iot_tool BLDevCube ; do
        target=''${x}-ubuntu
        chmod +x $dist/$target

        # We unset WAYLAND_DISPLAY in the wrapper because they bring their own Qt libraries
        # and they fail for Wayland.
        makeWrapper ${bflb-lab-dev-cube-env}/bin/bflb-lab-dev-cube-env $out/bin/$x \
          --add-flags "${init-env-for-lab-dev-cube} $dist $target \"\$(pwd)\"" \
          --unset WAYLAND_DISPLAY
      done
    '';
  };

  bflb-tools = pkgs.runCommand "bflb-tools" {} ''
    mkdir -p $out/bin
    ln -s ${bflb-mcu-tool}/bin/bflb-mcu-tool $out/bin/
    cp -s ${bflb-iot-tool}/bin/* $out/bin/
    ln -s ${thead-debugserver}/bin/DebugServerConsole $out/bin/
    cp -s ${bflb-lab-dev-cube}/bin/* $out/bin/
  '';

  rootfs = pkgs.stdenv.mkDerivation {
    name = "rootfs";
    src = null;
    dontUnpack = true;

    nativeBuildInputs = with pkgs; [ fakeroot squashfsTools ];
    busybox = pkgs.pkgsCross.riscv64.pkgsStatic.busybox;

    buildImage = ''
      set -e
      mkdir x
      cd x
      cp -r ${./rootfs}/* .
      cp -r $busybox/* .
      chown -R root:root .
      mkdir -p ./dev/pts
      mkdir -p ./etc/hotplug.d
      mkdir -p ./home/root
      mkdir -p ./lib
      #mkdir -p ./mnt/mmc
      #mkdir -p ./mnt/mmc/mmcblk0p1
      #mkdir -p ./mnt/mtd
      #mkdir -p ./mnt/usb/sda
      #mkdir -p ./mnt/usb/sda1
      mkdir -p ./proc
      mkdir -p ./share
      mkdir -p ./sys
      mkdir -p ./tmp
      mkdir -p ./usr/lib
      mkdir -p ./usr/share
      mkdir -p ./var/lib
      mkdir -p ./var/volatile

      mknod ./dev/console c 5 1
      mknod ./dev/null    c 1 3

      mksquashfs . ../squashfs_test.img -comp gzip  #TODO lz4
    '';
    passAsFile = [ "buildImage" ];

    buildPhase = ''
      fakeroot bash $buildImagePath
    '';

    installPhase = ''
      cp squashfs_test.img $out
    '';
  };
in
  with pkgs;
  stdenv.mkDerivation {
    passthru = downloads // {
      inherit keep-downloads
        bflb-mcu-tool bflb-iot-tool bflb-tools thead-debugserver rootfs;
    };

    name = "bl808_linux";

    src = fetchFromGitHub {
      owner = "bouffalolab";
      repo = "bl808_linux";
      rev = "561ee61222e5d5e7d028b5cf237c0ddf4a616f1e";
      hash = "sha256-k8wm4e7/ynPoY+ZVGnHIoq7o1yCrBKInFsUDL2xqK1w=";
    };

    patches = [
      ./bl808-linux-dts.patch
      ./bl808-linux-enable-jtag.patch
    ];

    inherit rootfs;

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
  }
