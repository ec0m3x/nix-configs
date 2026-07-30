{
  config,
  pkgs,
  ...
}: let
  litellmConfig = pkgs.writeText "litellm-config.yaml" ''
    general_settings:
      master_key: os.environ/LITELLM_MASTER_KEY
      database_url: os.environ/DATABASE_URL
      store_model_in_db: true
      drop_params: true
  '';
in {
  sops.secrets.litellm_postgres_password = {
    owner = "postgres";
    group = "postgres";
    mode = "0400";
    restartUnits = ["litellm-postgresql-provision.service"];
  };
  sops.secrets.litellm_master_key = {};
  sops.secrets.litellm_database_url = {};
  sops.templates.litellm_env = {
    mode = "0400";
    restartUnits = ["podman-litellm.service"];
    content = ''
      LITELLM_MASTER_KEY=${config.sops.placeholder.litellm_master_key}
      DATABASE_URL=${config.sops.placeholder.litellm_database_url}
    '';
  };

  # PostgreSQL's service sandbox resolves the data directory before its
  # ExecStartPre can initialize it, so the directory must already exist.
  systemd.tmpfiles.rules = [
    "d /srv/postgresql/18 0700 postgres postgres -"
  ];

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_18;
    dataDir = "/srv/postgresql/18";
    ensureDatabases = ["litellm"];
    ensureUsers = [
      {
        name = "litellm";
        ensureDBOwnership = true;
      }
    ];
    settings.password_encryption = "scram-sha-256";
    authentication = ''
      local all all peer
      host litellm litellm 127.0.0.1/32 scram-sha-256
      host litellm litellm ::1/128 scram-sha-256
    '';
  };

  systemd.services.litellm-postgresql-provision = {
    description = "Provision the LiteLLM PostgreSQL role password";
    after = ["postgresql-setup.service"];
    requires = ["postgresql-setup.service"];
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      Group = "postgres";
      RemainAfterExit = true;
    };
    script = ''
      export LITELLM_DB_PASSWORD="$(
        ${pkgs.coreutils}/bin/cat \
          ${config.sops.secrets.litellm_postgres_password.path}
      )"
      ${config.services.postgresql.package}/bin/psql \
        --dbname=postgres \
        --set=ON_ERROR_STOP=1 <<'SQL'
      \getenv litellm_password LITELLM_DB_PASSWORD
      ALTER ROLE litellm WITH LOGIN PASSWORD :'litellm_password';
      SQL
    '';
  };

  virtualisation.podman = {
    enable = true;
    autoPrune.enable = true;
  };
  virtualisation.oci-containers = {
    backend = "podman";
    containers.litellm = {
      image = "ghcr.io/berriai/litellm:v1.94.0@sha256:65d84a2282137b4dc73bbe184650a7c807177c533e4223b3bfbc87963fe3fabe";
      cmd = [
        "--config"
        "/app/config.yaml"
        "--port"
        "4000"
      ];
      environmentFiles = [config.sops.templates.litellm_env.path];
      volumes = ["${litellmConfig}:/app/config.yaml:ro"];
      extraOptions = ["--network=host"];
    };
  };

  systemd.services.podman-litellm = {
    after = ["litellm-postgresql-provision.service"];
    requires = ["litellm-postgresql-provision.service"];
  };

  networking.firewall.interfaces.lan0.allowedTCPPorts = [4000];
}
