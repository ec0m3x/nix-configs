# hl03 — ehemals pve03 (10.20.50.13, 8 GiB RAM, i5-4590T).
# Phase 3: Nextcloud, LiteLLM + Postgres, cloudflared, restic-Backup-Ziel
# auf der 1-TB-Platte.
{inputs, ...}: {
  imports = [
    ../homelab/common.nix
    ./disko.nix
  ];

  networking.hostName = "hl03";

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
}
