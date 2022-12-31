# nix-shell ../bl808_linux.nix -A env
{ pkgs ? import <nixpkgs> {} }:
(pkgs.buildFHSUserEnv {
  name = "build-env";
  targetPkgs = pkgs: with pkgs;
    [
      autoPatchelfHook zlib flex bison pkg-config
      ncurses5
      gcc binutils
      bc
      dtc lz4
      libGL xorg.libxcb

      #(python3.withPackages (p: with p; [ pyside2 ]))
      #(python3.withPackages (p: with p; [ qtpy ]))
      #python3
    ];
  multiPkgs = pkgs: with pkgs;
    [ glibc
    xorg.libX11
    ];
  runScript = "bash";
  extraOutputsToInstall = [ "dev" ];
})
