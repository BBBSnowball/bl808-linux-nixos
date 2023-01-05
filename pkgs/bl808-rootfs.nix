{ stdenv, fakeroot, squashfsTools, pkgsCross }:
stdenv.mkDerivation {
  name = "rootfs";
  src = null;
  dontUnpack = true;

  nativeBuildInputs = [ fakeroot squashfsTools ];
  busybox = pkgsCross.riscv64.pkgsStatic.busybox;

  buildImage = ''
    set -e
    mkdir x
    cd x
    cp -r ${../rootfs}/* .
    cp -r $busybox/* .
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

    mksquashfs . ../squashfs_test.img -comp gzip  #TODO lz4
  '';
  passAsFile = [ "buildImage" ];

  buildPhase = ''
    fakeroot bash $buildImagePath
  '';

  installPhase = ''
    cp squashfs_test.img $out
  '';
}
