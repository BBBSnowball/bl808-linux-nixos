{ stdenv, fakeroot, squashfsTools, pkgsCross, writeReferencesToFile, linkFarmFromDrvs, asDir ? false }:
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

  #refsDrv = linkFarmFromDrvs "refs" [ busybox tcl ];
  refsDrv = linkFarmFromDrvs "refs" [ busybox ];
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
    rm -rf nix/store/*/{lib/*.a,lib/*.o,man/}

    mkdir bin
    ln -s bin sbin
    for x in nix/store/*/bin/* ; do
      ln -s "/$x" "bin/''${x##*/}"
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
}
