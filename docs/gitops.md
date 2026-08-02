# GitOps deployment

`nix-ai` polls the public `main` branch every five minutes and deploys a new
revision only after the `flake-check` GitHub Actions workflow has completed
successfully for that exact commit.

The controller then:

1. verifies the identity and reachability of every remote target;
2. builds `hl03`, `hl02`, `hl01` and `nix-ai` before changing any host;
3. deploys in the order `hl03` -> `hl02` -> `hl01` -> `nix-ai`;
4. stops immediately if an activation fails or a host has a failed systemd
   unit; and
5. records the revision only after every host is healthy.

This is a pull-based workflow. It needs no GitHub token, self-hosted Actions
runner or inbound connection to the LAN. The existing `ecomex` SSH key on
`nix-ai` copies closures to the homelab hosts. Passwordless sudo is limited to
`/run/current-system/sw/bin/homelab-gitops-activate`; that wrapper accepts only
an immutable Nix store system closure whose hostname matches the target.

## One-time bootstrap

The activation wrapper must exist on all targets before the controller starts.
After committing and pushing the GitOps change, wait for `flake-check`, then run
the existing manual deployment on `nix-ai` first and enable the controller
last:

```bash
ssh -t nix-ai
cd /home/ecomex/nix-configs
git pull --ff-only
./scripts/deploy-homelab.sh
sudo nixos-rebuild switch --flake .#nix-ai
```

The last command installs and starts `homelab-gitops.timer`. Its first run may
deploy the current revision once more; this is harmless and establishes the
controller's local revision state.

Verify the installation:

```bash
systemctl status homelab-gitops.timer --no-pager
systemctl list-timers homelab-gitops.timer --no-pager
sudo systemctl start homelab-gitops.service
journalctl -u homelab-gitops.service -n 200 --no-pager

for host in hl01 hl02 hl03; do
  ssh "$host" 'cat /var/lib/homelab-gitops-target/revision'
done
cat /var/lib/homelab-gitops-target/revision
```

`StrictHostKeyChecking=yes` is intentional. The normal manual deployment must
have populated `/home/ecomex/.ssh/known_hosts` on `nix-ai`; a changed host key
causes deployment to fail closed.

## Normal operation

A push to a branch other than `main` is evaluated by CI but never deployed. A
push to `main` follows this path:

```text
push -> flake-check -> controller builds all hosts -> staggered activation
```

Useful status commands on `nix-ai`:

```bash
systemctl status homelab-gitops.service --no-pager
journalctl -u homelab-gitops.service --since today --no-pager
cat /var/lib/homelab-gitops/applied-revision
```

If CI is pending, the service exits successfully and retries on the next timer
run. Failed CI or a non-fast-forward rewrite of `main` fails closed and is
visible as a failed `homelab-gitops.service`.

## Rollback

Use a normal Git revert so that `main` remains fast-forward-only:

```bash
git revert <bad-commit>
git push origin main
```

After CI succeeds, the revert is built and deployed like any other commit. Do
not force-push `main`; the controller deliberately rejects rewritten history.

If a deployment stops after only some hosts switched, fix or revert the commit
and start the service again. The controller records a revision only after the
complete sequence, so the next run safely retries all hosts. It does not
automatically roll back a successfully activated host merely because a later
host fails, since service or database migrations may not be reversible.

## Scope

The workflow manages the four NixOS configurations only. `nix-mac` remains a
manual `darwin-rebuild switch --flake .#nix-mac`, because the Mac may be asleep
or outside the LAN and cannot be built by the Linux controller.
