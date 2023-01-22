{ lib }:
let
  overrideArgs = f: values: let
    argInfo = lib.functionArgs f;
  in lib.setFunctionArgs (x: f (x // values)) (builtins.removeAttrs argInfo (builtins.attrNames values));

  submodules = rec {
    riscv-gdb = {
      owner = "T-head-Semi";
      repo = "binutils-gdb";
      rev = "b34ac3415950d057a58ae55b99ee3829faa7acb7";
      hash = "sha256-ea22SYqDsMruULkFSCKhep0OMLW1tN1/s5cY93yoj0w=";
    };
    riscv-binutils = riscv-gdb;
    riscv-gcc = {
      owner = "T-head-Semi";
      repo = "gcc";
      rev = "8b6f9697e06a25dce47185b3caade67fd0cede60";
      hash = "sha256-wdD56EQctcyrqccwzkEEUYT4xU/sNsQXgUMThzsEn9A=";
    };
    riscv-glibc = {
      owner = "T-head-Semi";
      repo = "glibc";
      rev = "6aea17dafd37cf8b81c9cca05a8928ebc54f7efb";
      hash = "sha256-rYyWSa6hfB+wI6w1E/sowHbMHt9cEDjLJr56N2D56rc=";
    };
    riscv-dejagnu = {
      owner = "riscv-collab";
      repo = "riscv-dejagnu";
      rev = "4ea498a8e1fafeb568530d84db1880066478c86b";
      hash = "sha256-x/8yNMl0NKN0BpUHEFiAamJfvn2szaN73a8akt/AO+o=";
    };
    riscv-newlib = {
      owner = "T-head-Semi";
      repo = "newlib";
      rev = "00a83b57fca908d8fe712d1f9d979ab9d6813ec3";
      hash = "sha256-OVs8utd7O4th2A9xdn/APfUPYyk++wCNmZI3RxYdfX4=";
    };
    qemu = {
      owner = "T-head-Semi";
      repo = "qemu";
      rev = "5af674035298c07b361de69afdabf2fcbb37da71";
      hash = "sha256-iokyH31rvOe4p46sMhKAT8f8yinMEverwCwzM68FfgU=";
    };
    #riscv-libcc-runtime 0c4b221aad121e291e506edc36cb5ee5db3457e2
    #riscv-musl 21e7d71d5a470eb7f3f230cdc9edcd053ab00fc1
  };
in
rec {
  xuantie-gnu-toolchain =
    { stdenv, fetchFromGitHub, linkFarm
    , gnugrep, autoconf, automake, curl, python3, libmpc, mpfr, gmp, gawk, bison, flex, texinfo, gperf, libtool, patchutils, bc, zlib, expat
    , file, util-linux
    , suffix, target, configureArgs ? "" }:
    stdenv.mkDerivation {
      name = "xuantie-gnu-toolchain${suffix}";

      src = fetchFromGitHub {
        owner = "T-head-Semi";
        repo = "xuantie-gnu-toolchain";
        rev = "23fdf1028b63bb52ec0900f0021617e50c1f9af0";
        hash = "sha256-X3QppvOZ5T+npXfDnGJA1fzwjWQ4Dt3tcDUMqs7nsMY=";
      };

      hardeningDisable = [ "format" ];

      buildInputs = [ libmpc mpfr gmp libtool zlib expat ];
      nativeBuildInputs = [ gnugrep autoconf automake curl python3 gawk bison flex texinfo gperf bc patchutils file util-linux ];

      submodules = linkFarm "srcs" (with builtins; attrValues (mapAttrs (k: v: { name = k; path = (fetchFromGitHub v).outPath; }) submodules));

      prePatch = ''
        cp -Hr $submodules/* .
        chmod -R u+w .
      '';

      # https://github.com/riscv-collab/riscv-gnu-toolchain/issues/800#issuecomment-1155538932
      # https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/commit/00eff86c79ee4da65e24223d5251bc6135856d36
      patches = lib.optional stdenv.hostPlatform.isDarwin [ ../patches/gcc-11.3-on-darwin.patch ];

      configurePhase = ''
        patchShebangs .
        patchShebangs riscv-binutils/configure
        ./configure --prefix=$out ${configureArgs}

        if ! fgrep -q "NEED_GCC_EXTERNAL_LIBRARIES='false'" config.log; then
          echo "The Makefile would try to download additional dependencies. This would fail."
          exit 1
        fi
        # The Makefile will try to use it anyway if it exists so let's make sure that it doesn't.
        rm riscv-gcc/contrib/download_prerequisites
      '';

      buildPhase = ''
        make ${target} -j$NIX_BUILD_CORES
      '';

      dontMoveLib64 = true;
    };
  
  xuantie-gnu-toolchain-multilib-newlib = overrideArgs xuantie-gnu-toolchain {
    suffix = "-multilib-newlib";
    target = "newlib";
    configureArgs = "--enable-multilib";
  };

  xuantie-gnu-toolchain-multilib-linux = overrideArgs xuantie-gnu-toolchain {
    suffix = "-multilib-linux";
    target = "linux";
    configureArgs = "--enable-multilib";
  };
}
