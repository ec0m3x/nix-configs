{
  config,
  lib,
  pkgs,
  ...
}: let
  offlineDisk = "/dev/disk/by-id/usb-Seagate_M3_Portable_NM15KS34-0:0";
  offlinePartition = "/dev/disk/by-uuid/cc005762-01f1-4cbd-94af-a158819e3b80";
  offlineUuid = "cc005762-01f1-4cbd-94af-a158819e3b80";
  offlineSerial = "NM15KS34";
  offlineSize = "1000204885504";
  onlineUuid = "bea9cd03-b112-4d84-8c7d-26d53635a9d7";
  mountPoint = "/run/homelab-offline";
  statusFile = "/var/lib/homelab-backup/offline-mirror.status";
  lockFile = "/run/lock/homelab-restic-target.lock";
  passwordFile = config.sops.secrets.homelab_restic_repository_password.path;
in {
  assertions = [
    {
      assertion = config.networking.hostName == "hl03";
      message = "offline-backup-mirror may only be enabled on hl03";
    }
  ];

  services.udisks2.enable = true;

  # Only the commissioned filesystem on the commissioned Seagate may trigger
  # the mirror. Cloning either the UUID or the serial alone is insufficient.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="block", ENV{DEVTYPE}=="partition", ENV{ID_FS_UUID}=="${offlineUuid}", ENV{ID_SERIAL_SHORT}=="${offlineSerial}", TAG+="systemd", ENV{SYSTEMD_WANTS}+="restic-offline-mirror.service"
  '';

  systemd.tmpfiles.rules = [
    "d ${mountPoint} 0700 root root -"
    "d /var/cache/restic-offline-mirror 0700 root root -"
  ];

  systemd.services.restic-offline-mirror = {
    description = "Copy and verify Restic repositories on the removable offline disk";
    after = [
      "srv-backup.mount"
      "udisks2.service"
    ];
    requires = ["udisks2.service"];
    unitConfig.RequiresMountsFor = "/srv/backup";
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "infinity";
      Nice = 15;
      IOSchedulingClass = "idle";
      CPUWeight = 10;
      IOWeight = 10;
      UMask = "0077";
    };
    path = [
      pkgs.coreutils
      pkgs.e2fsprogs
      pkgs.gnugrep
      pkgs.gnused
      pkgs.restic
      pkgs.udisks2
      pkgs.util-linux
    ];
    script = ''
      set -Eeuo pipefail

      success=0
      mounted=0
      last_action="startup validation"

      write_status() {
        local state=$1
        local detail=$2
        local temporary="${statusFile}.new"

        printf 'state=%s\ntime=%s\ndetail=%s\n' \
          "$state" \
          "$(date --iso-8601=seconds)" \
          "$detail" >"$temporary"
        chmod 0644 "$temporary"
        mv "$temporary" ${statusFile}
      }

      cleanup() {
        local result=$?
        trap - EXIT

        if ((mounted)); then
          sync
          if ! umount ${mountPoint}; then
            result=1
          fi
        fi

        if ((!success)); then
          write_status failure "$last_action failed with exit status $result"
        fi
        exit "$result"
      }
      trap cleanup EXIT

      install -d -m 0711 /var/lib/homelab-backup
      install -d -m 0700 ${mountPoint} /var/cache/restic-offline-mirror
      last_action="wait for Restic target lock"
      write_status running "$last_action"
      exec 9>${lockFile}
      flock --exclusive 9

      last_action="startup validation"
      write_status running "$last_action"

      [[ -b ${offlineDisk} ]]
      [[ -b ${offlinePartition} ]]

      target_disk=$(readlink -f ${offlineDisk})
      target_partition=$(readlink -f ${offlinePartition})
      [[ -b "$target_disk" ]]
      [[ -b "$target_partition" ]]
      [[ "$(lsblk -dnro TYPE "$target_disk")" == disk ]]
      [[ "$(lsblk -dnro TRAN "$target_disk")" == usb ]]
      [[ "$(lsblk -dnro RO "$target_disk")" == 0 ]]
      [[ "$(blockdev --getsize64 "$target_disk")" == ${offlineSize} ]]
      [[ "$(lsblk -dnro UUID "$target_partition")" == ${offlineUuid} ]]
      [[ "$(lsblk -dnro LABEL "$target_partition")" == HOMELAB_OFFLINE ]]

      partition_parent=$(lsblk -dnro PKNAME "$target_partition")
      [[ "$(readlink -f "/dev/$partition_parent")" == "$target_disk" ]]

      actual_serial=$(udevadm info --query=property --name="$target_disk" |
        sed -n 's/^ID_SERIAL_SHORT=//p')
      [[ "$actual_serial" == ${offlineSerial} ]]

      online_source=$(findmnt -nr -o SOURCE --target /srv/backup)
      [[ "$(lsblk -dnro UUID "$online_source")" == ${onlineUuid} ]]
      [[ -z "$(findmnt -rn --source "$target_partition" || true)" ]]
      if mountpoint --quiet ${mountPoint}; then
        printf 'Offline mount point is already in use.\n' >&2
        exit 1
      fi

      last_action="offline filesystem check"
      write_status running "$last_action"
      set +e
      fsck.ext4 -p "$target_partition"
      fsck_result=$?
      set -e
      ((fsck_result <= 1))

      last_action="offline filesystem mount"
      mount \
        --types ext4 \
        --options rw,nosuid,nodev,noexec,noatime \
        "$target_partition" \
        ${mountPoint}
      mounted=1
      [[ "$(findmnt -nr -o UUID --target ${mountPoint})" == ${offlineUuid} ]]

      full_check=0
      if [[ ! -e ${mountPoint}/.full-check-completed ]]; then
        full_check=1
      fi

      for host in hl01 hl02 hl03; do
        source_repository="/srv/backup/restic/restic/$host"
        destination_repository="${mountPoint}/restic/$host"
        [[ -f "$source_repository/config" ]]

        if [[ ! -f "$destination_repository/config" ]]; then
          last_action="initialize offline $host repository"
          write_status running "$last_action"
          install -d -m 0700 "$destination_repository"
          restic \
            --repo "$destination_repository" \
            --password-file ${passwordFile} \
            init \
            --copy-chunker-params \
            --from-repo "$source_repository" \
            --from-password-file ${passwordFile}
        fi

        last_action="copy $host snapshots"
        write_status running "$last_action"
        restic \
          --repo "$destination_repository" \
          --password-file ${passwordFile} \
          --cache-dir /var/cache/restic-offline-mirror \
          --cleanup-cache \
          --retry-lock 30m \
          copy \
          --from-repo "$source_repository" \
          --from-password-file ${passwordFile}

        last_action="verify offline $host repository"
        write_status running "$last_action"
        if ((full_check)); then
          restic \
            --repo "$destination_repository" \
            --password-file ${passwordFile} \
            --cache-dir /var/cache/restic-offline-mirror \
            check --read-data
        else
          restic \
            --repo "$destination_repository" \
            --password-file ${passwordFile} \
            --cache-dir /var/cache/restic-offline-mirror \
            check --read-data-subset=10%
        fi
      done

      if ((full_check)); then
        printf '%s\n' "$(date --iso-8601=seconds)" >${mountPoint}/.full-check-completed
      fi

      usage_percent=$(df --output=pcent ${mountPoint} | tail -n 1 | tr -cd '0-9')
      [[ -n "$usage_percent" ]]
      if ((usage_percent >= 80)); then
        final_detail="success; warning: offline disk usage is $usage_percent%"
        printf 'WARNING: offline disk usage is %s%%\n' "$usage_percent" >&2
      else
        final_detail="success; offline disk usage is $usage_percent%"
      fi

      last_action="flush and unmount offline filesystem"
      write_status running "$last_action"
      sync
      umount ${mountPoint}
      mounted=0

      last_action="USB power-off"
      ${pkgs.udisks2}/bin/udisksctl power-off \
        --block-device "$target_disk" \
        --no-user-interaction

      write_status success "$final_detail; safe to unplug"
      success=1
      printf 'Offline mirror completed successfully; the USB disk is safe to unplug.\n'
    '';
  };
}
