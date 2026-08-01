# Homelab backups

This document is the operating and restore runbook for the permanent backups
of `hl01` through `hl03`. The NixOS implementation lives in
`modules/nixos/homelab-backup.nix`; the append-only target and its maintenance
jobs live in `modules/nixos/restic-target.nix`.

## Design and recovery objectives

- Every host writes to its own encrypted Restic repository on the external
  EXCERIA filesystem mounted at `/srv/backup` on `hl03`.
- Clients reach the target through `rest-server` on `10.20.50.13:8000`.
  Client access is append-only: a compromised client can add snapshots but
  cannot delete or rewrite existing backup data.
- Retention and integrity checks run locally on `hl03`, outside the
  append-only client interface.
- The target filesystem is separate from every host's system and application
  SSDs. It is not off-site, however. A second encrypted copy at another
  location remains the next resilience improvement; the planned removable
  mirror is described below.
- The intended recovery point is at most 24 hours old. Recovery is manual;
  the required time depends mainly on the amount of Immich and Nextcloud data.
- HAOS is deliberately excluded because Home Assistant is rebuilt as a fresh
  VM. NAS/Samba data is not in scope yet.

Restic encrypts repository contents before transmission. Its repository
password and the REST credentials are stored only in the SOPS-encrypted
`secrets/restic.yaml`. Recovery therefore also requires the admin age key (or
one of the host SSH keys listed as SOPS recipients). Keep an independent copy
of the admin age key outside the homelab.

## Schedule and contents

Timers are persistent, so a missed run starts after the host comes back. Each
daily timer adds a random delay of up to ten minutes.

| Host | Daily start | Consistent application state | File data |
| --- | --- | --- | --- |
| `hl01` | 02:15 | PostgreSQL cluster dump; SQLite online backups for Haushaltsbuch and Open WebUI | Immich uploads, Paperless data/media/consume, Hermes, Haushaltsbuch and Open WebUI state |
| `hl02` | 03:15 | Native Vaultwarden backup plus SQLite integrity check | Vaultwarden, AdGuard Home, Stirling-PDF and Traefik state |
| `hl03` | 04:15 | Nextcloud maintenance mode; MariaDB and PostgreSQL cluster dumps | Complete Nextcloud home/data directory |

Every repository also contains `/etc/nixos-secrets`, `/etc/ssh`, the Tailscale
state and `/var/lib/homelab-backup`, where the consistent database exports are
staged. Regenerable caches such as Hermes' cache and Open WebUI model caches
are excluded.

Retention runs on `hl03` every Sunday at 06:00 and keeps seven daily, five
weekly and six monthly snapshots. The same job prunes unused data and reads a
10% sample of every repository. On the first Sunday of each month at 08:00 a
full read of all repository data verifies the backup medium.

## Operations

Inspect timers and recent results on a host:

```bash
systemctl list-timers 'restic-*'
systemctl status restic-backups-$(hostname).service
journalctl -u restic-backups-$(hostname).service --since yesterday
```

Start a backup manually and inspect snapshots:

```bash
sudo systemctl start restic-backups-$(hostname).service
sudo restic-$(hostname) snapshots
```

On `hl03`, inspect target maintenance and available space:

```bash
systemctl status restic-rest-server.service
systemctl list-timers restic-maintenance.timer restic-full-check.timer
df -h /srv/backup
sudo systemctl start restic-maintenance.service
```

A failed preparation step prevents a snapshot from being written. On `hl03`,
the post-stop hook returns Nextcloud to its previous maintenance state even if
Restic itself fails. Do not delete the independent encrypted migration exports
until the permanent backup has several verified generations and an off-site
copy exists.

## Restore verification

Never restore directly over live data as a first test. Restore to a temporary
directory, inspect it, and remove that directory only after the check:

```bash
sudo install -d -m 0700 /var/tmp/restic-restore-test
sudo restic-$(hostname) restore latest \
  --target /var/tmp/restic-restore-test
sudo find /var/tmp/restic-restore-test -xdev -maxdepth 3 -type f | head
```

Useful integrity checks on the restored exports include:

```bash
# hl01 (sqlite3 is installed on this host)
sudo sqlite3 /var/tmp/restic-restore-test/var/lib/homelab-backup/haushaltsbuch.sqlite \
  'PRAGMA quick_check;'
sudo test -s /var/tmp/restic-restore-test/var/lib/homelab-backup/postgresql/cluster.sql

# hl02: compare immediately after a backup; its preparation already ran
# SQLite quick_check on the source database.
sudo sha256sum /var/backup/vaultwarden/db.sqlite3 \
  /var/tmp/restic-restore-test/var/backup/vaultwarden/db.sqlite3

# hl03
sudo test -s /var/tmp/restic-restore-test/var/lib/homelab-backup/mariadb.sql
sudo test -s /var/tmp/restic-restore-test/var/lib/homelab-backup/postgresql/cluster.sql
```

Run this restore verification after the initial backup, after material changes
to the backup module, and at least quarterly. A successful `restic check` alone
proves repository integrity, not that an application-level restore works.

## Removable offline mirror

The second backup tier uses a USB HDD that normally remains unplugged and is
stored away from the homelab. The physical medium was commissioned and the
hot-plug automation implemented on 2026-08-01. It is an independent Restic
target rather than a destructive block-level or `rsync --delete` mirror.
`restic copy` transfers valid snapshots without propagating deletions from the
online target.

The accepted offline medium is exactly:

- Seagate M3 Portable, 1,000,204,885,504 bytes, serial `NM15KS34`;
- `/dev/disk/by-id/usb-Seagate_M3_Portable_NM15KS34-0:0`;
- one ext4 partition labeled `HOMELAB_OFFLINE`;
- filesystem UUID `cc005762-01f1-4cbd-94af-a158819e3b80`.

It was left unmounted after formatting. The previous EFI/APFS partition table
was intentionally erased after model, serial, exact size, mount state and the
separate online EXCERIA UUID had all been checked.

The hot-plug workflow is:

1. A dedicated filesystem label and UUID identify the one accepted offline
   disk. No generic USB disk may trigger the job.
2. Inserting that disk activates a systemd unit on `hl03`, which mounts it at a
   private path and takes an exclusive lock so only one copy can run.
3. The unit copies new snapshots from all three local repositories into three
   independent repositories on the removable disk. Source and destination
   stay encrypted. New repositories copy the source chunker parameters so
   subsequent copies deduplicate consistently.
4. Restic reads and checks all destination data during commissioning. Later
   runs check repository metadata plus 10% of stored packs. A failure leaves
   the source untouched and does not report the disk as ready for removal.
5. On success the unit flushes all writes, records the completion time,
   unmounts the filesystem and powers down the USB device. Only then is the
   disk safe to unplug and return to storage.

The copy job, weekly prune and integrity checks share
`/run/lock/homelab-restic-target.lock`; only one can operate on the target at a
time. Offline snapshots are not forgotten or pruned. This intentionally keeps
snapshots that later disappear from the online repositories. A usage of 80%
or more is recorded as a warning and is the point to review retention manually.
No broad udev rule or automatic formatting exists.

The current state is written atomically to
`/var/lib/homelab-backup/offline-mirror.status`. Inspect a run with:

```bash
cat /var/lib/homelab-backup/offline-mirror.status
systemctl status restic-offline-mirror.service
journalctl -u restic-offline-mirror.service --since today
```

To start or retry while the verified disk is attached:

```bash
sudo systemctl reset-failed restic-offline-mirror.service
sudo systemctl start restic-offline-mirror.service
```

Only `state=success` together with `safe to unplug` means the unit completed,
unmounted the filesystem and powered off the USB device. On failure the unit
attempts to unmount but deliberately leaves the device powered so it can be
inspected and retried.

## Commissioning evidence (2026-08-01)

- `hl01` created snapshot `f495d13c`: 194,267 files, 38.840 GiB processed
  and 28.150 GiB stored. Streaming its PostgreSQL cluster dump back through
  `restic dump` produced the same SHA-256 as the staged source dump.
- `hl02` created snapshot `a30bb561`: 323 files, 38.866 MiB processed and
  8.359 MiB stored. A real restore of the Vaultwarden SQLite backup produced
  the same SHA-256 as the source backup.
- `hl03` created snapshot `c1846fa1`: 26,311 files, 4.482 GiB processed and
  3.467 GiB stored. Nextcloud entered and left maintenance mode automatically;
  streaming the MariaDB dump back produced the same SHA-256 as its source.
- The first retention/prune run completed successfully and read a 10% sample
  of every repository. The subsequent full check read 31.5 GiB across all
  repositories and reported no errors.

## Disaster restore order

1. Reinstall the affected NixOS host from this flake and restore its SOPS/SSH
   recovery material.
2. Stop the applications that own the data being restored.
3. Restore the latest snapshot into a temporary directory and verify it.
4. Copy application files to their declared paths with the original ownership
   and permissions.
5. Restore databases from the staged exports: PostgreSQL with `psql`, MariaDB
   with `mariadb`, and SQLite from the online backup files. Restore file data
   and its matching database snapshot as one set.
6. Start the services, run their application-specific health checks and keep
   the old data until the functional test has passed.

For a total loss of `hl03`, attach the intact EXCERIA filesystem to a trusted
NixOS machine and use each repository directly from
`/srv/backup/restic/restic/<host>`. This bypasses the REST server but still
requires the repository password from SOPS.
