# nix build -L . -o out
# nix build -L .#bflb-tools -o result-tools
# nix build -L .#keep-downloads -o keep-downloads
# Flash out/low_load_bl808_{d0,m0}.bin using the GUI:
#   nix run .#BLDevCube
#   Step 2 in keep-downloads/prebuilt-linux/steps.md but use the files in ./out
# Keep chip in bootloader mode and run:
#   nix run .#bl808-linux-1-flash-img --port /dev/ttyUSB1
#   (or: result-tools/bin/bflb-iot-tool --chipname bl808 --port /dev/ttyUSB1 --baudrate 2000000 --addr 0xD2000  --firmware out/whole_img_linux.bin  --single)
# Open /dev/ttyUSB0 with baudrate 2000000, press reset button, wait for login prompt and login as root.
#
# Update only the rootfs:
#   nix run .#bl808-linux-1-flash-rootfs
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-22.11";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils, ... }:
  let
    #defaultSystems = flake-utils.lib.defaultSystems;
    # -> no darwin, for now, because it doesn't support chrootenv (and libstdcxx5)
    defaultSystems = ["aarch64-linux" "x86_64-linux"];
  
    callPackageIfFunction = callPackage: x: extra:
      with builtins;
      with nixpkgs.lib;  # after builtins because isFunction must come from here
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
      // callPackageIfFunction final.callPackage ./pkgs/bl808-linux-2.nix { }
      // {
        inherit nixpkgs;  # used to import chrootenv in bflb-tools.nix
        thead-debugserver = final.callPackage ./pkgs/thead-debugserver.nix { };
        bflb-lab-dev-cube = final.callPackage ./pkgs/bflb-lab-dev-cube.nix { };
        bl808-rootfs = final.callPackage ./pkgs/bl808-rootfs.nix { };
        prebuilt-linux = final.callPackage ./pkgs/prebuilt-linux.nix { };
      };
  in {
    #inherit overlay;  # deprecated
    overlays.default = overlay;
  } // flake-utils.lib.eachSystem defaultSystems (system: let
    all-pkgs = import nixpkgs { inherit system; overlays = [ overlay ]; };
    pkgs = nixpkgs.legacyPackages.${system};

    dummy = derivation {
      inherit system;
      name = "dummy--contains_all_packages__for_debugging_only";
      builder = pkgs.bash;
      args = ["-c" "echo \"This derivation is not meant to be built.\"; exit 1" ];
    };
  in rec {
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
        bl808-linux-1
        bl808-linux-2;

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

    checks = {
      inherit (packages)
        bflb-tools
        prebuilt-linux
        bl808-linux-1;
    };

    devShells = {
      default = packages.bl808-dev-env.env;
      #TODO maybe add a shell with bflb-tools?
    };

    apps = let
      # similar to flake-utils's mkApp but we support adding extra arguments
      mkAppWithArgs = { drv, name ? drv.pname or drv.name, exePath ? drv.passthru.exePath or "/bin/${name}", args ? [] }:
      let
        exe = "${drv}${exePath}";
        program = if args == [] then exe else (pkgs.writeShellScript name ''
          echo "+" ${pkgs.lib.escapeShellArgs ([exe] ++ args)} "$@"
          exec ${pkgs.lib.escapeShellArgs ([exe] ++ args)} "$@"
        '').outPath;
      in { type = "app"; inherit program; };

      # The port assumes that we are using M1s dock and there aren't any other USB2serial converters attached (or only ones that show up as ttyACM rather than ttyUSB).
      # We could omit the argument but bflb-iot-tool would still use its own default.
      defaultFlashArgs = [ "--chipname" "bl808" "--baudrate" "2000000" "--port" "/dev/ttyUSB1" ];
    in (builtins.mapAttrs (name: drv: flake-utils.lib.mkApp { inherit name drv; }) {
      inherit (packages)
        bflb-mcu-tool
        bflb-iot-tool
        bflb-lab-dev-cube
        thead-debugserver;
      BLDevCube = packages.bflb-lab-dev-cube;
      DebugServerConsole = packages.thead-debugserver;
    }) // {
      bl808-linux-1-flash-img = mkAppWithArgs {
        drv = packages.bflb-iot-tool;
        args = defaultFlashArgs ++ [ "--addr" "0xD2000" "--firmware" "${packages.bl808-linux-1}/whole_img_linux.bin" "--single" ];
      };
      bl808-linux-1-flash-rootfs = mkAppWithArgs {
        drv = packages.bflb-iot-tool;
        args = defaultFlashArgs ++ [ "--addr" "0x552000" "--firmware" packages.bl808-rootfs "--single" ];
      };
    };
  });
}
