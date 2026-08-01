# Next session handover

Last updated: 2026-08-01

## Current state

- The Proxmox-to-NixOS migration is complete. `hl01`, `hl02` and `hl03` run
  their production workloads on bare-metal NixOS; `nix-ai` remains the remote
  build host.
- The permanent Restic backup strategy is deployed on all three homelab hosts.
  Clients write to separate append-only repositories on the external EXCERIA
  filesystem mounted at `/srv/backup` on `hl03`.
- Initial snapshots and real restore reads succeeded:
  - `hl01`: snapshot `f495d13c`, 38.840 GiB processed, PostgreSQL dump streamed
    back with an identical SHA-256.
  - `hl02`: snapshot `a30bb561`, Vaultwarden SQLite database restored with an
    identical SHA-256.
  - `hl03`: snapshot `c1846fa1`, 4.482 GiB processed, MariaDB dump streamed
    back with an identical SHA-256. Nextcloud maintenance mode was entered and
    left automatically.
- The first retention/prune job and its 10% data check succeeded. The first
  full check subsequently read 31.5 GiB from all repositories and reported no
  errors.
- The removable offline mirror is deployed and its normal workflow is
  verified. The initial run copied all three repositories, read every copied
  pack without errors, unmounted the Seagate disk and powered it off. A second
  physical unplug/replug triggered the job through udev without a command,
  reused the existing repositories, completed the configured 10% checks and
  powered the disk off again. The status reported 4% usage and `safe to
  unplug` after both runs.
- At the final online check all backup timers were active and no host had a
  failed systemd unit.
- The four systems `hl01`, `hl02`, `hl03` and `nix-ai` were selected for a
  clean shutdown before rearranging the office. Verify their actual power and
  boot state at the start of the next session.
- Git `main` is published. The durable backup implementation starts at commit
  `ffbf2b9`; the removable hotplug mirror was implemented by commit `5c2bd79`.
- The first boot after the office rearrangement exposed two ordering/retry
  issues. Both fixes were built, deployed and verified: on `hl03`,
  `restic-target-prepare` now explicitly waits for the EXCERIA mount; on
  `hl02`, Traefik waits up to 300 seconds per attempt and retries without a
  start limit while a delayed repeater prevents the Tailscale address from
  appearing. There are no pending configuration deployments.

The complete operating and restore runbook is
[`homelab-backups.md`](homelab-backups.md). Do not remove the encrypted
migration exports yet; keep them until the removable offline copy has several
verified generations.

## Start of the next session

1. Boot the machines needed for the work. Bring up `hl03` before starting or
   manually triggering client backups, because it owns the Restic target.
   After `nix-ai` is back, fast-forward its checkout because the final handover
   commit was created on the Mac after the shutdown sequence:

   ```bash
   ssh nix-ai 'cd /home/ecomex/nix-configs && git pull --ff-only'
   ```

2. Verify every host before making changes:

   ```bash
   for host in hl01 hl02 hl03; do
     ssh "$host" 'systemctl --failed --no-pager; systemctl list-timers --all --no-pager "restic-*"'
   done
   ```

3. Check the target on `hl03`:

   ```bash
   ssh hl03 'findmnt /srv/backup; systemctl is-active restic-rest-server.service'
   ```

4. Note that the daily Restic timers use `Persistent=true`. If a scheduled run
   was missed while the machines were off, systemd may start it shortly after
   boot. Inspect `systemctl status restic-backups-$(hostname).service` before
   starting another backup manually.

## Current project: removable offline backup disk

The requested workflow is: attach a second USB HDD, let `hl03` copy and verify
the backups automatically, wait until the disk is automatically unmounted and
powered down, then unplug it and store it in a cupboard.

The real disk was inventoried read-only and intentionally reformatted on
2026-08-01. It is the 1 TB Seagate M3 Portable with serial `NM15KS34`, exact
size 1,000,204,885,504 bytes and stable path
`/dev/disk/by-id/usb-Seagate_M3_Portable_NM15KS34-0:0`. It now contains one
unmounted ext4 filesystem labeled `HOMELAB_OFFLINE` with UUID
`cc005762-01f1-4cbd-94af-a158819e3b80`. The previous EFI/APFS layout was
explicitly accepted for deletion. The declarative hotplug job accepts only
this serial plus filesystem UUID, uses independent Restic repositories without
offline pruning, warns at 80%, records status locally and powers the device off
after a successful copy and check.

The implementation does the following:

1. Match only the verified UUID/device identity.
2. Mount the disk at a private path through systemd.
3. Take the same exclusive lock used by online prune and full-check jobs.
4. Use `restic copy` for the `hl01`, `hl02` and `hl03` repositories. Do not use
   a destructive `rsync --delete` mirror.
5. Check the destination repositories and report failure clearly.
6. On success, flush writes, record the completion time, unmount the filesystem
   and power down the USB device so it is explicitly safe to remove.
7. The initial full copy and a second automatic incremental run are verified.
   An interrupted-copy recovery drill and an actual restore from the removable
   repository remain useful future resilience tests; they are not required for
   normal operation.

NAS/Samba remains intentionally out of scope unless the user reopens that
decision. HAOS remains excluded from backups because it is rebuilt fresh.
