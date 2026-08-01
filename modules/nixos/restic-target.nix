{
  config,
  pkgs,
  ...
}: {
  sops.secrets = {
    homelab_restic_server_htpasswd = {
      sopsFile = ../../secrets/restic.yaml;
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
    privateRepos = true;
    htpasswd-file = config.sops.secrets.homelab_restic_server_htpasswd.path;
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

  systemd.services.restic-maintenance = {
    description = "Prune and verify the homelab Restic repositories";
    after = ["srv-backup.mount"];
    unitConfig.RequiresMountsFor = "/srv/backup";
    serviceConfig = {
      Type = "oneshot";
      Nice = 10;
      IOSchedulingClass = "idle";
      CPUWeight = 20;
      IOWeight = 20;
    };
    script = ''
      set -Eeuo pipefail
      export RESTIC_PASSWORD_FILE=${config.sops.secrets.homelab_restic_repository_password.path}

      for host in hl01 hl02 hl03; do
        repository="/srv/backup/restic/restic/''${host}"
        [[ -f "''${repository}/config" ]] || continue
        export RESTIC_REPOSITORY="''${repository}"
        ${pkgs.restic}/bin/restic unlock
        ${pkgs.restic}/bin/restic forget \
          --prune \
          --keep-daily 7 \
          --keep-weekly 5 \
          --keep-monthly 6
        ${pkgs.restic}/bin/restic check --read-data-subset=10%
      done
    '';
  };

  systemd.timers.restic-maintenance = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "Sun *-*-* 06:00:00";
      Persistent = true;
      AccuracySec = "5m";
    };
  };

  systemd.services.restic-full-check = {
    description = "Read and verify all homelab Restic repository data";
    after = ["srv-backup.mount"];
    unitConfig.RequiresMountsFor = "/srv/backup";
    serviceConfig = {
      Type = "oneshot";
      Nice = 15;
      IOSchedulingClass = "idle";
      CPUWeight = 10;
      IOWeight = 10;
    };
    script = ''
      set -Eeuo pipefail
      export RESTIC_PASSWORD_FILE=${config.sops.secrets.homelab_restic_repository_password.path}

      for host in hl01 hl02 hl03; do
        repository="/srv/backup/restic/restic/''${host}"
        [[ -f "''${repository}/config" ]] || continue
        export RESTIC_REPOSITORY="''${repository}"
        ${pkgs.restic}/bin/restic check --read-data
      done
    '';
  };

  systemd.timers.restic-full-check = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "Sun *-*-01..07 08:00:00";
      Persistent = true;
      AccuracySec = "5m";
    };
  };

  networking.firewall.interfaces.lan0.allowedTCPPorts = [8000];
}
