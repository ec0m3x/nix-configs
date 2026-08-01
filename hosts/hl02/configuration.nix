# hl02 — ehemals pve02 (10.20.50.12, 8 GiB RAM, i5-4590T).
# Phase 1: AdGuard Home + Tailscale-Subnet-Router.
# Phase 2: Vaultwarden, SearXNG, Stirling-PDF, Reverse-Proxy (Wildcard
# *.hl.sk4i.com + Tailnet-Einstieg).
{inputs, ...}: {
  imports = [
    ../homelab/common.nix
    ./disko.nix
    ./services/adguardhome.nix
    ./services/tailscale-router.nix
    inputs.self.nixosModules.homelab-backup
    inputs.self.nixosModules.searxng
    inputs.self.nixosModules.stirling-pdf
    inputs.self.nixosModules.traefik
    inputs.self.nixosModules.vaultwarden
  ];

  networking.hostName = "hl02";
  sops.defaultSopsFile = ../../secrets/hl02.yaml;

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
    # Bisherige AdGuard-Service-IP beibehalten, damit Router und Clients
    # während Phase 1 nicht gleichzeitig umkonfiguriert werden müssen.
    {
      address = "10.20.50.49";
      prefixLength = 24;
    }
  ];
}
