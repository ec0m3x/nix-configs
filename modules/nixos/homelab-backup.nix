{
  config,
  lib,
  pkgs,
  ...
}: let
  hostName = config.networking.hostName;
  backupRoot = "/var/lib/homelab-backup";
  resticSecretFile = ../../secrets/restic.yaml;

  schedules = {
    hl01 = "02:15";
    hl02 = "03:15";
    hl03 = "04:15";
  };

  hostPaths = {
    hl01 = [
      "/srv/haushaltsbuch"
      "/srv/immich/upload"
      "/srv/paperless"
      "/var/lib/private/open-webui"
    ];
    hl02 = [
      "/var/backup/vaultwarden"
      "/var/lib/private/AdGuardHome"
      "/var/lib/private/stirling-pdf"
      "/var/lib/traefik"
    ];
    hl03 = [
      # Die Forgejo-Datenbank steckt bereits im pg_dumpall unten; hier geht es
      # um die Repos, LFS-Objekte und Avatare.
      "/srv/forgejo"
      "/srv/nextcloud"
    ];
  };

  hostExcludes = {
    hl01 = [
      "/var/lib/private/open-webui/hf_home"
      "/var/lib/private/open-webui/transformers_home"
    ];
    hl02 = [];
    hl03 = [
      # Uploads in Arbeit — im Snapshot wertlos.
      "/srv/forgejo/data/tmp"
    ];
  };

  prepareCommands = {
    hl01 = ''
      #!${pkgs.runtimeShell}
      set -Eeuo pipefail
      umask 077

      ${pkgs.coreutils}/bin/install -d -m 0711 ${backupRoot}
      ${pkgs.coreutils}/bin/install \
        -d -o postgres -g postgres -m 0700 ${backupRoot}/postgresql

      ${pkgs.coreutils}/bin/rm -f ${backupRoot}/postgresql/cluster.sql.new
      ${pkgs.util-linux}/bin/runuser -u postgres -- \
        ${config.services.postgresql.package}/bin/pg_dumpall \
          --clean \
          --if-exists \
          --file=${backupRoot}/postgresql/cluster.sql.new
      ${pkgs.coreutils}/bin/test -s ${backupRoot}/postgresql/cluster.sql.new
      ${pkgs.coreutils}/bin/mv \
        ${backupRoot}/postgresql/cluster.sql.new \
        ${backupRoot}/postgresql/cluster.sql
      ${pkgs.coreutils}/bin/chown root:root ${backupRoot}/postgresql/cluster.sql
      ${pkgs.coreutils}/bin/chmod 0600 ${backupRoot}/postgresql/cluster.sql

      # Konsistente SQLite-Kopie statt Datei-Snapshot des laufenden WAL.
      # Guard, weil die DB erst beim ersten Start des Containers entsteht —
      # ein Backup-Lauf davor darf nicht fehlschlagen.
      if [[ -s /srv/haushaltsbuch/haushaltsbuch.db ]]; then
        ${pkgs.coreutils}/bin/rm -f ${backupRoot}/haushaltsbuch.sqlite.new
        ${pkgs.sqlite}/bin/sqlite3 \
          /srv/haushaltsbuch/haushaltsbuch.db \
          ".backup '${backupRoot}/haushaltsbuch.sqlite.new'"
        ${pkgs.sqlite}/bin/sqlite3 \
          ${backupRoot}/haushaltsbuch.sqlite.new \
          "PRAGMA quick_check;" | ${pkgs.gnugrep}/bin/grep --quiet --line-regexp ok
        ${pkgs.coreutils}/bin/mv \
          ${backupRoot}/haushaltsbuch.sqlite.new \
          ${backupRoot}/haushaltsbuch.sqlite
      else
        ${pkgs.coreutils}/bin/rm -f ${backupRoot}/haushaltsbuch.sqlite
      fi

      if [[ -s /var/lib/private/open-webui/data/webui.db ]]; then
        ${pkgs.coreutils}/bin/rm -f ${backupRoot}/open-webui.sqlite.new
        ${pkgs.sqlite}/bin/sqlite3 \
          /var/lib/private/open-webui/data/webui.db \
          ".backup '${backupRoot}/open-webui.sqlite.new'"
        ${pkgs.sqlite}/bin/sqlite3 \
          ${backupRoot}/open-webui.sqlite.new \
          "PRAGMA quick_check;" | ${pkgs.gnugrep}/bin/grep --quiet --line-regexp ok
        ${pkgs.coreutils}/bin/mv \
          ${backupRoot}/open-webui.sqlite.new \
          ${backupRoot}/open-webui.sqlite
      else
        ${pkgs.coreutils}/bin/rm -f ${backupRoot}/open-webui.sqlite
      fi
    '';

    hl02 = ''
      #!${pkgs.runtimeShell}
      set -Eeuo pipefail

      ${pkgs.systemd}/bin/systemctl start --wait backup-vaultwarden.service
      ${pkgs.coreutils}/bin/test -s /var/backup/vaultwarden/db.sqlite3
      ${pkgs.sqlite}/bin/sqlite3 \
        /var/backup/vaultwarden/db.sqlite3 \
        "PRAGMA quick_check;" | ${pkgs.gnugrep}/bin/grep --quiet --line-regexp ok
    '';

    hl03 = ''
      #!${pkgs.runtimeShell}
      set -Eeuo pipefail
      umask 077

      if [[ "$(${config.services.nextcloud.occ}/bin/nextcloud-occ config:system:get maintenance 2>/dev/null || true)" != "true" ]]; then
        ${config.services.nextcloud.occ}/bin/nextcloud-occ maintenance:mode --on
        ${pkgs.coreutils}/bin/touch /run/homelab-backup-nextcloud-maintenance
      fi

      ${pkgs.coreutils}/bin/install -d -m 0711 ${backupRoot}
      ${pkgs.coreutils}/bin/install \
        -d -o postgres -g postgres -m 0700 ${backupRoot}/postgresql

      ${pkgs.coreutils}/bin/rm -f ${backupRoot}/mariadb.sql.new
      ${config.services.mysql.package}/bin/mariadb-dump \
        --all-databases \
        --single-transaction \
        --quick \
        --routines \
        --events \
        --result-file=${backupRoot}/mariadb.sql.new
      ${pkgs.coreutils}/bin/test -s ${backupRoot}/mariadb.sql.new
      ${pkgs.coreutils}/bin/mv \
        ${backupRoot}/mariadb.sql.new \
        ${backupRoot}/mariadb.sql
      ${pkgs.coreutils}/bin/chmod 0600 ${backupRoot}/mariadb.sql

      ${pkgs.coreutils}/bin/rm -f ${backupRoot}/postgresql/cluster.sql.new
      ${pkgs.util-linux}/bin/runuser -u postgres -- \
        ${config.services.postgresql.package}/bin/pg_dumpall \
          --clean \
          --if-exists \
          --file=${backupRoot}/postgresql/cluster.sql.new
      ${pkgs.coreutils}/bin/test -s ${backupRoot}/postgresql/cluster.sql.new
      ${pkgs.coreutils}/bin/mv \
        ${backupRoot}/postgresql/cluster.sql.new \
        ${backupRoot}/postgresql/cluster.sql
      ${pkgs.coreutils}/bin/chown root:root ${backupRoot}/postgresql/cluster.sql
      ${pkgs.coreutils}/bin/chmod 0600 ${backupRoot}/postgresql/cluster.sql
    '';
  };

  cleanupCommands = {
    hl01 = null;
    hl02 = null;
    hl03 = ''
      #!${pkgs.runtimeShell}
      set -Eeuo pipefail

      if [[ -e /run/homelab-backup-nextcloud-maintenance ]]; then
        ${config.services.nextcloud.occ}/bin/nextcloud-occ maintenance:mode --off
        ${pkgs.coreutils}/bin/rm -f /run/homelab-backup-nextcloud-maintenance
      fi
    '';
  };

  sourceMounts = {
    hl01 = ["/srv"];
    hl02 = [];
    hl03 = [
      "/srv"
      "/srv/backup"
    ];
  };
in {
  assertions = [
    {
      assertion = builtins.hasAttr hostName hostPaths;
      message = "homelab-backup only supports hl01, hl02 and hl03";
    }
  ];

  sops.secrets = {
    homelab_restic_repository_password = {
      sopsFile = resticSecretFile;
      mode = "0400";
    };
    homelab_restic_server_password = {
      sopsFile = resticSecretFile;
      mode = "0400";
    };
  };

  sops.templates.homelab_restic_environment = {
    mode = "0400";
    content = ''
      RESTIC_REST_USERNAME=restic
      RESTIC_REST_PASSWORD=${config.sops.placeholder.homelab_restic_server_password}
    '';
  };

  systemd.tmpfiles.rules = [
    "d ${backupRoot} 0711 root root -"
  ];

  services.restic.backups.${hostName} = {
    repository = "rest:http://10.20.50.13:8000/restic/${hostName}";
    passwordFile = config.sops.secrets.homelab_restic_repository_password.path;
    environmentFile = config.sops.templates.homelab_restic_environment.path;
    initialize = true;
    paths =
      [
        "/etc/nixos-secrets"
        "/etc/ssh"
        "/var/lib/tailscale"
        backupRoot
      ]
      ++ lib.attrByPath [hostName] [] hostPaths;
    exclude = lib.attrByPath [hostName] [] hostExcludes;
    extraBackupArgs = [
      "--host=${hostName}"
      "--tag=homelab"
      "--tag=${hostName}"
      "--one-file-system"
    ];
    timerConfig = {
      OnCalendar = "*-*-* ${lib.attrByPath [hostName] "03:00" schedules}:00";
      RandomizedDelaySec = "10m";
      Persistent = true;
      AccuracySec = "1m";
    };
    backupPrepareCommand = lib.attrByPath [hostName] null prepareCommands;
    backupCleanupCommand = lib.attrByPath [hostName] null cleanupCommands;
  };

  systemd.services."restic-backups-${hostName}" = {
    after = lib.optionals (hostName == "hl03") ["restic-rest-server.service"];
    requires = lib.optionals (hostName == "hl03") ["restic-rest-server.service"];
    unitConfig = lib.optionalAttrs (lib.attrByPath [hostName] [] sourceMounts != []) {
      RequiresMountsFor =
        lib.concatStringsSep " " (lib.attrByPath [hostName] [] sourceMounts);
    };
    serviceConfig = {
      Nice = 10;
      IOSchedulingClass = "idle";
      CPUWeight = 20;
      IOWeight = 20;
    };
  };
}
