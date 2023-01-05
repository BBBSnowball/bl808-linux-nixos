# nix build . -o out
# nix build .#bflb-tools -o result-tools
# nix build .#keep-downloads -o keep-downloads
# Flash out/low_load_bl808_{d0,m0}.bin using the GUI:
#   result-tools/bin/BLDevCube
#   Step 2 in keep-downloads/prebuilt-linux/steps.md
# Keep chip in bootloader mode and run:
# result-tools/bin/bflb-iot-tool --chipname bl808 --port /dev/ttyUSB1 --baudrate 2000000 --addr 0xD2000  --firmware out/whole_img_linux.bin  --single
# Open /dev/ttyUSB0 with baudrate 2000000 and login as root.
#
# Update only the rootfs:
# nix build .#bl808-rootfs -o result-rootfs && ./result-tools/bin/bflb-iot-tool --chipname bl808 --port /dev/ttyUSB1 --baudrate 2000000 --addr 0x552000 --firmware result-rootfs --single
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-22.11";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils, ... }:
  flake-utils.lib.eachDefaultSystem (system: let
    callPackageIfFunction = callPackage: x: extra:
      with builtins;
      let
        x' = if isPath x then import x else x;
        x'' = if isFunction x' then callPackage x' extra else x';
        recurse = x: callPackageIfFunction callPackage x extra;
      in
      if isAttrs x'' && !(x'' ? outPath) then mapAttrs (k: recurse) x''
      else if isList x'' then map recurse x''
      else x'';
    overlay = final: prev:
      callPackageIfFunction final.callPackage ./pkgs/prebuilt-toolchain.nix { }
      // callPackageIfFunction final.callPackage ./pkgs/bflb-tools.nix { }
      // callPackageIfFunction final.callPackage ./pkgs/bflb-tools-all.nix { }
      // callPackageIfFunction final.callPackage ./pkgs/bl808-linux-1.nix { }
      // {
        inherit nixpkgs;  # used to import chrootenv in bflb-tools.nix
        thead-debugserver = final.callPackage ./pkgs/thead-debugserver.nix { };
        bflb-lab-dev-cube = final.callPackage ./pkgs/bflb-lab-dev-cube.nix { };
        bl808-rootfs = final.callPackage ./pkgs/bl808-rootfs.nix { };
        prebuilt-linux = final.callPackage ./pkgs/prebuilt-linux.nix { };
      };
    all-pkgs = import nixpkgs { inherit system; overlays = [ overlay ]; };
  in let
    # We define this in a separate `let` so we don't accidentally use it in the overlay.
    pkgs = nixpkgs.legacyPackages.${system};

    dummy = derivation {
      inherit system;
      name = "dummy (contains all packages, for debugging)";
      builder = pkgs.bash;
      args = ["-c" "echo \"This derivation is not meant to be built.\"; exit 1" ];
    };
  in rec {
    overlays.default = overlay;

    packages = {
      inherit (all-pkgs)
        prebuiltCmake
        prebuiltGccBaremetal
        prebuiltGccLinux

        chrootenv
        #bflb-crypto-plus
        #pycklink
        #portalocker_2_0
        bflb-mcu-tool
        bflb-iot-tool
        bflb-lab-dev-cube
        thead-debugserver
        bflb-tools

        bl808-rootfs
        prebuilt-linux
        bl808-linux-1;

      default = packages.bl808-linux-1;

      keep-downloads = with all-pkgs; let
        downloads = builtins.mapAttrs (k: v: v.src) {
          inherit bflb-iot-tool bflb-mcu-tool pycklink bflb-crypto-plus
            bflb-lab-dev-cube thead-debugserver;
        } // {
          inherit
            prebuilt-linux
            prebuiltCmake
            prebuiltGccBaremetal
            prebuiltGccLinux;
      };
      in pkgs.linkFarm "bl808_downloads" downloads // { inherit downloads; };

      # make all packages available for debugging (and dummy is to make it a valid derivation with as few attributes of its own as possible)
      all = all-pkgs // dummy;

      bl808-dev-env = pkgs.buildFHSUserEnv {
        name = "build-env";
        targetPkgs = pkgs: with pkgs; [
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
        multiPkgs = pkgs: with pkgs; [
          glibc
          xorg.libX11
        ];
        runScript = "bash";
        extraOutputsToInstall = [ "dev" ];
      };
    };

    devShells.default = packages.bl808-dev-env.env;
  });
}
