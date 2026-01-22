{ config, pkgs, ... }:

{
  # 1. EDID dem System als Firmware "unterschieben"
  hardware.firmware = [
    (pkgs.runCommand "monitor-edid" {} ''
      mkdir -p $out/lib/firmware/edid
      cp ${./monitor.bin} $out/lib/firmware/edid/monitor.bin
    '')
  ];

  # 2. Kernel anweisen, diese EDID für den Dummy-Port zu nutzen
  # WICHTIG: Hier muss der Name stehen, den der Kernel verwendet (z.B. DP-1 statt card0-DP-1)
  boot.kernelParams = [
    "drm.edid_firmware=HDMI-A-1:edid/monitor.bin" 
    "video=HDMI-A-1:D"
  ];
}