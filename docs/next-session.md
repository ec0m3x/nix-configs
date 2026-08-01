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
- At the final online check all backup timers were active and no host had a
  failed systemd unit.
- The four systems `hl01`, `hl02`, `hl03` and `nix-ai` were selected for a
  clean shutdown before rearranging the office. Verify their actual power and
  boot state at the start of the next session.
- Git `main` is clean and published. The durable backup implementation starts
  at commit `ffbf2b9`; the commissioning evidence and offline-mirror plan are
  included by commit `67c44c0`.

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

## Next project: removable offline backup disk

The requested workflow is: attach a second USB HDD, let `hl03` copy and verify
the backups automatically, wait until the disk is automatically unmounted and
powered down, then unplug it and store it in a cupboard.

Do not implement a generic USB rule or format anything before identifying the
real disk. With the new disk attached, begin with read-only inventory:

```bash
ssh hl03 'lsblk -o NAME,PATH,MODEL,SERIAL,SIZE,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINTS'
```

Record and decide:

- exact model, serial number, capacity and stable `/dev/disk/by-id` path;
- whether existing data must be preserved;
- filesystem, label and UUID (Restic already encrypts repository contents);
- offline retention policy;
- how completion should be signalled, for example an ntfy message in addition
  to the systemd journal.

The implementation should then:

1. Match only the verified UUID/device identity.
2. Mount the disk at a private path through systemd.
3. Take the same exclusive lock used by online prune and full-check jobs.
4. Use `restic copy` for the `hl01`, `hl02` and `hl03` repositories. Do not use
   a destructive `rsync --delete` mirror.
5. Check the destination repositories and report failure clearly.
6. On success, flush writes, record the completion time, unmount the filesystem
   and power down the USB device so it is explicitly safe to remove.
7. Test interrupted-copy recovery, a second incremental copy and an actual
   restore from the unplugged/offline repository before accepting the design.

NAS/Samba remains intentionally out of scope unless the user reopens that
decision. HAOS remains excluded from backups because it is rebuilt fresh.
