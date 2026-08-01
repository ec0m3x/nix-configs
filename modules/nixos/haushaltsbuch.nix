{
  config,
  pkgs,
  ...
}: let
  haushaltsbuchImage = "ghcr.io/ec0m3x/haushaltsbuch@sha256:500b3d1773d4690c33887ac530c90bd225ab08894e56970f778e4ee2326b59e7";
  ghcrLogin = {
    registry = "ghcr.io";
    username = "ec0m3x";
    passwordFile = config.sops.secrets.ghcr_pull_token.path;
  };
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
      HB_PORT=8787
      HB_ALLOWED_HOSTS=hb.hl.sk4i.com,10.20.50.11
      HB_TRUSTED_PROXY_IPS=10.20.50.12
    '';
  };

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
        environment.HB_INIT_DB = "0";
        volumes = ["/srv/haushaltsbuch:/data:rw"];
        extraOptions = [
          "--network=host"
          "--security-opt=no-new-privileges"
          "--memory=512m"
        ];
      };
    };
  };

  networking.firewall.interfaces.lan0.allowedTCPPorts = [8787];
}
