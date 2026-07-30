# hl01 — ehemals pve01 (10.20.50.11, 16 GiB RAM, i5-4590T).
# Phase 4: immich, paperless-ngx, open-webui, Samba-NAS, Home Assistant
# (HAOS-VM), haushaltsbuch + honcho (oci-containers), ava.
#
# ACHTUNG: Die Onboard-NIC dieses Hosts ist defekt/down — das System läuft
# über einen USB-Ethernet-Adapter (MAC 00:24:9b:49:70:91). Bei Adaptertausch
# muss die MAC hier angepasst werden.
{inputs, ...}: {
  imports = [
    ../homelab/common.nix
    ./disko.nix
  ];

  networking.hostName = "hl01";

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
}
