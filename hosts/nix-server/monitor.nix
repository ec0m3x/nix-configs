{ config, pkgs, ... }:

{
  # 1. Inject EDID to the system as firmware
  hardware.firmware = [
    (pkgs.runCommand "monitor-edid" {} ''
      mkdir -p $out/lib/firmware/edid
      cp ${./monitor.bin} $out/lib/firmware/edid/monitor.bin
    '')
  ];

  # 2. Instruct kernel to use this EDID for the dummy port
  # IMPORTANT: Use the name that the kernel uses (e.g. DP-1 instead of card0-DP-1)
  boot.kernelParams = [
    "drm.edid_firmware=HDMI-A-1:edid/monitor.bin"
    "video=HDMI-A-1:D"
  ];
}