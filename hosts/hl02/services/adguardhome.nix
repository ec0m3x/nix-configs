{...}: {
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
}
