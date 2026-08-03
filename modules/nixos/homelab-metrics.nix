# Glances als Metrik-Backend der Homelab-Hosts.
#
# Einziger Konsument ist das Homepage-Dashboard auf hl02
# (modules/nixos/homepage-dashboard.nix), das die Glances-REST-API pro Host
# abfragt und daraus die Auslastungsübersicht in der Kopfzeile rendert.
#
# Das Modul wird aus hosts/homelab/common.nix importiert und gilt damit für
# hl01–hl03; die LAN-Adresse kommt aus einem Attrset über den Hostnamen
# (gleiches Muster wie `hostPaths.<host>` in homelab-backup.nix).
{
  config,
  pkgs,
  ...
}: let
  # Nur das Dashboard auf hl02 ist legitimer Client der API.
  dashboardAddress = "10.20.50.12";
  glancesPort = 61208;

  lanAddresses = {
    hl01 = "10.20.50.11";
    hl02 = "10.20.50.12";
    hl03 = "10.20.50.13";
  };
  lanAddress = lanAddresses.${config.networking.hostName};
in {
  services.glances = {
    enable = true;
    package = pkgs.glances;
    port = glancesPort;
    # `openFirewall` würde den Port für das gesamte LAN öffnen. Da
    # tailscale0 in modules/nixos/tailscale.nix als `trustedInterfaces`
    # geführt wird, hört Glances zusätzlich bewusst nicht auf 0.0.0.0 —
    # sonst wäre die API im ganzen Tailnet erreichbar.
    openFirewall = false;
    extraArgs = [
      "--webserver"
      "--bind"
      lanAddress
    ];
  };

  # Glances ist ein Python-Prozess; auf den 8-GiB-Hosts hl02/hl03 soll er
  # keinesfalls mit den eigentlichen Diensten um RAM konkurrieren.
  systemd.services.glances.serviceConfig = {
    MemoryHigh = "256M";
    MemoryMax = "384M";
  };

  # Quell-beschränkt statt `interfaces.lan0.allowedTCPPorts`: die API gibt
  # Prozessliste und Systemdetails preis, das muss nicht das ganze LAN sehen.
  # Auf hl02 selbst greift die Regel nicht — der Zugriff auf die eigene
  # LAN-Adresse läuft über `lo`, und `lo` ist in der NixOS-Firewall erlaubt.
  networking.firewall = {
    extraCommands = ''
      iptables -A nixos-fw -i lan0 -p tcp \
        -s ${dashboardAddress}/32 --dport ${toString glancesPort} -j nixos-fw-accept
    '';
    extraStopCommands = ''
      iptables -D nixos-fw -i lan0 -p tcp \
        -s ${dashboardAddress}/32 --dport ${toString glancesPort} -j nixos-fw-accept \
        || true
    '';
  };
}
