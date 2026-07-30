{
  config,
  pkgs,
  ...
}: {
  sops.secrets = {
    nextcloud_instanceid = {
      owner = "nextcloud";
      group = "nextcloud";
      mode = "0400";
    };
    nextcloud_passwordsalt = {
      owner = "nextcloud";
      group = "nextcloud";
      mode = "0400";
    };
    nextcloud_secret = {
      owner = "nextcloud";
      group = "nextcloud";
      mode = "0400";
    };
    nextcloud_mail_smtp_password = {
      owner = "nextcloud";
      group = "nextcloud";
      mode = "0400";
      restartUnits = ["phpfpm-nextcloud.service"];
    };
  };

  sops.templates.nextcloud_secret_json = {
    owner = "nextcloud";
    group = "nextcloud";
    mode = "0400";
    restartUnits = ["phpfpm-nextcloud.service"];
    content = builtins.toJSON {
      instanceid = config.sops.placeholder.nextcloud_instanceid;
      passwordsalt = config.sops.placeholder.nextcloud_passwordsalt;
      secret = config.sops.placeholder.nextcloud_secret;
    };
  };

  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud34;
    hostName = "cloud.sk4i.com";
    home = "/srv/nextcloud";
    datadir = "/srv/nextcloud";
    https = true;
    configureRedis = true;
    maxUploadSize = "16G";

    database.createLocally = true;
    config = {
      dbtype = "mysql";
      dbname = "nextcloud";
      dbuser = "nextcloud";
      # The source database is restored after the first activation, so a
      # disposable bootstrap admin account is unnecessary.
      adminuser = null;
      adminpassFile = null;
    };

    extraApps = {
      inherit (pkgs.nextcloud34Packages.apps) calendar contacts;
    };
    appstoreEnable = true;

    secretFile = config.sops.templates.nextcloud_secret_json.path;
    secrets.mail_smtppassword =
      config.sops.secrets.nextcloud_mail_smtp_password.path;

    settings = {
      trusted_domains = ["10.20.50.13"];
      trusted_proxies = ["10.20.50.12"];
      forwarded_for_headers = ["HTTP_X_FORWARDED_FOR"];
      overwriteprotocol = "https";
      "overwrite.cli.url" = "https://cloud.sk4i.com";

      "mysql.utf8mb4" = true;
      maintenance_window_start = 1;
      default_phone_region = "DE";
      log_type = "systemd";
      loglevel = 3;

      mail_smtpname = "info@sks-concept.de";
      mail_domain = "sks-concept.de";
      mail_from_address = "info";
      mail_smtpmode = "smtp";
      mail_smtphost = "smtp.ionos.de";
      mail_smtpauth = true;
      mail_smtpport = 465;
      mail_sendmailmode = "smtp";
      mail_smtpstreamoptions.ssl = {
        allow_self_signed = false;
        verify_peer = true;
        verify_peer_name = true;
      };
    };
  };

  # Keep both the application data and MariaDB on the dedicated Samsung SSD.
  services.mysql.dataDir = "/srv/mysql";

  services.nginx.virtualHosts."cloud.sk4i.com".listen = [
    {
      addr = "10.20.50.13";
      port = 80;
    }
  ];

  networking.firewall.interfaces.lan0.allowedTCPPorts = [80];
}
