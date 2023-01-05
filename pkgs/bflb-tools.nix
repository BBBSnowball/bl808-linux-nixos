{ nixpkgs ? <nixpkgs>, callPackage, python3Packages, gnused, buildFHSUserEnv, writeShellScript, coreutils, xorg, bash }:
rec {
  chrootenv = callPackage "${nixpkgs}/pkgs/build-support/build-fhs-userenv/chrootenv" {};

  bflb-flash-env = (buildFHSUserEnv {
    name = "flash-env";
    targetPkgs = pkgs: with pkgs;
      [
        zlib
      ];
    runScript = "bash";
  });

  init-env-for-flash-tools = writeShellScript "init-env-for-flash-tools" ''
    for i in ${bflb-flash-env}/* /host/*; do
      path="/''${i##*/}"
      [ -e "$path" ] || ${coreutils}/bin/ln -s "$i" "$path"
    done

    set -e

    # create a writable copy of the Python package in /tmp because it will be
    # writing temporary files into its tree
    pkg="$1"
    cmd="$2"
    shift
    shift
    pkgtmp=$(mktemp -td bflb-tmp.XXXXXXXX)
    #cp -r "$pkg"/* "$pkgtmp"
    ${xorg.lndir}/bin/lndir -silent "$pkg" "$pkgtmp"
    chmod -R u+w "$pkgtmp/"
    for x in "$pkgtmp/bin"/.*[a-z]* ; do
      ${gnused}/bin/sed -i "s?$pkg?$pkgtmp?g" "$x"

      # sed has replaced the link by a read-only file from the store
      # and `rm` doesn't like to remove read-only files (and we avoid
      # passing `-f` if possible)
      chmod +w "$x"
    done

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

  bflb-crypto-plus = python3Packages.buildPythonPackage rec {
    pname = "bflb-crypto-plus";
    version = "1.0";
    src = python3Packages.fetchPypi {
      pname = "bflb_crypto_plus";
      inherit version;
      hash = "sha256-sbSDh05dLstJ+fhSWXFa2Ut2+WJ7Pen6Z39spc5mYkI=";
    };
    propagatedBuildInputs = with python3Packages; [
      ecdsa pycryptodome setuptools
    ];
  };
  pycklink = python3Packages.buildPythonPackage rec {
    pname = "pycklink";
    version = "0.1.1";
    src = python3Packages.fetchPypi {
      inherit pname version;
      hash = "sha256-Ub3a72V15Fkeyo7RkbjMaj6faUrcC8RkRRSbNUuq/ks=";
    };
  };
  portalocker_2_0 = with python3Packages; buildPythonPackage rec {
    pname = "portalocker";
    version = "2.0.0";
    format = "setuptools";
  
    src = fetchPypi {
      inherit pname version;
      hash = "sha256-FEh+7YGqkUEn7fAoTinHyohCwFuzPZbcfkvbRygtJuQ=";
    };
  
    propagatedBuildInputs = [
      redis
    ];

    doCheck = false;
  };
  bflb-common = { pname, ... }@args: python3Packages.buildPythonApplication (args // {
    # This doesn't seem to work for us.
    nativeBuildInputs = [ python3Packages.pythonRelaxDepsHook ];
    pythonRelaxDeps = [ "pycryptodome" "pylink-square" "portalocker" ];
    #NIX_DEBUG = 1;

    #patches = [ ../patches/bflb_mcu_tool.patch ];

    prePatch = ''
      for x in setup.py *.egg-info/requires.txt ; do
        sed -i 's/\(portalocker\|pylink-square\|pycryptodome\)=[=0-9.]*/\1/' "$x"
      done
    '';

    propagatedBuildInputs = with python3Packages; [
      ecdsa pycryptodome bflb-crypto-plus pycklink pyserial pylink-square portalocker
    ];

    # no need to fixup binaries because they are prebuilt but we need fixup for the startup script
    #dontFixup = true;

    postInstall = (args.postInstall or "") + ''
      mv $out/bin/${pname} $out/bin/.${pname}.unwrapped
      ( echo "#! ${bash}/bin/bash"; echo "${chrootenv}/bin/chrootenv ${init-env-for-flash-tools} $out bin/.${pname}.unwrapped \"\$(pwd)\" \"\$@\"" ) >$out/bin/${pname}
      chmod +x $out/bin/${pname}
    '';
  });
  bflb-mcu-tool = bflb-common rec {
    pname = "bflb-mcu-tool";
    version = "1.8.1";
    src = python3Packages.fetchPypi {
      inherit pname version;
      hash = "sha256-bY5z6bXV2BAd38kjCHCfFd8H+ZXIFFfs0EC+i4mxG4s=";
    };
  };
  bflb-iot-tool = bflb-common rec {
    pname = "bflb-iot-tool";
    version = "1.8.1";
    src = python3Packages.fetchPypi {
      inherit pname version;
      hash = "sha256-7kendLur1Fw0bhBJq14gM3fUG/y/K3IdWb5Jj2iP8cE=";
    };

    postPatch = ''
      echo 'entry_points["console_scripts"].append("bflb_eflash_loader = libs.bflb_eflash_loader:run")' >>setup.py
      #echo 'entry_points["console_scripts"].append("bflb_eflash_loader_client = libs.bflb_eflash_loader_client:...")' >>setup.py
      echo 'entry_points["console_scripts"].append("bflb_eflash_loader_server = libs.bflb_eflash_loader_server:eflash_loader_server_main")' >>setup.py
      echo 'entry_points["console_scripts"].append("bflb_efuse_boothd_create = libs.bflb_efuse_boothd_create:run")' >>setup.py
      echo 'entry_points["console_scripts"].append("bflb_img_create = libs.bflb_img_create:run")' >>setup.py
      #bflb_iot_tool/libs/bflb_img_loader.py:if __name__ == '__main__': -> TODO

      echo 'bflb_eflash_loader = libs.bflb_eflash_loader:run' >>bflb_iot_tool.egg-info/entry_points.txt
      echo 'bflb_eflash_loader_server = libs.bflb_eflash_loader_server:eflash_loader_server_main' >>bflb_iot_tool.egg-info/entry_points.txt
      echo 'bflb_efuse_boothd_create = libs.bflb_efuse_boothd_create:run' >>bflb_iot_tool.egg-info/entry_points.txt
      echo 'bflb_img_create = libs.bflb_img_create:run' >>bflb_iot_tool.egg-info/entry_points.txt
    '';

    postInstall = ''
      #ln -s $out/lib/python3.10/site-packages/bflb_iot_tool/libs/bflb_eflash_loader.py $out/bin/bflb_eflash_loader
      #chmod +x $out/lib/python3.10/site-packages/bflb_iot_tool/libs/bflb_eflash_loader.py
      ( echo "#! /usr/bin/python3"; echo "from bflb_iot_tool.libs.bflb_eflash_loader import run; run()" ) >>$out/bin/bflb_eflash_loader
      chmod +x $out/bin/bflb_eflash_loader
    '';

    patches = [ ../patches/bflb-iot-tool-1.8.1.patch ];
  };
}
