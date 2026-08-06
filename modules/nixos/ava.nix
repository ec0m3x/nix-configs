# Ava — Hermes Agent (Nous Research), der Kategorisierungs-Agent des
# Haushaltsbuchs.
#
# Anders als beim Haushaltsbuch ist das Image hier fremder Code mit eigenem
# Releasezyklus, deshalb das offizielle Image von Docker Hub statt eines
# selbstgebauten. Gepinnt wird eine Release-Version, nicht `latest` — das
# zeigt bei diesem Projekt auf den jeweils aktuellen main-Build.
#
# Der Agent verwaltet seinen kompletten Zustand selbst unter /opt/data
# (Config, .env, Skills, Memories, Sessions). Das ist bewusst ein Volume und
# nicht deklarativ: Hermes schreibt sich im Betrieb eigene Skills, ein
# unveränderliches Installat würde gegen sein Design arbeiten. Die
# Erstkonfiguration läuft einmalig über den interaktiven Setup-Wizard.
#
# Update: `scripts/bump-ava.sh` pinnt den neuesten Release-Tag von Docker Hub
# — GitOps rollt danach aus.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # v2026.8.3
  avaImage = "docker.io/nousresearch/hermes-agent@sha256:16788311e2fa3035456bdc1bafb8ec2b1777db64ebf020af9bb7eb73c3712c9e";

  # OpenAI-kompatibler Endpoint. Das Haushaltsbuch läuft auf demselben Host
  # ebenfalls mit --network=host und spricht ihn über Loopback an; der Server
  # bindet deshalb auf 127.0.0.1 und 8642 wird nicht in der Firewall geöffnet.
  apiPort = 8642;

  # Das Web-Dashboard läuft im selben Container: das Image hat dafür einen
  # s6-Service-Slot, der bei HERMES_DASHBOARD=1 neben dem `gateway run`-CMD
  # hochkommt. Ein zweiter Container wäre ein zweiter Gateway-Prozess auf
  # demselben /opt/data — vom Upstream nicht vorgesehen.
  dashboardPort = 9119;

  # Gebunden wird auf 0.0.0.0 statt wie sonst im Homelab auf die LAN-IP. Das
  # Dashboard prüft den Host-Header gegen die Bind-Adresse (DNS-Rebinding,
  # GHSA-ppp5-vxwm-4cf7): bei einem Bind auf 10.20.50.11 muss der Host-Header
  # exakt "10.20.50.11" lauten, Traefik schickt aber ava.hl.sk4i.com — das
  # gäbe 400. Nur 0.0.0.0 akzeptiert beliebige Host-Header.
  #
  # Ungeschützt ist das trotzdem nicht: jeder Nicht-Loopback-Bind aktiviert
  # den Auth-Gate, und ohne registrierten Provider startet der Server gar
  # nicht ("Refusing to bind dashboard"). Deshalb unten Username + scrypt-Hash.
  dashboardHost = "0.0.0.0";
  proxyAddress = "10.20.50.12";

  # Hermes' "managed scope": /etc/hermes/config.yaml gewinnt gegen die
  # Agenten-eigene ~/.hermes/config.yaml und ist für CLI und Agent
  # schreibgeschützt. Gemerged wird blattweise, eine Teilmenge genügt also —
  # alles außer mcp_servers bleibt in Avas Hand.
  #
  # Der Token steht bewusst NICHT hier: das Nix-Store-File ist world-readable.
  # ${env:...} löst gegen die Prozess-Env auf, die aus sops kommt.
  managedConfig = (pkgs.formats.yaml {}).generate "hermes-managed-config.yaml" {
    mcp_servers.haushaltsbuch = {
      url = "https://hb.hl.sk4i.com/mcp/";
      headers.Authorization = "Bearer \${env:HB_MCP_TOKEN}";
      enabled = true;
      timeout = 180;
    };
  };
in {
  sops.secrets.ava_environment = {
    mode = "0400";
    restartUnits = ["podman-ava.service"];
  };

  # Zugangsdaten des Dashboards. Der Hash ist ein scrypt-String im Format
  # `scrypt$n$r$p$salt_b64$dk_b64`; Klartext gehört nicht hierher, weil eine
  # gesetzte HERMES_DASHBOARD_BASIC_AUTH_PASSWORD den Hash überstimmen würde.
  sops.secrets.ava_dashboard_password_hash = {
    mode = "0400";
    restartUnits = ["podman-ava.service"];
  };

  # Signaturschlüssel der Session-Tokens. Ohne ihn würfelt Hermes pro
  # Prozessstart einen neuen aus — jeder Container-Neustart loggt dann alle aus.
  sops.secrets.ava_dashboard_session_secret = {
    mode = "0400";
    restartUnits = ["podman-ava.service"];
  };

  # Die Zugangsdaten der Modell-Anbieter schreibt der Setup-Wizard nach
  # /opt/data/.env. Hier steht nur, was beide Container teilen müssen:
  # der Schlüssel, mit dem das Haushaltsbuch den Trigger absetzt.
  sops.templates.ava_env = {
    mode = "0400";
    restartUnits = ["podman-ava.service"];
    content = ''
      ${config.sops.placeholder.ava_environment}
      API_SERVER_ENABLED=true
      API_SERVER_HOST=127.0.0.1
      API_SERVER_PORT=${toString apiPort}
      # Muss zu HERMES_MODEL in der Haushaltsbuch-Env passen — die App schickt
      # diesen Namen im Chat-Request. Ohne das gilt der Profilname.
      API_SERVER_MODEL_NAME=ava
      HERMES_DASHBOARD=1
      HERMES_DASHBOARD_HOST=${dashboardHost}
      HERMES_DASHBOARD_PORT=${toString dashboardPort}
      HERMES_DASHBOARD_BASIC_AUTH_USERNAME=ecomex
      HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH=${config.sops.placeholder.ava_dashboard_password_hash}
      HERMES_DASHBOARD_BASIC_AUTH_SECRET=${config.sops.placeholder.ava_dashboard_session_secret}
      TZ=Europe/Berlin
    '';
  };

  # uid/gid 10000 = Service-User `hermes` im offiziellen Image. 0700 wie vom
  # Setup-Wizard angelegt — hier liegen die Provider-Credentials.
  systemd.tmpfiles.rules = [
    "d /srv/ava 0700 10000 10000 -"
  ];

  virtualisation.podman = {
    enable = lib.mkDefault true;
    autoPrune.enable = lib.mkDefault true;
  };
  virtualisation.oci-containers = {
    backend = "podman";
    containers.ava = {
      image = avaImage;
      cmd = ["gateway" "run"];
      environmentFiles = [config.sops.templates.ava_env.path];
      volumes = [
        "/srv/ava:/opt/data:rw"
        "${managedConfig}:/etc/hermes/config.yaml:ro"
      ];
      extraOptions = [
        "--network=host"
        "--security-opt=no-new-privileges"
        # 3g statt 2g: seit HERMES_DASHBOARD=1 laufen uvicorn, die SPA und der
        # PTY-Chat zusätzlich im selben Container.
        "--memory=3g"
      ];
    };
  };

  # Im LAN darf nur Traefik an das Dashboard. Über das Tailnet ist der Port
  # erreichbar (tailscale0 ist trustedInterface) — dort schützt der Auth-Gate.
  networking.firewall = {
    extraCommands = ''
      iptables -A nixos-fw -i lan0 -p tcp \
        -s ${proxyAddress}/32 --dport ${toString dashboardPort} -j nixos-fw-accept
    '';
    extraStopCommands = ''
      iptables -D nixos-fw -i lan0 -p tcp \
        -s ${proxyAddress}/32 --dport ${toString dashboardPort} -j nixos-fw-accept \
        || true
    '';
  };
}
