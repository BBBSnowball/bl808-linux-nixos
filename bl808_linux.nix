# nix-shell ../bl808_linux.nix -A env
{ pkgs ? import <nixpkgs> {} }:
(pkgs.buildFHSUserEnv {
  name = "build-env";
  targetPkgs = pkgs: with pkgs;
    [
      autoPatchelfHook zlib flex bison ncurses pkg-config
      #ncurses5
      gcc binutils
      bc
      dtc lz4

      (python3.withPackages (p: with p; [ pyside ]))
    ];
  multiPkgs = pkgs: with pkgs;
    [ glibc
    xorg.libX11
    ];
  runScript = "bash";
  extraOutputsToInstall = [ "dev" ];
})
