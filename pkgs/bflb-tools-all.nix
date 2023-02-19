{
  bflb-tools = { runCommand, bflb-mcu-tool, bflb-iot-tool, thead-debugserver, bflb-lab-dev-cube, stdenv, lib }:
  runCommand "bflb-tools" {} (''
    mkdir -p $out/bin
    ln -s ${bflb-mcu-tool}/bin/bflb-mcu-tool $out/bin/
    cp -s ${bflb-iot-tool}/bin/* $out/bin/
  '' + lib.optionalString (stdenv.hostPlatform.system == "x86_64-linux") ''
    ln -s ${thead-debugserver}/bin/DebugServerConsole $out/bin/
    cp -s ${bflb-lab-dev-cube}/bin/* $out/bin/
  '');
}
