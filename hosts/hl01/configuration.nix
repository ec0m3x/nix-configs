# hl01 — ehemals pve01 (10.20.50.11, 16 GiB RAM, i5-4590T).
# Phase 4: Immich, Paperless-ngx, Open WebUI, Haushaltsbuch + Honcho und AVA.
# Eine frische Home-Assistant-OS-VM ist aktiv; Samba folgt bei Bedarf später.
#
# ACHTUNG: Die Onboard-NIC dieses Hosts ist defekt/down — das System läuft
# über einen USB-Ethernet-Adapter (MAC 00:24:9b:49:70:91). Bei Adaptertausch
# muss die MAC hier angepasst werden.
{
  inputs,
  pkgs,
  ...
}: {
  imports = [
    ../homelab/common.nix
    ./disko.nix
    inputs.self.nixosModules.haos-vm
    inputs.self.nixosModules.haushaltsbuch-honcho
    inputs.self.nixosModules.hermes-agent
    inputs.self.nixosModules.homelab-backup
    inputs.self.nixosModules.immich
    inputs.self.nixosModules.open-webui
    inputs.self.nixosModules.paperless
  ];

  networking.hostName = "hl01";
  sops.defaultSopsFile = ../../secrets/hl01.yaml;

  # USB-NIC per MAC auf `lan0` pinnen
  systemd.network.links."10-lan0" = {
    matchConfig.MACAddress = "00:24:9b:49:70:91";
    linkConfig.Name = "lan0";
  };
  networking.interfaces.lan0.ipv4.addresses = [
    {
      address = "10.20.50.11";
      prefixLength = 24;
    }
  ];

  # Immich and Paperless share the source-compatible PostgreSQL 16 instance.
  # Both databases and all application data live on the dedicated /srv SSD.
  services.postgresql = {
    package = pkgs.postgresql_16;
    dataDir = "/srv/postgresql/16";
  };
  environment.systemPackages = with pkgs; [
    git
    postgresql_16
    sqlite
    zstd
  ];
  systemd.tmpfiles.rules = [
    "d /srv/postgresql 0750 postgres postgres -"
    "d /srv/postgresql/16 0700 postgres postgres -"
  ];
}
