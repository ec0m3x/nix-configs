# hl01 — ehemals pve01 (10.20.50.11, 16 GiB RAM, i5-4590T).
# Phase 4: Immich, Paperless-ngx, Open WebUI, Haushaltsbuch + Honcho.
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

  # One-time guarded cleanup after the migrated Hermes services and account
  # have been removed. Delete this activation script after the rollout.
  system.activationScripts.removeLegacyHermes = {
    deps = ["users"];
    text = ''
      set -Eeuo pipefail

      export_dir=/home/ecomex/ava-config-export
      for export_file in "$export_dir/SOUL.md" "$export_dir/.env"; do
        if [[ ! -f "$export_file" || -L "$export_file" || ! -s "$export_file" ]]; then
          echo "Refusing Hermes cleanup: AVA export is missing or unsafe: $export_file" >&2
          exit 1
        fi
        if [[ "$(${pkgs.coreutils}/bin/stat -c %u:%g:%a "$export_file")" != "1000:100:600" ]]; then
          echo "Refusing Hermes cleanup: unexpected AVA export ownership or mode: $export_file" >&2
          exit 1
        fi
      done

      backup_state=$(${pkgs.systemd}/bin/systemctl is-active restic-backups-hl01.service || true)
      if [[ "$backup_state" != "inactive" ]]; then
        echo "Refusing Hermes cleanup: backup service is $backup_state" >&2
        exit 1
      fi

      while IFS=: read -r name _ _ _ _ _ _; do
        if [[ "$name" == "hermes" ]]; then
          echo "Refusing Hermes cleanup: user hermes still exists" >&2
          exit 1
        fi
      done </etc/passwd
      while IFS=: read -r name _ _ _; do
        if [[ "$name" == "hermes" ]]; then
          echo "Refusing Hermes cleanup: group hermes still exists" >&2
          exit 1
        fi
      done </etc/group

      if ${pkgs.procps}/bin/pgrep -u 1001 >/dev/null; then
        echo "Refusing Hermes cleanup: UID 1001 still owns running processes" >&2
        exit 1
      fi

      if [[ ! -e /home/hermes ]]; then
        exit 0
      fi
      if [[ ! -d /home/hermes || -L /home/hermes ]]; then
        echo "Refusing Hermes cleanup: /home/hermes is not a real directory" >&2
        exit 1
      fi
      if [[ "$(${pkgs.coreutils}/bin/stat -c %u:%g /home/hermes)" != "1001:1001" ]]; then
        echo "Refusing Hermes cleanup: unexpected /home/hermes ownership" >&2
        exit 1
      fi
      if ${pkgs.util-linux}/bin/findmnt -R -n -o TARGET /home/hermes | ${pkgs.gnugrep}/bin/grep -q .; then
        echo "Refusing Hermes cleanup: /home/hermes contains a mount" >&2
        exit 1
      fi

      ${pkgs.coreutils}/bin/rm -rf --one-file-system -- /home/hermes
      [[ ! -e /home/hermes ]]
    '';
  };

  environment.systemPackages = with pkgs; [
    git
    sqlite
    zstd
  ];
}
