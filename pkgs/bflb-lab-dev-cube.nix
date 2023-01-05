{
  bflb-lab-dev-cube = { buildFHSUserEnv, fetchzip, makeWrapper, chrootenv, coreutils, writeShellScript, stdenv, xorg }:
  let
    bflb-lab-dev-cube-env = buildFHSUserEnv {
      name = "bflb-lab-dev-cube-env";
      targetPkgs = pkgs: with pkgs;
        [ zlib
          ncurses5
          lz4
          libGL xorg.libxcb
          glibc
          xorg.libX11
        ];
      runScript = "bash";
      extraOutputsToInstall = [ "dev" ];
    };
  
    init-env-for-lab-dev-cube = writeShellScript "init-env-for-flash-tools" ''
      for i in ${bflb-lab-dev-cube-env}/* /host/*; do
        path="/''${i##*/}"
        [ -e "$path" ] || ${coreutils}/bin/ln -s "$i" "$path"
      done
  
      set -e
  
      # create a writable copy of the files in /tmp because it will be
      # writing temporary files into its tree
      pkg="$1"
      cmd="$2"
      shift
      shift
      pkgtmp=$(mktemp -td bflb-tmp.XXXXXXXX)
      ${xorg.lndir}/bin/lndir -silent "$pkg" "$pkgtmp"
      chmod -R u+w "$pkgtmp/"
  
      sed -bi "" "$pkgtmp/$cmd"
      chmod +w "$pkgtmp/$cmd"
  
      [ -d "$1" ] && [ -r "$1" ] && cd "$1"
      shift
  
      set +e
      source /etc/profile
      if [ -n "$DBG" ] ; then
        echo "DEBUG: pkgtmp=$pkgtmp"
        strace -o "$pkgtmp/strace" -- "$pkgtmp/$cmd" "$@"
        x=$?
        #rm -r "$pkgtmp"  # don't delete in debug mode
        exit $x
      else
        "$pkgtmp/$cmd" "$@"
        x=$?
        rm -r "$pkgtmp"
        exit $x
      fi
    '';
  in stdenv.mkDerivation rec {
    pname = "bflb-lab-dev-cube";
    version = src.version;

    src = fetchzip {
      url = "https://dev.bouffalolab.com/media/upload/download/BouffaloLabDevCube-v1.8.1.zip";
      stripRoot = false;
      hash = "sha256-qUlVusp+LeHayL0qXrSBZCCNUtOCC82wzNUcSfXRKOc=";
      passthru.version = "1.8.1";
    };

    dontUnpack = true;
    dontBuild = true;

    nativeBuildInputs = [ makeWrapper ];

    installPhase = ''
      mkdir -p $out/bin $out/share
      dist=$out/share/bflb-lab-dev-cube
      cp -r $src $dist
      chmod +x $dist/utils/genromfs/genromfs_*

      for x in bflb_iot_tool BLDevCube ; do
        target=''${x}-ubuntu
        chmod +x $dist/$target

        # We unset WAYLAND_DISPLAY in the wrapper because they bring their own Qt libraries
        # and they fail for Wayland.
        makeWrapper ${bflb-lab-dev-cube-env}/bin/bflb-lab-dev-cube-env $out/bin/$x \
          --add-flags "${init-env-for-lab-dev-cube} $dist $target \"\$(pwd)\"" \
          --unset WAYLAND_DISPLAY
      done
    '';
  };
}
