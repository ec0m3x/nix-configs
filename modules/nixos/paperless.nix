{
  lib,
  pkgs,
  ...
}: {
  assertions = [
    {
      assertion = pkgs.paperless-ngx.version == "2.20.15";
      message = "hl01 expects Paperless-ngx 2.20.15 for the Phase-4 restore";
    }
  ];

  services.paperless = {
    enable = true;
    package = pkgs.paperless-ngx;
    address = "10.20.50.11";
    port = 8000;
    dataDir = "/srv/paperless/data";
    mediaDir = "/srv/paperless/media";
    consumptionDir = "/srv/paperless/consume";
    database.createLocally = true;
    settings = {
      PAPERLESS_URL = "https://docs.hl.sk4i.com";
      PAPERLESS_OCR_LANGUAGE = "deu+eng";
    };
  };

  systemd.tmpfiles.rules = [
    "d /srv/paperless 0700 paperless paperless -"
  ];

  systemd.slices.system-paperless.sliceConfig = {
    MemoryHigh = "2G";
    MemoryMax = "3G";
  };

  networking.firewall.interfaces.lan0.allowedTCPPorts = [8000];
}
