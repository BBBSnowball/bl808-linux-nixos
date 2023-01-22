let
  ignoreForCallPackage = go: { outPath = "ignore for further callPackage"; inherit go; };

  # delete all prebuilt executables and libraries
  deblobify = drv: { runCommand, file, ... }: runCommand drv.name {
    inherit drv file;
    inherit (drv) pname version;
    passthru = {
      with-blobs = drv;
      inherit (drv) src;
    };

    okToKeep = ''
      /builtin_imgs/
      /chips/.*/eflash_loader/eflash_loader
      /bflb_iot_tool/img/
      /bflb_mcu_tool/img/
      [ ]text/\S+$
      [ ]application/x-bytecode.python$
      [ ]application/x-wine-extension-ini$
      [ ]application/json$
      [ ]inode/x-empty$
    '';
    passAsFile = [ "okToKeep" ];
  } ''
    cp -r $drv $out
    chmod -R u+w $out
    rm -rf $out/lib/python*/site-packages/*/utils/{cklink,genromfs,jlink,openocd/*.dll,openocd/*.exe}
    find $out -type f -exec file --mime-type {} \+ >remaining
    if grep -vEf $okToKeepPath <remaining || [ "$?" != "1" ] ; then
      echo "Some unknown files are remaining after we have removed known-blobs. See above."
      exit 1
    fi
  '';

  useChrootEnv = false;
in
{
  chrootenv = { nixpkgs, callPackage }: callPackage "${nixpkgs}/pkgs/build-support/build-fhs-userenv/chrootenv" {};

  bflb-flash-env = { buildFHSUserEnv }:
  buildFHSUserEnv {
    name = "flash-env";
    targetPkgs = pkgs: with pkgs;
      [
        zlib
      ];
    runScript = "bash";
  };

  init-env-for-flash-tools = { writeShellScript, bflb-flash-env, xorg, gnused, coreutils, lib, stdenv }:
  writeShellScript "init-env-for-flash-tools" (lib.optionalString useChrootEnv ''
    for i in ${bflb-flash-env}/* /host/*; do
      path="/''${i##*/}"
      [ -e "$path" ] || ${coreutils}/bin/ln -s "$i" "$path"
    done
  '' + ''
    set -e

    # create a writable copy of the Python package in /tmp because it will be
    # writing temporary files into its tree
    pkg="$1"
    cmd="$2"
    shift
    shift
    pkgtmp=$(${coreutils}/bin/mktemp -td bflb-tmp.XXXXXXXX)
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
      ${if stdenv.hostPlatform.isDarwin
        then "$pkgtmp/$cmd" "$@"
        else ''strace -o "$pkgtmp/strace" -- "$pkgtmp/$cmd" "$@"''}
      x=$?
      #rm -r "$pkgtmp"  # don't delete in debug mode
      exit $x
    else
      "$pkgtmp/$cmd" "$@"
      x=$?
      rm -r "$pkgtmp"
      exit $x
    fi
  '');

  #NOTE We should use packageOverrides here but this is not so easy with the current structure of this flake.
  # see https://nixos.wiki/wiki/Overlays#Python_Packages_Overlay
  bflb-crypto-plus = { python3Packages }: python3Packages.buildPythonPackage rec {
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
  pycklink = { python3Packages }: python3Packages.buildPythonPackage rec {
    pname = "pycklink";
    version = "0.1.1";
    src = python3Packages.fetchPypi {
      inherit pname version;
      hash = "sha256-Ub3a72V15Fkeyo7RkbjMaj6faUrcC8RkRRSbNUuq/ks=";
    };
  };
  portalocker_2_0 = { python3Packages }: with python3Packages; buildPythonPackage rec {
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

  bflb-common = { python3Packages, bash, init-env-for-flash-tools,
  #chrootenv,
  bflb-crypto-plus, pycklink, portalocker_2_0 }: ignoreForCallPackage ({ pname, ... }@args: python3Packages.buildPythonApplication (args // {
    # This doesn't seem to work for us.
    nativeBuildInputs = [ python3Packages.pythonRelaxDepsHook ];
    pythonRelaxDeps = [ "pycryptodome" "pylink-square" "portalocker" ];
    #NIX_DEBUG = 1;

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

    #postInstall = (args.postInstall or "") + ''
    #  mv $out/bin/${pname} $out/bin/.${pname}.unwrapped
    #  ( echo "#! ${bash}/bin/bash"; echo "${chrootenv}/bin/chrootenv ${init-env-for-flash-tools} $out bin/.${pname}.unwrapped \"\$(pwd)\" \"\$@\"" ) >$out/bin/${pname}
    #  chmod +x $out/bin/${pname}
    #'';
    postInstall = (args.postInstall or "") + ''
      mv $out/bin/${pname} $out/bin/.${pname}.unwrapped
      ( echo "#! ${bash}/bin/bash"; echo "${bash}/bin/bash ${init-env-for-flash-tools} $out bin/.${pname}.unwrapped \"\$(pwd)\" \"\$@\"" ) >$out/bin/${pname}
      chmod +x $out/bin/${pname}
    '';
  }));
  bflb-mcu-tool-with-blobs = { python3Packages, bflb-common }: bflb-common.go rec {
    pname = "bflb-mcu-tool";
    version = "1.8.1";
    src = python3Packages.fetchPypi {
      inherit pname version;
      hash = "sha256-bY5z6bXV2BAd38kjCHCfFd8H+ZXIFFfs0EC+i4mxG4s=";
    };

    patches = [
      ../patches/bflb-mcu-tool--fix-eflash-exitcode.patch
    ];
  };
  bflb-iot-tool-with-blobs = { python3Packages, bflb-common }: bflb-common.go rec {
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

    patches = [
      ../patches/bflb-iot-tool--logfile-from-environ.patch
      ../patches/bflb-iot-tool--fix-eflash-exitcode.patch
    ];
  };

  bflb-mcu-tool = { bflb-mcu-tool-with-blobs, runCommand, file }@args: deblobify bflb-mcu-tool-with-blobs args;
  bflb-iot-tool = { bflb-iot-tool-with-blobs, runCommand, file }@args: deblobify bflb-iot-tool-with-blobs args;
}
