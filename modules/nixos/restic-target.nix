{
  config,
  pkgs,
  ...
}: let
  repositoryRoot = "/srv/backup/restic";
  lockDirectory = "/run/lock/homelab-restic-target";
  lockFile = "${lockDirectory}/lock";
  repositoryPasswordCredential = "restic-repository-password";
  repairRepositoryOwnership = pkgs.writeShellScript "repair-restic-repository-ownership" ''
    set -Eeuo pipefail
    ${pkgs.util-linux}/bin/mountpoint --quiet /srv/backup
    ${pkgs.findutils}/bin/find ${repositoryRoot} -xdev \
      \( ! -user restic -o ! -group restic \) \
      -exec ${pkgs.coreutils}/bin/chown --no-dereference restic:restic {} +
  '';
in {
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
    dataDir = repositoryRoot;
    appendOnly = true;
    privateRepos = true;
    htpasswd-file = config.sops.secrets.homelab_restic_server_htpasswd.path;
  };

  # Never let the server silently write backups to the root filesystem when
  # the preserved EXCERIA filesystem is absent.
  systemd.services.restic-target-prepare = {
    description = "Prepare the Restic directory on the EXCERIA filesystem";
    # `nofail` lets hl03 boot without the USB disk, but this preparation must
    # never race the mount when the disk is present.
    after = ["srv-backup.mount"];
    before = ["restic-rest-server.service"];
    unitConfig.RequiresMountsFor = "/srv/backup";
    serviceConfig.Type = "oneshot";
    script = ''
      ${pkgs.util-linux}/bin/mountpoint --quiet /srv/backup
      ${pkgs.coreutils}/bin/install \
        -d -o restic -g restic -m 0750 ${repositoryRoot}
      ${pkgs.coreutils}/bin/install \
        -d -o restic -g restic -m 0750 ${lockDirectory}
    '';
  };

  # Restic creates rewritten index files as the user running `prune`. Repair
  # files left behind by the former root-run maintenance job before exposing
  # the repositories through rest-server.
  systemd.services.restic-target-permissions = {
    description = "Normalize ownership of the homelab Restic repositories";
    after = ["restic-target-prepare.service"];
    requires = ["restic-target-prepare.service"];
    before = ["restic-rest-server.service"];
    unitConfig.RequiresMountsFor = "/srv/backup";
    serviceConfig.Type = "oneshot";
    script = ''
      exec ${repairRepositoryOwnership}
    '';
  };

  systemd.services.restic-rest-server = {
    after = ["restic-target-permissions.service"];
    requires = ["restic-target-permissions.service"];
    unitConfig.RequiresMountsFor = "/srv/backup";
  };

  systemd.tmpfiles.rules = [
    "d ${lockDirectory} 0750 restic restic -"
    "f ${lockFile} 0600 restic restic -"
  ];

  systemd.services.restic-maintenance = {
    description = "Prune and verify the homelab Restic repositories";
    after = ["restic-target-permissions.service"];
    requires = ["restic-target-permissions.service"];
    unitConfig.RequiresMountsFor = "/srv/backup";
    serviceConfig = {
      Type = "oneshot";
      User = "restic";
      Group = "restic";
      LoadCredential = [
        "${repositoryPasswordCredential}:${config.sops.secrets.homelab_restic_repository_password.path}"
      ];
      Nice = 10;
      IOSchedulingClass = "idle";
      CPUWeight = 20;
      IOWeight = 20;
    };
    script = ''
      set -Eeuo pipefail
      export RESTIC_PASSWORD_FILE="$CREDENTIALS_DIRECTORY/${repositoryPasswordCredential}"

      exec 9>${lockFile}
      ${pkgs.util-linux}/bin/flock --exclusive 9

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
    after = ["restic-target-permissions.service"];
    requires = ["restic-target-permissions.service"];
    unitConfig.RequiresMountsFor = "/srv/backup";
    serviceConfig = {
      Type = "oneshot";
      User = "restic";
      Group = "restic";
      LoadCredential = [
        "${repositoryPasswordCredential}:${config.sops.secrets.homelab_restic_repository_password.path}"
      ];
      Nice = 15;
      IOSchedulingClass = "idle";
      CPUWeight = 10;
      IOWeight = 10;
    };
    script = ''
      set -Eeuo pipefail
      export RESTIC_PASSWORD_FILE="$CREDENTIALS_DIRECTORY/${repositoryPasswordCredential}"

      exec 9>${lockFile}
      ${pkgs.util-linux}/bin/flock --exclusive 9

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

  # Temporary end-to-end verification for the repository ownership repair.
  # Remove after maintenance and the following REST backup have succeeded.
  systemd.services.restic-ownership-recovery-check = {
    description = "Verify Restic maintenance and client access after ownership repair";
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "infinity";
    };
    script = ''
      ${pkgs.systemd}/bin/systemctl reset-failed \
        restic-maintenance.service \
        restic-backups-hl03.service
      ${pkgs.systemd}/bin/systemctl start restic-maintenance.service
      ${pkgs.systemd}/bin/systemctl start restic-backups-hl03.service
    '';
  };

  networking.firewall.interfaces.lan0.allowedTCPPorts = [8000];
}
