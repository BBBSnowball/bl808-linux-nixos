{
  bl808-regs-py = { runCommand, tcl, fetchFromGitHub, xuantie-gnu-toolchain-multilib-linux }:
  runCommand "bl808-regs-py" {
    inherit tcl;
    bl_mcu_sdk = fetchFromGitHub {
      owner = "bouffalolab";
      repo = "bl_mcu_sdk";
      rev = "9e189b69cbc0a75ffa170f600a28820848d56432";
      hash = "sha256-nkPhJFtgd1IsX/REYN8TEs35TDF62CjfIuTlQuSyc2A=";
    };
  } ''
    export PATH=$PATH:${xuantie-gnu-toolchain-multilib-linux}/bin
    $tcl/bin/tclsh ${../parse_regs.tcl} $bl_mcu_sdk
    mkdir $out/usr/lib/micropython -p
    cp bl808_regs.py $out/usr/lib/micropython/
    cp bl808_consts.py $out/usr/lib/micropython/
    cp ${../reg_lib.py} $out/usr/lib/micropython/reg_lib.py
  '';
}
