# Forgejo — selbst gehostete Git-Forge unter git.hl.sk4i.com.
#
# Läuft auf hl03, weil dort der Postgres-Cluster aus litellm.nix schon steht:
# Forgejo geht per Unix-Socket mit `peer`-Auth rein und braucht damit weder
# DB-Passwort noch sops-Secret. Als Nebeneffekt landet die Datenbank
# automatisch im Backup — der hl03-Prepare-Schritt in homelab-backup.nix macht
# `pg_dumpall` über den ganzen Cluster.
#
# Der Dateibaum liegt unter /srv/forgejo auf der Datenpartition, nicht auf der
# System-SSD; Repos wachsen. Ein eigener Forgejo-Dump (`dump.enable`) bleibt
# aus: restic sichert den Baum, pg_dumpall die DB.
#
# Git über SSH nutzt bewusst den vorhandenen Host-sshd auf Port 22 statt des
# eingebauten Servers — der müsste auf einen hohen Port, weil dem Unit
# `CapabilityBoundingSet = ""` jedes CAP_NET_BIND_SERVICE nimmt. Forgejo pflegt
# dafür selbst `.ssh/authorized_keys` im Home des `forgejo`-Users (= stateDir).
{
  config,
  pkgs,
  ...
}: let
  proxyAddress = "10.20.50.12";
  lanAddress = "10.20.50.13";
  appPort = 3000;
  domain = "git.hl.sk4i.com";

  adminUser = "ecomex";
  adminEmail = "s.koch@bechtle.com";
  stateDir = "/srv/forgejo";
in {
  services.forgejo = {
    enable = true;
    package = pkgs.forgejo;
    inherit stateDir;
    lfs.enable = true;

    database = {
      type = "postgres";
      # `local all all peer` kommt aus litellm.nix; createDatabase hängt
      # `forgejo` an ensureDatabases/ensureUsers an und merged mit dessen Listen.
      socket = "/run/postgresql";
      createDatabase = true;
    };

    settings = {
      server = {
        DOMAIN = domain;
        ROOT_URL = "https://${domain}/";
        # LAN-IP statt 0.0.0.0: tailscale0 ist trustedInterface, ein
        # Wildcard-Bind wäre im ganzen Tailnet offen.
        HTTP_ADDR = lanAddress;
        HTTP_PORT = appPort;
        # hl03.hl.sk4i.com zeigt außerhalb der Hosts über den Wildcard auf
        # Traefik, taugt also nicht als SSH-Ziel — daher die IP.
        START_SSH_SERVER = false;
        SSH_DOMAIN = lanAddress;
        SSH_PORT = 22;
        LANDING_PAGE = "explore";
        # Keine Assets und Avatare von fremden CDNs nachladen.
        OFFLINE_MODE = true;
      };

      security = {
        # Traefik terminiert TLS; nur ihm darf X-Forwarded-For geglaubt werden.
        REVERSE_PROXY_TRUSTED_PROXIES = proxyAddress;
        REVERSE_PROXY_LIMIT = 1;
      };

      # Einzelnutzer-Forge: das Admin-Konto wird einmalig per CLI angelegt
      # (`forgejo admin user create`), danach ist hier zu.
      service.DISABLE_REGISTRATION = true;
      session.COOKIE_SECURE = true;

      repository = {
        DEFAULT_BRANCH = "main";
        DEFAULT_PRIVATE = "private";
      };

      # Kein Runner vorhanden — sonst hängen in der UI überall tote
      # Actions-Tabs.
      actions.ENABLED = false;

      ui.DEFAULT_THEME = "forgejo-dark";
      log.LEVEL = "Info";
    };
  };

  # hl03 hat 8 GiB und teilt sie mit Nextcloud, MariaDB, Postgres und LiteLLM.
  systemd.services.forgejo.serviceConfig = {
    MemoryHigh = "768M";
    MemoryMax = "1G";
  };

  # Das nixpkgs-Modul kennt keine Option für das Admin-Konto, also legt es
  # dieser idempotente oneshot an. Damit ist das Konto reproduzierbar und das
  # Passwort liegt verschlüsselt im Repo statt nur im Kopf.
  #
  # ACHTUNG, bewusst akzeptierter Kompromiss: Forgejos CLI nimmt das Passwort
  # ausschließlich über `--password` in argv — es gibt keine Datei-, stdin-
  # oder Env-Variante. Für die Laufzeit des Aufrufs steht der Klartext also in
  # /proc/<pid>/cmdline, und das ist unter Linux per Default für jeden lokalen
  # Nutzer lesbar. Eine Kommandosubstitution ändert daran nichts. Auf hl03 ist
  # der einzige interaktive Nutzer ecomex, der ohnehin per sudo an das Secret
  # kommt; das Fenster ist einige Millisekunden bei Aktivierung bzw. Rotation.
  sops.secrets.forgejo_admin_password = {
    mode = "0400";
    restartUnits = ["forgejo-admin.service"];
  };

  systemd.services.forgejo-admin = {
    description = "Provision the Forgejo admin account";
    after = ["forgejo.service"];
    requires = ["forgejo.service"];
    wantedBy = ["multi-user.target"];

    # forgejo.service ist Type=notify, nach `after` ist die DB also migriert.
    environment = {
      GITEA_WORK_DIR = stateDir;
      GITEA_CUSTOM = config.services.forgejo.customDir;
    };

    serviceConfig = {
      Type = "oneshot";
      User = "forgejo";
      Group = "forgejo";
      RemainAfterExit = true;
      # systemd liest das Secret als root und legt es unter
      # $CREDENTIALS_DIRECTORY nur für diesen Unit ab.
      LoadCredential = "password:${config.sops.secrets.forgejo_admin_password.path}";
    };

    script = let
      forgejo = "${config.services.forgejo.package}/bin/forgejo";
      appIni = "${config.services.forgejo.customDir}/conf/app.ini";
    in ''
      set -euo pipefail
      password="$(${pkgs.coreutils}/bin/tr -d '\n' < "$CREDENTIALS_DIRECTORY/password")"

      # Spalte 2 der Tabelle ist der Username; Kopfzeile überspringen. Kein
      # `|| true` — ein echter Fehler soll den Unit scheitern lassen und nicht
      # als "User existiert schon" durchgehen.
      if ${forgejo} --config ${appIni} admin user list \
        | ${pkgs.gawk}/bin/awk 'NR > 1 { print $2 }' \
        | ${pkgs.gnugrep}/bin/grep --quiet --line-regexp ${adminUser}; then
        # Rotation: ein geändertes sops-Secret restartet diesen Unit.
        ${forgejo} --config ${appIni} admin user change-password \
          --username ${adminUser} \
          --password "$password" \
          --must-change-password=false
      else
        # `--must-change-password=false` muss mit `=` geschrieben werden,
        # sonst frisst das Flag das nächste Argument (Forgejo-Issue #3399).
        ${forgejo} --config ${appIni} admin user create \
          --admin \
          --username ${adminUser} \
          --email ${adminEmail} \
          --password "$password" \
          --must-change-password=false
      fi
    '';
  };

  # Wie bei haushaltsbuch.nix eine quell-beschränkte Regel statt
  # `interfaces.lan0.allowedTCPPorts`: eine Forge gibt Quellcode und
  # Access-Tokens preis, das muss nicht das ganze LAN erreichen können. Port 22
  # für Git über SSH ist davon unabhängig und bleibt über services.openssh offen.
  networking.firewall = {
    extraCommands = ''
      iptables -A nixos-fw -i lan0 -p tcp \
        -s ${proxyAddress}/32 --dport ${toString appPort} -j nixos-fw-accept
    '';
    extraStopCommands = ''
      iptables -D nixos-fw -i lan0 -p tcp \
        -s ${proxyAddress}/32 --dport ${toString appPort} -j nixos-fw-accept \
        || true
    '';
  };
}
