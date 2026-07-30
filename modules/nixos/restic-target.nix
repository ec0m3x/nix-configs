{
  config,
  pkgs,
  ...
}: {
  sops.secrets = {
    # Repository encryption and HTTP credentials are also needed by the
    # client jobs added in Phase 4.
    restic_password = {};
    restic_server_password = {};
    restic_server_htpasswd = {
      owner = "restic";
      group = "restic";
      mode = "0400";
      restartUnits = ["restic-rest-server.service"];
    };
  };

  services.restic.server = {
    enable = true;
    listenAddress = "10.20.50.13:8000";
    dataDir = "/srv/backup/restic";
    appendOnly = true;
    htpasswd-file = config.sops.secrets.restic_server_htpasswd.path;
  };

  # Never let the server silently write backups to the root filesystem when
  # the preserved EXCERIA filesystem is absent.
  systemd.services.restic-target-prepare = {
    description = "Prepare the Restic directory on the EXCERIA filesystem";
    before = ["restic-rest-server.service"];
    serviceConfig.Type = "oneshot";
    script = ''
      ${pkgs.util-linux}/bin/mountpoint --quiet /srv/backup
      ${pkgs.coreutils}/bin/install \
        -d -o restic -g restic -m 0750 /srv/backup/restic
    '';
  };
  systemd.services.restic-rest-server = {
    after = ["restic-target-prepare.service"];
    requires = ["restic-target-prepare.service"];
    unitConfig.RequiresMountsFor = "/srv/backup";
  };

  networking.firewall.interfaces.lan0.allowedTCPPorts = [8000];
}
