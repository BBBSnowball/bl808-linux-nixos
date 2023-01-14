{ stdenv, fakeroot, squashfsTools, pkgsCross, writeReferencesToFile, linkFarmFromDrvs, asDir ? false, python3, pkg-config }:
let
  pkgsTarget = pkgsCross.riscv64.pkgsMusl;
  pkgsTargetStatic = pkgsCross.riscv64.pkgsStatic;

  asDirStr = if asDir then "true" else "false";
in
stdenv.mkDerivation rec {
  name = "rootfs";
  src = null;
  dontUnpack = true;

  nativeBuildInputs = [ fakeroot squashfsTools ];
  busybox = pkgsTarget.busybox;
  tcl = pkgsTarget.tcl.overrideAttrs (old: {
    configureFlags = [
      #"--help"
      "--enable-threads"
      "--enable-64bit"
      #"--disable-load"
      #"--without-tzdata"
    ];
  });
  micropython = (pkgsTarget.micropython.override { python3 = python3; }).overrideAttrs (old: {
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
  });
  lua = pkgsTarget.lua.override {
    # no readline because that pulls in ncurses, which is too big
    readline = null;
    postConfigure = ''
      makeFlagsArray+=(PLAT=linux MYLIBS=-ldl -j$NIX_BUILD_CORES)
      echo "#undef LUA_USE_READLINE" >>./src/luaconf.h
      substituteInPlace src/Makefile --replace "-lreadline" ""
    '';
  };

  #refsDrv = linkFarmFromDrvs "refs" [ busybox tcl ];
  refsDrv = linkFarmFromDrvs "refs" [ busybox micropython lua ];
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
    rm -rf nix/store/*/{lib/*.a,lib/*.o,lib/pkgconfig,man/,share/terminfo}

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
    ln -s ${busybox}/linuxrc .
    ln -s ${busybox}/default.script .

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
