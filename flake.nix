{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-22.11";
    flake-utils.url = "github:numtide/flake-utils";

    uboot = {
      url = "github:madushan1000/u-boot/bl808/usb-udc";
      flake = false;
    };

    kernel = {
      url = "github:arm000/linux-bl808/linux-next/mboxic";
      flake = false;
    };

    oblfr = {
      url = "github:openbouffalo/OBLFR";
      flake = false;
    };

    bl_mcu_sdk = {
      url = "github:bouffalolab/bl_mcu_sdk";
      flake = false;
    };

    opensbi = {
      url = "github:riscv-software-src/opensbi/v1.2";
      flake = false;
    };

    buildroot_bouffalo = {
      url = "github:openbouffalo/buildroot_bouffalo";
      flake = false;
    };
  };

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
      // callPackageIfFunction final.callPackage ./pkgs/bl808-linux-2.nix {
        kernel-source = self.inputs.kernel;
        oblfr-source = self.inputs.oblfr;
        bl_mcu_sdk-source = self.inputs.bl_mcu_sdk;
        opensbi-source = self.inputs.opensbi;
        inherit (self.inputs) buildroot_bouffalo;
      }
      // callPackageIfFunction final.callPackage (import ./pkgs/xuantie-gnu-toolchain.nix { inherit (nixpkgs) lib; }) { }
      // callPackageIfFunction final.callPackage ./pkgs/bl808-regs-py.nix { }
      // callPackageIfFunction final.callPackage ./pkgs/buildroot.nix { }
      // {
        inherit nixpkgs;  # used to import chrootenv in bflb-tools.nix
        thead-debugserver = final.callPackage ./pkgs/thead-debugserver.nix { };
        bflb-lab-dev-cube = final.callPackage ./pkgs/bflb-lab-dev-cube.nix { };
        bl808-rootfs = final.callPackage ./pkgs/bl808-rootfs.nix { };
        bl808-rootfs-dir = final.callPackage ./pkgs/bl808-rootfs.nix { asDir = true; };
        prebuilt-linux = final.callPackage ./pkgs/prebuilt-linux.nix { };
        uboot = final.callPackage ./pkgs/uboot.nix { source = self.inputs.uboot; };
        #musl = if final.stdenv.hostPlatform.system != "riscv32-linux" then prev.musl else
        #prev.musl.overrideAttrs (old: {
        #  postPatch = (old.postPatch or "") + ''
        #    substituteInPlace configure --replace "riscv64" "riscv32"
        #    ln -s riscv64 arch/riscv32
        #  '';
        #});
        nxpmicro-mfgtools = prev.nxpmicro-mfgtools.overrideAttrs (_: {
          # We are using a newer version here but that's probably not necessary.
          version = "1.5.21";
          src = final.fetchFromGitHub {
            owner = "nxp-imx";
            repo = "mfgtools";
            rev = "uuu_1.5.21";
            hash = "sha256-XVvGsHltlA3h9hd3C88G3s2wIZ1EVM6DmvdiwD82vTw=";
          };
          patches = [ ./patches/nxpmicro-mfgtools--add-our-usb-vid-pid.patch ];
        });
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
        xuantie-gnu-toolchain-multilib-newlib
        xuantie-gnu-toolchain-multilib-linux

        chrootenv
        #bflb-crypto-plus
        #pycklink
        #portalocker_2_0
        bflb-mcu-tool
        bflb-iot-tool
        bflb-lab-dev-cube
        thead-debugserver
        bflb-tools
        nxpmicro-mfgtools

        bl808-rootfs
        bl808-rootfs-dir
        bl808-regs-py
        prebuilt-linux
        bl808-linux-2
        bl808-linux-2-flash-script
        bl808-buildroot-flash-script;

      #inherit (all-pkgs.pkgsCross.riscv32.pkgsMusl)
      inherit (all-pkgs.pkgsCross.riscv32)
        uboot;

      default = packages.bl808-linux-2-flash-script;

      keep-downloads = with all-pkgs; let
        downloads = builtins.mapAttrs (k: v: v.src or v.with-blobs.src) {
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

      buildroot-dev-env = pkgs.buildFHSUserEnv {
        name = "build-env";
        targetPkgs = pkgs: with pkgs; [
          gnumake gcc file unzip file bc openssl gnulib glibc zlib
          python3
          #pkgsCross.riscv64.libxcrypt
          #(libxcrypt.overrideAttrs (_: { postInstall = ''rm $out/lib/*.so* -f''; }))
          ((import nixpkgs {
            inherit system;
            crossSystem = pkgs.lib.systems.examples.riscv64 // {
              gcc.arch = "rv64imac";
            };
          }).libxcrypt)
        ];
        multiPkgs = pkgs: with pkgs; [
          glibc
        ];
        runScript = "bash";
        extraOutputsToInstall = [ "dev" ];
      };
    };

    checks = {
      inherit (packages)
        bflb-tools
        prebuilt-linux
        bl808-linux-2;
    };

    devShells = {
      default = packages.bl808-dev-env.env;
      buildroot = packages.buildroot-dev-env.env;
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
      bl808-linux-flash-rootfs = mkAppWithArgs {
        drv = packages.bflb-iot-tool;
        args = defaultFlashArgs ++ [ "--addr" "0x552000" "--firmware" packages.bl808-rootfs "--single" ];
      };
      bl808-linux-2-flash-img = mkAppWithArgs {
        drv = packages.bflb-iot-tool;
        args = defaultFlashArgs ++ [ "--addr" "0xD2000" "--firmware" "${packages.bl808-linux-2}/whole_img_linux.bin" "--single" ];
      };
      bl808-linux-2-flash = mkAppWithArgs {
        drv = packages.bl808-linux-2-flash-script;
      };
      uuu = mkAppWithArgs {
        drv = packages.nxpmicro-mfgtools;
        exePath = "/bin/uuu";
      };
    };
  });
}
