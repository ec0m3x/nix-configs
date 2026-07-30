{
  config,
  pkgs,
  ...
}: {
  sops.secrets = {
    vaultwarden_admin_token = {};
    vaultwarden_smtp_username = {};
    vaultwarden_smtp_password = {};
  };
  sops.templates.vaultwarden_env = {
    owner = "vaultwarden";
    group = "vaultwarden";
    mode = "0400";
    restartUnits = ["vaultwarden.service"];
    content = ''
      ADMIN_TOKEN=${config.sops.placeholder.vaultwarden_admin_token}
      SMTP_USERNAME=${config.sops.placeholder.vaultwarden_smtp_username}
      SMTP_PASSWORD=${config.sops.placeholder.vaultwarden_smtp_password}
    '';
  };

  services.vaultwarden = {
    enable = true;
    package = pkgs.vaultwarden-1_37_1;
    webVaultPackage = pkgs.vaultwarden-1_37_1.webvault;
    dbBackend = "sqlite";
    environmentFile = config.sops.templates.vaultwarden_env.path;
    backupDir = "/var/backup/vaultwarden";
    config = {
      DOMAIN = "https://vault.sk4i.com";
      SIGNUPS_ALLOWED = false;
      SHOW_PASSWORD_HINT = false;

      # Only the reverse proxy may reach the application directly.
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = 8222;

      # The target database is on a local SSD, unlike the previous NFS PVC.
      ENABLE_DB_WAL = true;

      SMTP_HOST = "smtp.protonmail.ch";
      SMTP_PORT = 587;
      SMTP_SECURITY = "starttls";
      SMTP_FROM = "admin@sk4i.com";
      SMTP_FROM_NAME = "Vaultwarden";
    };
  };
}
