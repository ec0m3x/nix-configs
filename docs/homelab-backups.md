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
  location remains the next resilience improvement.
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
# hl01
sudo sqlite3 /var/tmp/restic-restore-test/var/lib/homelab-backup/haushaltsbuch.sqlite \
  'PRAGMA quick_check;'
sudo test -s /var/tmp/restic-restore-test/var/lib/homelab-backup/postgresql/cluster.sql

# hl02
sudo sqlite3 /var/tmp/restic-restore-test/var/backup/vaultwarden/db.sqlite3 \
  'PRAGMA quick_check;'

# hl03
sudo test -s /var/tmp/restic-restore-test/var/lib/homelab-backup/mariadb.sql
sudo test -s /var/tmp/restic-restore-test/var/lib/homelab-backup/postgresql/cluster.sql
```

Run this restore verification after the initial backup, after material changes
to the backup module, and at least quarterly. A successful `restic check` alone
proves repository integrity, not that an application-level restore works.

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
