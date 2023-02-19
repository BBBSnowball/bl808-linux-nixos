{
  bl808-buildroot-flash-script = { python3, bflb-mcu-tool, bflb-iot-tool, writeShellScriptBin }:
  (writeShellScriptBin "flash-bl808-buildroot" ''
    if [ -z "$1" -o "$1" == "--help" ] ; then
      echo "Usage: $0 path/to/output/images --port ... --baudrate ..." >&2
      exit 1
    fi

    set -e

    files="$1"
    shift
    bflb_mcu_tool=${bflb-mcu-tool}/bin/bflb-mcu-tool
    bflb_iot_tool=${bflb-iot-tool}/bin/bflb-iot-tool
    flash_args=(--chipname bl808 --baudrate 2000000 --port /dev/ttyUSB1 "$@")

    ${python3}/bin/python3 ${../bl808-flash/merge_7_5Mbin.py} \
      --only-bootheader-group1 $files/d0_lowload_bl808_d0.bin \
      --out-bootheader-group1 $files/bootheader_group1.bin \
      --out-low-load-d0-padded $files/low_load_bl808_d0_padded.bin

    set -xe
    $bflb_mcu_tool "''${flash_args[@]}" --firmware $files/m0_lowload_bl808_m0.bin
    $bflb_iot_tool "''${flash_args[@]}" --addr 0x1000 --firmware $files/bootheader_group1.bin --single
    $bflb_iot_tool "''${flash_args[@]}" --addr 0x52000 --firmware $files/low_load_bl808_d0_padded.bin --single
    $bflb_iot_tool "''${flash_args[@]}" --addr 0xd2000 --firmware $files/pine64-ox64-firmware.bin --single

    : You can reset the board to boot into Linux. The console is on the first ttyUSB with 2 Mbaud.
    : ELF files with debug symbols are in: $files/
  '');
}
