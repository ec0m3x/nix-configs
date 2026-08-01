{pkgs, ...}: {
  # Immich and Paperless share the source-compatible PostgreSQL 16 instance.
  # Both databases and all application data live on the dedicated /srv SSD.
  services.postgresql = {
    package = pkgs.postgresql_16;
    dataDir = "/srv/postgresql/16";
  };

  environment.systemPackages = [pkgs.postgresql_16];

  systemd.tmpfiles.rules = [
    "d /srv/postgresql 0750 postgres postgres -"
    "d /srv/postgresql/16 0700 postgres postgres -"
  ];
}
