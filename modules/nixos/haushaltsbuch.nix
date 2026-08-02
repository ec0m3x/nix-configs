# Haushaltsbuch — Dashboard + REST + MCP (web) und supercronic-Sidecar
# (scheduler) aus einem Image.
#
# Das Image baut die CI des App-Repos (ec0m3x/haushaltsbuch, Workflow
# `ci-image`) und pusht es nach GHCR. Hier wird bewusst ein Digest gepinnt,
# kein bewegliches Tag: ein Update ist damit ein sichtbarer, reviewbarer
# Commit in diesem Repo statt eines stillen Registry-Wechsels.
#
# Update-Ablauf:
#   1. Push auf main im App-Repo -> CI baut, Job-Summary zeigt den Digest.
#   2. Digest hier eintragen, committen, pushen.
#   3. GitOps-Controller auf nix-ai rollt hl01 aus.
{config, ...}: let
  # Tag ae59268 (App-Repo main, 2026-08-03).
  haushaltsbuchImage = "ghcr.io/ec0m3x/haushaltsbuch@sha256:45414a9db5c23c22d2c40f6d892e368279e46b661ce2fab7b3c859f28816feee";
  ghcrLogin = {
    registry = "ghcr.io";
    username = "ec0m3x";
    passwordFile = config.sops.secrets.ghcr_pull_token.path;
  };

  # Traefik auf hl02 ist der einzige legitime Client. Die Sparkassen-Zugänge
  # und der MCP-Token machen diesen Dienst empfindlicher als die übrigen
  # LAN-Backends, deshalb hier bewusst eine quell-beschränkte Regel statt des
  # sonst üblichen `interfaces.lan0.allowedTCPPorts`.
  proxyAddress = "10.20.50.12";
  appPort = 8787;
in {
  sops.secrets = {
    ghcr_pull_token = {
      mode = "0400";
      restartUnits = [
        "podman-haushaltsbuch-web.service"
        "podman-haushaltsbuch-scheduler.service"
      ];
    };
    haushaltsbuch_environment = {
      mode = "0400";
      restartUnits = [
        "podman-haushaltsbuch-web.service"
        "podman-haushaltsbuch-scheduler.service"
      ];
    };
  };

  # Der verschlüsselte Teil enthält die Bank- und Ava-Secrets; die
  # host-spezifischen Netzwerkwerte stehen im Klartext hier, damit sie
  # reviewbar sind. Gleichnamige Keys weiter unten gewinnen.
  sops.templates.haushaltsbuch_env = {
    mode = "0400";
    restartUnits = [
      "podman-haushaltsbuch-web.service"
      "podman-haushaltsbuch-scheduler.service"
    ];
    content = ''
      ${config.sops.placeholder.haushaltsbuch_environment}
      DATA_DIR=/data
      HB_BIND_IP=10.20.50.11
      HB_HOST=0.0.0.0
      HB_PORT=${toString appPort}
      HB_ALLOWED_HOSTS=hb.hl.sk4i.com,10.20.50.11
      HB_TRUSTED_PROXY_IPS=${proxyAddress}
    '';
  };

  # uid/gid 10001 = Service-User `haushaltsbuch` im Image.
  systemd.tmpfiles.rules = [
    "d /srv/haushaltsbuch 0750 10001 10001 -"
  ];

  virtualisation.podman = {
    enable = true;
    autoPrune.enable = true;
  };
  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      haushaltsbuch-web = {
        image = haushaltsbuchImage;
        login = ghcrLogin;
        # Ohne TZ läuft der Container in UTC — die supercronic-Zeiten in
        # docker/crontab sind aber als Ortszeit gemeint (compose setzt das
        # ebenso).
        environment.TZ = "Europe/Berlin";
        environmentFiles = [config.sops.templates.haushaltsbuch_env.path];
        volumes = ["/srv/haushaltsbuch:/data:rw"];
        extraOptions = [
          "--network=host"
          "--security-opt=no-new-privileges"
          "--memory=1g"
        ];
      };
      haushaltsbuch-scheduler = {
        image = haushaltsbuchImage;
        login = ghcrLogin;
        cmd = [
          "/usr/local/bin/supercronic"
          "/app/docker/crontab"
        ];
        dependsOn = ["haushaltsbuch-web"];
        environmentFiles = [config.sops.templates.haushaltsbuch_env.path];
        environment = {
          TZ = "Europe/Berlin";
          # Nur der web-Container migriert die DB (kein init-Rennen).
          HB_INIT_DB = "0";
        };
        volumes = ["/srv/haushaltsbuch:/data:rw"];
        extraOptions = [
          "--network=host"
          "--security-opt=no-new-privileges"
          "--memory=512m"
        ];
      };
    };
  };

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
