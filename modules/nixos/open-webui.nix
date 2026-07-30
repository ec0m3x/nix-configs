{
  lib,
  pkgs,
  ...
}: {
  assertions = [
    {
      assertion = pkgs.unstable.open-webui.version == "0.10.2";
      message = "Update the documented Open WebUI migration decision when changing its native package";
    }
  ];

  services.open-webui = {
    enable = true;
    package = pkgs.unstable.open-webui;
    host = "10.20.50.11";
    port = 8080;
    environment = {
      SCARF_NO_ANALYTICS = "True";
      DO_NOT_TRACK = "True";
      ANONYMIZED_TELEMETRY = "False";
      OLLAMA_BASE_URL = "http://10.20.50.20:11434";
    };
  };

  # The source is newer than the native Nix package. Start with a fresh
  # state directory and retain the complete 0.11.0 source state externally.
  systemd.services.open-webui.serviceConfig = {
    MemoryHigh = "2G";
    MemoryMax = "3G";
  };

  networking.firewall.interfaces.lan0.allowedTCPPorts = [8080];
}
