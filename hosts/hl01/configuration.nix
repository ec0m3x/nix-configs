# hl01 — ehemals pve01 (10.20.50.11, 16 GiB RAM, i5-4590T).
# Phase 4: Immich, Paperless-ngx, Open WebUI und Haushaltsbuch.
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
    ./services/postgresql.nix
    inputs.self.nixosModules.haos-vm
    inputs.self.nixosModules.haushaltsbuch
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

  # Keep compatibility for user-managed Python environments that expect the
  # conventional Linux dynamic linker (for example a fresh Hermes install).
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib
      zlib
      openssl
      libffi
      sqlite
    ];
  };

  environment.systemPackages = with pkgs; [
    git
    sqlite
    zstd
  ];
}
