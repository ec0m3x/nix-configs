#!/usr/bin/env bash
set -Eeuo pipefail

readonly expected_by_id=/dev/disk/by-id/usb-Seagate_M3_Portable_NM15KS34-0:0
readonly expected_serial=NM15KS34
readonly expected_size=1000204885504
readonly expected_online_uuid=bea9cd03-b112-4d84-8c7d-26d53635a9d7
readonly filesystem_label=HOMELAB_OFFLINE

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

[[ $EUID -eq 0 ]] || die "run this script as root"
[[ $(hostname -s) == "hl03" ]] || die "this script may only run on hl03"
[[ -b $expected_by_id ]] || die "verified Seagate by-id path is missing"

target_disk=$(readlink -f "$expected_by_id")
readonly target_disk
[[ -b $target_disk ]] || die "resolved target is not a block device: $target_disk"
[[ $(lsblk -dnro TYPE "$target_disk") == "disk" ]] || die "target is not a whole disk"
[[ $(lsblk -dnro TRAN "$target_disk") == "usb" ]] || die "target is not connected through USB"
[[ $(lsblk -dnro RO "$target_disk") == "0" ]] || die "target disk is read-only"
[[ $(blockdev --getsize64 "$target_disk") == "$expected_size" ]] || die "target size does not match"

actual_serial=$(udevadm info --query=property --name="$target_disk" |
  sed -n 's/^ID_SERIAL_SHORT=//p')
[[ $actual_serial == "$expected_serial" ]] || \
  die "target serial '$actual_serial' does not match '$expected_serial'"

online_source=$(findmnt -nr -o SOURCE --target /srv/backup) || \
  die "the online backup filesystem is not mounted"
online_uuid=$(lsblk -dnro UUID "$online_source")
[[ $online_uuid == "$expected_online_uuid" ]] || \
  die "the mounted online backup UUID is not the verified EXCERIA UUID"

while IFS= read -r device; do
  if findmnt -rn --source "$device" >/dev/null; then
    die "target device is mounted: $device"
  fi

  device_name=$(basename "$device")
  if [[ -d /sys/class/block/$device_name/holders ]] &&
    [[ -n $(ls -A "/sys/class/block/$device_name/holders") ]]; then
    die "target device has active holders: $device"
  fi
done < <(lsblk -nrpo NAME "$target_disk")

printf 'Verified destructive target:\n'
lsblk -o NAME,PATH,MODEL,SERIAL,TRAN,SIZE,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINTS "$target_disk"
printf '\nThis permanently erases every partition and all data on %s.\n' "$expected_by_id"
printf 'Type "ERASE %s" to continue: ' "$expected_serial"
IFS= read -r confirmation </dev/tty
[[ $confirmation == "ERASE $expected_serial" ]] || die "confirmation did not match"

printf '\nErasing partition metadata on %s...\n' "$target_disk"
wipefs --all --force "$target_disk"
sgdisk --zap-all "$target_disk"
sgdisk \
  --clear \
  --new=1:0:0 \
  --typecode=1:8300 \
  --change-name=1:"$filesystem_label" \
  "$target_disk"

blockdev --rereadpt "$target_disk"
udevadm settle

readonly target_partition="${target_disk}1"
for _ in {1..20}; do
  [[ -b $target_partition ]] && break
  sleep 0.25
done
[[ -b $target_partition ]] || die "new partition did not appear: $target_partition"

printf 'Creating ext4 filesystem labeled %s...\n' "$filesystem_label"
mkfs.ext4 -F -L "$filesystem_label" -m 0 "$target_partition"
sync
udevadm settle

printf '\nOffline backup disk initialized successfully and left unmounted:\n'
lsblk -o NAME,PATH,MODEL,SERIAL,TRAN,SIZE,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINTS "$target_disk"
