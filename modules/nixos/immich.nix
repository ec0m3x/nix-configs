{pkgs, ...}: {
  services.immich = {
    enable = true;
    package = pkgs.unstable.immich;
    host = "10.20.50.11";
    port = 2283;
    # The restored database contains absolute paths below
    # /opt/immich/upload. Keep that logical path while storing the data on
    # the dedicated /srv SSD.
    mediaLocation = "/opt/immich/upload";
    settings.server.externalDomain = "https://photos.sk4i.com";
    machine-learning.environment = {
      MACHINE_LEARNING_WORKERS = "1";
      MACHINE_LEARNING_MODEL_TTL = "300";
    };
  };

  fileSystems."/opt/immich/upload" = {
    device = "/srv/immich/upload";
    fsType = "none";
    options = [
      "bind"
      "x-system.requires-mounts-for=/srv/immich/upload"
    ];
  };

  systemd.tmpfiles.rules = [
    "d /srv/immich 0700 immich immich -"
    "d /srv/immich/upload 0700 immich immich -"
  ];

  # Keep machine learning from displacing the other Phase-4 workloads.
  systemd.services.immich-machine-learning.serviceConfig = {
    MemoryHigh = "2G";
    MemoryMax = "3G";
  };

  networking.firewall.interfaces.lan0.allowedTCPPorts = [2283];
}
