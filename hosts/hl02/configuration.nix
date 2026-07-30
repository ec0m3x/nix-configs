# hl02 — ehemals pve02 (10.20.50.12, 8 GiB RAM, i5-4590T).
# Phase 1: AdGuard Home + Tailscale-Subnet-Router.
# Phase 2: Vaultwarden, SearXNG, Stirling-PDF, Reverse-Proxy (Wildcard
# *.hl.sk4i.com + Tailnet-Einstieg).
{inputs, ...}: {
  imports = [
    ../homelab/common.nix
    ./disko.nix

    inputs.self.nixosModules.tailscale
  ];

  networking.hostName = "hl02";

  # Onboard-NIC per MAC auf `lan0` pinnen
  systemd.network.links."10-lan0" = {
    matchConfig.MACAddress = "64:00:6a:3e:65:e2";
    linkConfig.Name = "lan0";
  };
  networking.interfaces.lan0.ipv4.addresses = [
    {
      address = "10.20.50.12";
      prefixLength = 24;
    }
  ];
}
