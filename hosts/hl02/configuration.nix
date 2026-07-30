# hl02 — ehemals pve02 (10.20.50.12, 8 GiB RAM, i5-4590T).
# Phase 1: AdGuard Home + Tailscale-Subnet-Router.
# Phase 2: Vaultwarden, SearXNG, Stirling-PDF, Reverse-Proxy (Wildcard
# *.hl.sk4i.com + Tailnet-Einstieg).
{inputs, ...}: {
  imports = [
    ../homelab/common.nix
    ./disko.nix
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

  services.adguardhome = {
    enable = true;
    # Die aus LXC 106 wiederhergestellte Konfiguration bleibt über die
    # Weboberfläche änderbar. Zugangsdaten gehören nicht in den Nix-Store.
    mutableSettings = true;
    host = "10.20.50.49";
    port = 80;
    settings.dns.bootstrap_dns = [
      "9.9.9.10"
      "149.112.112.10"
      "2620:fe::10"
      "2620:fe::fe:10"
    ];
  };

  # AdGuard nur im LAN freigeben; tailscale0 ist im Tailscale-Modul bereits
  # als vertrauenswürdiges Interface eingetragen.
  networking.firewall.interfaces.lan0 = {
    allowedTCPPorts = [53 80];
    allowedUDPPorts = [53];
  };

  # Der gesicherte tailscaled-State behält die bestehende Node-Identität.
  # Das Flag stellt die gewünschte Route zusätzlich deklarativ sicher.
  services.tailscale.extraSetFlags = [
    "--advertise-routes=10.20.50.0/24"
  ];
}
