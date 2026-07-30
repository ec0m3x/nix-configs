{
  config,
  lib,
  pkgs,
  ...
}: let
  haushaltsbuchImage = "ghcr.io/ec0m3x/haushaltsbuch:f2aeb9d@sha256:500b3d1773d4690c33887ac530c90bd225ab08894e56970f778e4ee2326b59e7";
  honchoImage = "ghcr.io/ec0m3x/honcho:eb386c3@sha256:1013f0208844cfa0add7deab9f8a5f4d158f11f83cd0d3bceccb011daa4d288f";
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
        "podman-honcho-api.service"
        "podman-honcho-deriver.service"
      ];
    };
    haushaltsbuch_environment = {
      mode = "0400";
      restartUnits = [
        "podman-haushaltsbuch-web.service"
        "podman-haushaltsbuch-scheduler.service"
      ];
    };
    honcho_environment = {
      mode = "0400";
      restartUnits = [
        "podman-honcho-api.service"
        "podman-honcho-deriver.service"
      ];
    };
    honcho_postgres_password = {
      owner = "postgres";
      group = "postgres";
      mode = "0400";
      restartUnits = ["honcho-postgresql-provision.service"];
    };
  };

  sops.templates = {
    haushaltsbuch_env = {
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
    honcho_env = {
      mode = "0400";
      restartUnits = [
        "podman-honcho-api.service"
        "podman-honcho-deriver.service"
      ];
      content = ''
        ${config.sops.placeholder.honcho_environment}
        DB_CONNECTION_URI=postgresql+psycopg://honcho:${config.sops.placeholder.honcho_postgres_password}@127.0.0.1:5432/honcho
        CACHE_URL=redis://127.0.0.1:6380/0?suppress=true
        CACHE_ENABLED=true
      '';
    };
  };

  # Immich already adds pgvector and VectorChord to this PostgreSQL 16
  # instance. Honcho therefore only needs its database and role here.
  services.postgresql = {
    ensureDatabases = ["honcho"];
    ensureUsers = [
      {
        name = "honcho";
        ensureDBOwnership = true;
      }
    ];
    authentication = lib.mkAfter ''
      host honcho honcho 127.0.0.1/32 scram-sha-256
      host honcho honcho ::1/128 scram-sha-256
    '';
  };

  systemd.services.honcho-postgresql-provision = {
    description = "Provision the Honcho PostgreSQL role and vector extension";
    after = ["postgresql-setup.service"];
    requires = ["postgresql-setup.service"];
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      Group = "postgres";
      RemainAfterExit = true;
    };
    script = ''
      export HONCHO_DB_PASSWORD="$(
        ${pkgs.coreutils}/bin/cat \
          ${config.sops.secrets.honcho_postgres_password.path}
      )"
      ${config.services.postgresql.package}/bin/psql \
        --dbname=postgres \
        --set=ON_ERROR_STOP=1 <<'SQL'
      \getenv honcho_password HONCHO_DB_PASSWORD
      ALTER ROLE honcho WITH LOGIN PASSWORD :'honcho_password';
      SQL
      ${config.services.postgresql.package}/bin/psql \
        --dbname=honcho \
        --set=ON_ERROR_STOP=1 \
        --command='CREATE EXTENSION IF NOT EXISTS vector'
    '';
  };

  # The exported Redis database contains no keys. Keep the replacement local
  # to hl01 and bounded; PostgreSQL remains Honcho's durable state.
  services.redis.servers.honcho = {
    enable = true;
    bind = "127.0.0.1";
    port = 6380;
    settings = {
      maxmemory = "256mb";
      maxmemory-policy = "allkeys-lru";
    };
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
      honcho-api = {
        image = honchoImage;
        login = ghcrLogin;
        entrypoint = "/bin/sh";
        cmd = [
          "-c"
          "/app/.venv/bin/python scripts/provision_db.py && exec /app/.venv/bin/fastapi run --host 127.0.0.1 --port 8010 src/main.py"
        ];
        environmentFiles = [config.sops.templates.honcho_env.path];
        extraOptions = [
          "--network=host"
          "--security-opt=no-new-privileges"
          "--memory=3g"
        ];
      };
      honcho-deriver = {
        image = honchoImage;
        login = ghcrLogin;
        entrypoint = "/app/.venv/bin/python";
        cmd = [
          "-m"
          "src.deriver"
        ];
        dependsOn = ["honcho-api"];
        environmentFiles = [config.sops.templates.honcho_env.path];
        extraOptions = [
          "--network=host"
          "--security-opt=no-new-privileges"
          "--memory=3g"
        ];
      };
    };
  };

  systemd.services = {
    podman-honcho-api = {
      after = [
        "honcho-postgresql-provision.service"
        "redis-honcho.service"
      ];
      requires = [
        "honcho-postgresql-provision.service"
        "redis-honcho.service"
      ];
    };
    podman-honcho-deriver = {
      after = [
        "honcho-postgresql-provision.service"
        "redis-honcho.service"
      ];
      requires = [
        "honcho-postgresql-provision.service"
        "redis-honcho.service"
      ];
    };
  };

  networking.firewall.interfaces.lan0.allowedTCPPorts = [8787];
}
