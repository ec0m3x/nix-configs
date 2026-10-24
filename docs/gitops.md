# GitOps deployment

`hl01` (10.20.50.11, 16 GiB RAM) is the replacement for the retired `nix-ai`
builder/controller. It polls public `main` every five minutes and deploys a
revision only after `flake-check` succeeds for that exact commit. CI evaluates
only the three remaining servers. The old workstation configuration is kept
for reference; it is neither built nor deployed by this workflow.

The controller:

1. verifies the identity and reachability of the remote targets;
2. builds `hl03`, `hl02` and `hl01` before changing any host;
3. activates `hl03` -> `hl02` -> `hl01`, with the controller activated locally;
4. stops if activation fails or a host has failed systemd units; and
5. records the revision only after every host is healthy.

The CI gate, fast-forward requirement and restricted activation wrapper are
unchanged. No GitHub token, Actions runner or inbound LAN connection is needed.
The dedicated private key `/home/ecomex/.ssh/id_ed25519_gitops` on hl01 copies
closures to hl02/hl03. Its public key is declared in `hosts/homelab/common.nix`.
The private key stays outside Git and the Nix store. The workstation's separate
`id_ed25519_homelab` public key is also declared for administrative access.

Builds use one job with two cores to leave resources for application services
and the HAOS VM. Existing binary caches are unchanged.

## One-time migration from nix-ai

A push alone cannot bootstrap the replacement for a missing controller. First
review, commit and push the migration to `main`, and wait for `flake-check` to
succeed. Then perform the following steps from the workstation. These require
working LAN access, verified host keys and the existing `ecomex` login/sudo
password (or another existing administrator SSH key).

The migration prepared the two key pairs under `~/.ssh` on the workstation.
Do not regenerate `id_ed25519_gitops` without updating its declared public key.
Never copy either private key into the repository.

```bash
# Allow workstation access using the existing server login/password.
for address in 10.20.50.11 10.20.50.12 10.20.50.13; do
  ssh-copy-id -i ~/.ssh/id_ed25519_homelab.pub "ecomex@$address"
done

# Copy only the dedicated deployment key pair to the replacement controller.
scp -i ~/.ssh/id_ed25519_homelab \
  ~/.ssh/id_ed25519_gitops ~/.ssh/id_ed25519_gitops.pub \
  ecomex@10.20.50.11:.ssh/

ssh -t -i ~/.ssh/id_ed25519_homelab ecomex@10.20.50.11
```

On **hl01**:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519_gitops
chmod 644 ~/.ssh/id_ed25519_gitops.pub

# Authorize the controller before the first deployment. Verify the displayed
# host-key fingerprints against a trusted source when first connecting.
for address in 10.20.50.12 10.20.50.13; do
  ssh-copy-id -i ~/.ssh/id_ed25519_gitops.pub "ecomex@$address"
done

# Check identity, noninteractive key login, and existing activation wrappers.
for entry in hl02:10.20.50.12 hl03:10.20.50.13; do
  ssh -i ~/.ssh/id_ed25519_gitops -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=yes -o BatchMode=yes "ecomex@${entry#*:}" \
    'hostname -s; test -x /run/current-system/sw/bin/homelab-gitops-activate'
done

# Use HTTPS: the deployment key deliberately has no GitHub account access.
# If no checkout exists:
git clone https://github.com/ec0m3x/nix-configs.git ~/nix-configs
cd ~/nix-configs
# For an existing checkout instead, preserve local changes before updating:
git remote set-url origin https://github.com/ec0m3x/nix-configs.git
git switch main
git pull --ff-only

# Build all three, then activate hl03, hl02 and finally hl01 locally.
# The script requires a clean main checkout matching origin/main.
./scripts/deploy-homelab.sh
```

The existing wrapper should already be present from the former GitOps setup.
The manual script can still bootstrap it if absent; the controller must not
run before the wrappers and SSH access are ready. Activating hl01 last installs
and starts `homelab-gitops.timer`. Its first run may deploy the revision again
to establish its local state. Private key and host trust are reused from the
manual deployment. `StrictHostKeyChecking=yes` remains enforced.

Verify on hl01:

```bash
systemctl status homelab-gitops.timer --no-pager
sudo systemctl start homelab-gitops.service
journalctl -u homelab-gitops.service -n 200 --no-pager
cat /var/lib/homelab-gitops/applied-revision
cat /var/lib/homelab-gitops-target/revision
for address in 10.20.50.12 10.20.50.13; do
  ssh -i ~/.ssh/id_ed25519_gitops -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=yes -o BatchMode=yes "ecomex@$address" \
    'cat /var/lib/homelab-gitops-target/revision; systemctl --failed --no-pager'
done
```

Do not copy the old `applied-revision` state from nix-ai: the new controller
must validate and deploy the migration once. Keep existing authorized keys
until access from the replacement is verified.

## Normal operation

Only `main` deploys; other branches are evaluated by CI without deployment:

```text
push -> flake-check -> hl01 builds all three hosts -> hl03 -> hl02 -> hl01
```

Useful status commands on hl01:

```bash
systemctl status homelab-gitops.service --no-pager
journalctl -u homelab-gitops.service --since today --no-pager
cat /var/lib/homelab-gitops/applied-revision
```

Pending CI is retried at the next timer run. Failed CI or a non-fast-forward
rewrite fails closed and is reported by `homelab-gitops.service`.

## Rollback

Use a normal Git revert, then push without rewriting `main`:

```bash
git revert <bad-commit>
git push origin main
```

After CI succeeds, the revert is built and deployed like any other commit.
If deployment stops partway, fix/revert the change and start the service again.
The revision is recorded only after the complete sequence; a retry safely
repeats every host. Successfully activated hosts are not automatically rolled
back merely because a later host fails, since migrations may be irreversible.

## Scope

Only `hl01`, `hl02` and `hl03` are deployed. `nix-mac` continues to use manual
`darwin-rebuild switch --flake .#nix-mac`. `nix-ai` is retired.
