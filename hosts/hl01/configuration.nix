# hl01 — ehemals pve01 (10.20.50.11, 16 GiB RAM, i5-4590T).
# Phase 4: Immich, Paperless-ngx and Open WebUI.
# Eine frische Home-Assistant-OS-VM ist aktiv; Samba folgt bei Bedarf später.
#
# ACHTUNG: Die Onboard-NIC dieses Hosts ist defekt/down — das System läuft
# über einen USB-Ethernet-Adapter (MAC 00:24:9b:49:70:91). Bei Adaptertausch
# muss die MAC hier angepasst werden.
{
  config,
  inputs,
  pkgs,
  ...
}: {
  imports = [
    ../homelab/common.nix
    ./disko.nix
    ./services/postgresql.nix
    inputs.self.nixosModules.haos-vm
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

  # One-time guarded cleanup after Haushaltsbuch and Honcho were stopped.
  # Remove this activation script after the cleanup rollout.
  system.activationScripts.removeLegacyHouseholdApps = {
    deps = ["users"];
    text = ''
      set -Eeuo pipefail

      export_file=/home/ecomex/haushaltsbuch.env
      if [[ ! -f "$export_file" || -L "$export_file" || ! -s "$export_file" ]]; then
        echo "Refusing cleanup: Haushaltsbuch export is missing or unsafe" >&2
        exit 1
      fi
      if [[ "$(${pkgs.coreutils}/bin/stat -c %u:%g:%a:%s "$export_file")" != "1000:100:600:2888" ]]; then
        echo "Refusing cleanup: unexpected Haushaltsbuch export metadata" >&2
        exit 1
      fi
      read -r export_hash _ < <(${pkgs.coreutils}/bin/sha256sum "$export_file")
      if [[ "$export_hash" != "8193793cf7240abd08b4044dde8ed0d76c550eef856b149b7dfe34a63228c654" ]]; then
        echo "Refusing cleanup: Haushaltsbuch export checksum changed" >&2
        exit 1
      fi

      backup_state=$(${pkgs.systemd}/bin/systemctl is-active restic-backups-hl01.service || true)
      if [[ "$backup_state" != "inactive" ]]; then
        echo "Refusing cleanup: backup service is $backup_state" >&2
        exit 1
      fi

      for unit in \
        podman-haushaltsbuch-web.service \
        podman-haushaltsbuch-scheduler.service \
        podman-honcho-api.service \
        podman-honcho-deriver.service \
        honcho-postgresql-provision.service \
        redis-honcho.service; do
        load_state=$(${pkgs.systemd}/bin/systemctl show "$unit" -p LoadState --value 2>/dev/null || true)
        if [[ "$load_state" != "not-found" ]]; then
          echo "Refusing cleanup: $unit has load state $load_state" >&2
          exit 1
        fi
      done

      if ${pkgs.iproute2}/bin/ss -ltnH | ${pkgs.gnugrep}/bin/grep -Eq ':(8787|8010|6380)[[:space:]]'; then
        echo "Refusing cleanup: an application port is still listening" >&2
        exit 1
      fi

      ${pkgs.util-linux}/bin/runuser -u postgres -- \
        ${config.services.postgresql.package}/bin/psql \
        --dbname=postgres \
        --set=ON_ERROR_STOP=1 \
        --command='DROP DATABASE IF EXISTS honcho WITH (FORCE)'
      ${pkgs.util-linux}/bin/runuser -u postgres -- \
        ${config.services.postgresql.package}/bin/psql \
        --dbname=postgres \
        --set=ON_ERROR_STOP=1 \
        --command='DROP ROLE IF EXISTS honcho'

      for container in \
        haushaltsbuch-web \
        haushaltsbuch-scheduler \
        honcho-api \
        honcho-deriver; do
        if ${pkgs.podman}/bin/podman container exists "$container"; then
          ${pkgs.podman}/bin/podman rm --force "$container"
        fi
      done
      for image in \
        ghcr.io/ec0m3x/haushaltsbuch@sha256:500b3d1773d4690c33887ac530c90bd225ab08894e56970f778e4ee2326b59e7 \
        ghcr.io/ec0m3x/honcho@sha256:1013f0208844cfa0add7deab9f8a5f4d158f11f83cd0d3bceccb011daa4d288f; do
        if ${pkgs.podman}/bin/podman image exists "$image"; then
          ${pkgs.podman}/bin/podman image rm --force "$image"
        fi
      done

      remove_tree() {
        local target="$1"
        local expected_owner="''${2-}"
        [[ -e "$target" ]] || return 0
        if [[ ! -d "$target" || -L "$target" ]]; then
          echo "Refusing cleanup: $target is not a real directory" >&2
          exit 1
        fi
        if [[ -n "$expected_owner" ]] && \
          [[ "$(${pkgs.coreutils}/bin/stat -c %u:%g "$target")" != "$expected_owner" ]]; then
          echo "Refusing cleanup: unexpected ownership for $target" >&2
          exit 1
        fi
        if ${pkgs.util-linux}/bin/findmnt -R -n -o TARGET "$target" | ${pkgs.gnugrep}/bin/grep -q .; then
          echo "Refusing cleanup: $target contains a mount" >&2
          exit 1
        fi
        ${pkgs.coreutils}/bin/rm -rf --one-file-system -- "$target"
        [[ ! -e "$target" ]]
      }

      remove_tree /srv/haushaltsbuch 10001:10001
      remove_tree /var/lib/redis-honcho

      for staged_file in \
        /var/lib/homelab-backup/haushaltsbuch.sqlite \
        /var/lib/homelab-backup/haushaltsbuch.sqlite.new; do
        if [[ -e "$staged_file" ]]; then
          if [[ ! -f "$staged_file" || -L "$staged_file" ]]; then
            echo "Refusing cleanup: unsafe staged file $staged_file" >&2
            exit 1
          fi
          ${pkgs.coreutils}/bin/rm -f -- "$staged_file"
        fi
      done
    '';
  };

  environment.systemPackages = with pkgs; [
    git
    sqlite
    zstd
  ];
}
