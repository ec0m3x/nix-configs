# hl03 — ehemals pve03 (10.20.50.13, 8 GiB RAM, i5-4590T).
# Phase 3: Nextcloud, LiteLLM + Postgres, cloudflared und Restic-Ziel.
{inputs, ...}: {
  imports = [
    ../homelab/common.nix
    ./disko.nix
    inputs.self.nixosModules.cloudflared
    inputs.self.nixosModules.litellm
    inputs.self.nixosModules.nextcloud
    inputs.self.nixosModules.restic-target
  ];

  networking.hostName = "hl03";
  sops.defaultSopsFile = ../../secrets/hl03.yaml;

  # Onboard-NIC per MAC auf `lan0` pinnen
  systemd.network.links."10-lan0" = {
    matchConfig.MACAddress = "98:90:96:b2:db:a5";
    linkConfig.Name = "lan0";
  };
  networking.interfaces.lan0.ipv4.addresses = [
    {
      address = "10.20.50.13";
      prefixLength = 24;
    }
  ];

  # Existing ext4 filesystem containing the untouched PBS datastore. Restic
  # uses /srv/backup/restic next to it; this disk is never managed by disko.
  fileSystems."/srv/backup" = {
    device = "/dev/disk/by-uuid/bea9cd03-b112-4d84-8c7d-26d53635a9d7";
    fsType = "ext4";
    options = [
      "nofail"
      "x-systemd.device-timeout=10s"
    ];
  };
}
