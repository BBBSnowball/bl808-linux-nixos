{ stdenv, fakeroot, squashfsTools, pkgsCross, nixpkgs, system
, writeReferencesToFile, linkFarmFromDrvs, asDir ? false, python3, pkg-config, fetchFromGitHub, runCommand, bl808-regs-py }:
let
  pkgs = import nixpkgs {
    inherit system;
    overlays = [(final: prev: {
      gcc = final.gcc12.override (old1: {
        cc = old1.cc.overrideAttrs (old: {
          patches = old.patches ++ [ ../patches/gcc-12-darwin-aarch64-remove-nodefaultrpath.patch ];
        });
      });
    })];
  };
  pkgsTarget = pkgs.pkgsCross.riscv64.pkgsMusl;
  pkgsTargetStatic = pkgs.pkgsCross.riscv64.pkgsStatic;

  asDirStr = if asDir then "true" else "false";
in
stdenv.mkDerivation rec {
  name = "rootfs";
  src = null;
  dontUnpack = true;

  nativeBuildInputs = [ fakeroot squashfsTools ];
  passthru.busybox = pkgsTarget.busybox;

  # Usage:
  # import machine
  # machine.mem32[0x200008E4] = 0x00400b42  # led on
  # machine.mem32[0x200008E4] = 0x01400b42  # led off
  #
  # Start with `-X heapsize=4M` if you want to use bl808_regs.py.
  passthru.micropython = (pkgsTarget.micropython.override { python3 = python3; }).overrideAttrs (old: {
    # We need a compiler for the host to build mpy-cross. The build complains that pkg-config is missing so let's add that, as well.
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ stdenv.cc pkg-config ];

    buildPhase = ''
      runHook preBuild
      make -C mpy-cross -j$NIX_BUILD_CORES

      # - use cross-compiler here (but not for mpy-cross)
      # - don't set Q= to the cross-compiler prefix because that's also used to call Python
      # - remove -Werror from CWARN
      make -C ports/unix CC=${pkgsTarget.stdenv.cc.targetPrefix}gcc CROSS_COMPILE=${pkgsTarget.stdenv.cc.targetPrefix} CWARN=-Wall -j$NIX_BUILD_CORES
      runHook postBuild
    '';

    outputs = [ "out" "mpycross" ];

    installPhase = old.installPhase + ''
      install -Dm755 mpy-cross/mpy-cross -t $mpycross/bin
    '';
  });
  passthru.micropythonPrecompile = drv: runCommand "${drv.name}-mpy" {} ''
    cp -r ${drv} $out
    chmod -R +w $out
    find $out/usr/lib/micropython -name "*.py" | while read x ; do
      ${passthru.micropython.mpycross}/bin/mpy-cross -X heapsize=4M "$x"
      rm "$x"
    done
  '';

  # Usage:
  # MMIO = require('periphery').MMIO
  # glb = MMIO(0x20000000, 0x1000)
  # glb:write32(0x8e4, 0x00400b42)  # led on
  # glb:write32(0x8e4, 0x01400b42)  # led off
  passthru.lua = (pkgsTarget.lua.override {
    # no readline because that pulls in ncurses, which is too big
    readline = null;
    postConfigure = ''
      makeFlagsArray+=(PLAT=linux MYLIBS=-ldl -j$NIX_BUILD_CORES)
      echo "#undef LUA_USE_READLINE" >>./src/luaconf.h
      substituteInPlace src/Makefile --replace "-lreadline" ""
    '';

    packageOverrides = final: prev: {
      lua-periphery = final.buildLuaPackage {
        pname = "lua-periphery";
        version = "2.3.1";
        src = fetchFromGitHub {
          owner = "vsergeev";
          repo = "lua-periphery";
          rev = "v2.3.1";
          hash = "sha256-6G7sUNGob/xqexQ4KsW6oq+hMI38vd2tos2KPRSByQQ=";
          fetchSubmodules = true;
        };
      };
      lua = passthru.lua;
    };
  });
  passthru.luaWithPkgs = passthru.lua.withPackages (p: [ p.lua-periphery ]);

  refsDrv = linkFarmFromDrvs "refs" (with passthru; [
    busybox
    micropython
    (passthru.micropythonPrecompile bl808-regs-py)
    #luaWithPkgs
    (pkgsTarget.screen.override { pam = null; })
    #(pkgsTarget.lrzsz)
    (pkgsTarget.lrzsz.overrideAttrs (old: { postInstall = ''rm $out/bin/{rx,rb,sx,sb}''; }))
  ]);
  refs = writeReferencesToFile refsDrv;

  buildImage = ''
    set -e
    mkdir x
    cd x

    cp -r ${../rootfs}/* .

    #cp -r $busybox/* .
    mkdir -p nix/store
    while read x ; do
      cp -r $x nix/store/
    done <$refs
    rm -rf nix/store/*/{lib/*.a,lib/*.o,lib/pkgconfig,man/,share/man/}
    #rm -rf nix/store/*/share/terminfo/[0-9a-uw-zA-Z]*  # keep "v" for vt100
    for x in nix/store/*/share/terminfo ; do
      ( cd $x && rm -rf [0-9a-uw-zA-Z]* && mv v w && mkdir v && mv w/{vt100,vt100-am} v/ && rm -rf w )
    done

    mkdir bin
    ln -s bin sbin
    for x in nix/store/*/bin/* ; do
      if [ ! -e "bin/''${x##*/}" ] ; then
        ln -s "/$x" "bin/''${x##*/}"
      else
        echo "WARN: File already exists: bin/''${x##*/}"
        echo "  points to $(realpath "bin/''${x##*/}")"
        echo "  ignoring  /$x"
      fi
    done
    ln -s $busybox/linuxrc .
    ln -s $busybox/default.script .

    mkdir -p usr/lib/micropython
    for x in nix/store/*/usr/lib/micropython/* ; do
      ln -s ../../../$x usr/lib/micropython/
    done

    chown -R root:root .
    mkdir -p ./dev/pts
    mkdir -p ./etc/hotplug.d
    mkdir -p ./root
    mkdir -p ./home
    mkdir -p ./lib
    mkdir -p ./mnt/{mmc,mtd}
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

    if ! ${asDirStr} ; then
      # Lua references this but it doesn't seem to be required for our use case
      #rm -rf nix/store/*-riscv64-unknown-linux-musl-stage-final-*-lib

      mksquashfs . ../squashfs_test.img -comp gzip  #TODO lz4
    fi
  '';
  passAsFile = [ "buildImage" ];

  buildPhase = ''
    fakeroot bash $buildImagePath
  '';

  installPhase = ''
    if ${asDirStr} ; then
      cp -r x $out
    else
      cp squashfs_test.img $out
    fi
  '';

  dontFixup = true;
}
