{pkgs, ...}: {
  services.open-webui = {
    enable = true;
    package = pkgs.open-webui;
    host = "10.20.50.11";
    port = 8080;
    environment = {
      SCARF_NO_ANALYTICS = "True";
      DO_NOT_TRACK = "True";
      ANONYMIZED_TELEMETRY = "False";
      OLLAMA_BASE_URL = "http://10.20.50.20:11434";
    };
  };

  systemd.services.open-webui.serviceConfig = {
    MemoryHigh = "2G";
    MemoryMax = "3G";
  };

  networking.firewall.interfaces.lan0.allowedTCPPorts = [8080];
}
