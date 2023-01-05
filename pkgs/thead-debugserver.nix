{
  thead-debugserver = { stdenv, fetchzip, autoPatchelfHook, libusb, libstdcxx5, bash }:
  stdenv.mkDerivation {
    name = "thead-debugserver";

    src = fetchzip {
      url = "https://dl.sipeed.com/fileList/MAIX/M1s/M1s_Dock/9_Driver/cklink/T-Head-DebugServer-linux-x86_64-V5.16.5-20221021.sh.tar.gz";
      hash = "sha256-IjDf0ynPegwpFukMbPrR54eBK3BjNDRN6ZBKV/I1g84=";
    };

    nativeBuildInputs = [ autoPatchelfHook ];
    buildInputs = [ libusb libstdcxx5 ];

    # The download is an interactive shell script that doesn't seem to have any provisions
    # for batch processing. No thanks. That way, we will also avoid sudo and 777+suid permissions.
    unpackPhase = ''
      tail -n+282 $src/*.sh | tar -xz
      cd T-HEAD_DebugServer
    '';

    buildPhase = ''
      #FIXME The original script is setting +x and +s on many .elf and .so files. Do we really need suid anywhere?
      chmod +x DebugServerConsole.elf
      find -name "*.so" -exec chmod -x {} \+
    '';

    installPhase = ''
      mkdir -p $out/share $out/bin
      cp -r . $out/share/thead-debugserver

      #ln $out/share/thead-debugserver/DebugServerConsole.elf $out/bin/DebugServerConsole
      # -> would look for further files in the wrong place (and then segfault)
      ( echo "#! ${bash}/bin/bash"; echo "exec $out/share/thead-debugserver/DebugServerConsole.elf \"\$@\"" ) \
        >$out/bin/DebugServerConsole
      chmod +x $out/bin/DebugServerConsole

      #patchelf --rpath $out/share/thead-debugserver $out/share/thead-debugserver/DebugServerConsole.elf
      extraAutoPatchelfLibs=($out/share/thead-debugserver)
    '';
  };
}
