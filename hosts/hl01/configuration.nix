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
    ./services/postgresql.nix
    inputs.self.nixosModules.haos-vm
    inputs.self.nixosModules.haushaltsbuch
    inputs.self.nixosModules.hermes-agent
    inputs.self.nixosModules.honcho
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

  environment.systemPackages = with pkgs; [
    git
    sqlite
    zstd
  ];

  # One-time handoff for a clean Hermes installation under the ecomex account.
  # Remove this activation snippet after the private export has been verified.
  system.activationScripts.exportAvaConfig = {
    deps = [
      "setupSecrets"
      "users"
    ];
    text = ''
      source_soul=/home/hermes/.hermes/SOUL.md
      source_environment=/run/secrets/hermes_environment
      destination=/home/ecomex/ava-config-export

      [[ -f "$source_soul" ]] || {
        echo "AVA export source SOUL.md is missing" >&2
        exit 1
      }
      [[ -f "$source_environment" ]] || {
        echo "AVA export source environment is missing" >&2
        exit 1
      }
      [[ ! -e "$destination" ]] || {
        echo "refusing to overwrite existing AVA export" >&2
        exit 1
      }

      temporary_dir="$(${pkgs.coreutils}/bin/mktemp -d --tmpdir=/home/ecomex .ava-config-export.XXXXXX)"
      trap '
        ${pkgs.coreutils}/bin/rm -f "$temporary_dir/SOUL.md" "$temporary_dir/.env"
        ${pkgs.coreutils}/bin/rmdir "$temporary_dir"
      ' EXIT

      ${pkgs.coreutils}/bin/install -m 0600 -o ecomex -g users \
        "$source_soul" "$temporary_dir/SOUL.md"
      ${pkgs.coreutils}/bin/install -m 0600 -o ecomex -g users \
        "$source_environment" "$temporary_dir/.env"
      ${pkgs.coreutils}/bin/chown ecomex:users "$temporary_dir"
      ${pkgs.coreutils}/bin/chmod 0700 "$temporary_dir"
      ${pkgs.coreutils}/bin/mv "$temporary_dir" "$destination"
      trap - EXIT
    '';
  };
}
