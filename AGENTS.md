# AGENTS.md

Compact guidance for OpenCode sessions in this repo. Read this before editing.
For full background see `CLAUDE.md` and `README.md`; this file only captures what
those get wrong, omit, or where the live config has drifted.

## Current state (drifts from CLAUDE.md / README.md)

- **`nix-ai` is currently running HEADLESS.** All desktop modules
  (`niri`, `pipewire`, `greetd`, `gaming`, `latex`) are commented out in
  `hosts/nix-ai/configuration.nix`, and all desktop home-manager modules
  (`kitty`, `niri`, `noctalia`, `zen-browser`, `vscode`, `vesktop`,
  `spotify`, `telegram`, `thunderbird`, `nextcloud-client`, `default-apps`,
  `protonmail*`) are commented out in `home-manager/home.nix`. The desktop
  module files still exist and build — do not assume Niri/Plasma/Noctalia are
  active. Re-enable by uncommenting the import lines, not by editing the
  module files.
- **`nix-mac` exists** (`hosts/nix-mac/configuration.nix`), exported via
  `flake.nix` as `darwinConfigurations.nix-mac` (aarch64-darwin). Build with
  `darwin-rebuild switch --flake .#nix-mac`.
- **Home-manager runs as a NixOS module**, not standalone. A single
  `nixos-rebuild switch` applies both system and user config. `nix-ai` uses the
  headless workstation profile; `hl01`–`hl03` use the minimal shared server
  profile in `home-manager/home-homelab.nix`. Do **not** run
  `home-manager switch` — it is not wired up that way.
- Wolf game streaming is enabled on `nix-ai`; sunshine is commented out.
- **`nix-server` was removed** (2026-07-30). Do not resurrect it; `nix-ai`
  already imports every module it used.
- **The homelab migration is complete** (2026-08-01, branch `main`). The former
  Proxmox mini PCs now run bare-metal NixOS as `hl01`–`hl03` at
  `10.20.50.11`–`.13`; do not treat their files as scaffolding or resurrect
  Proxmox assumptions. `hl01` hosts the applications and a fresh HAOS VM,
  `hl02` provides DNS/proxy/Vaultwarden, and `hl03` hosts Nextcloud/LiteLLM and
  the Restic target. Read `docs/next-session.md` first for the concise current
  handover, `docs/homelab-backups.md` for backup/restore operations, and
  `docs/homelab-migration.md` for full history before touching `hosts/hl0*` or
  `hosts/homelab/`. The hosts share `hosts/homelab/common.nix` and do NOT have
  a `hardware-configuration.nix`; `nixpkgs.hostPlatform` is set in common.nix.
- **Permanent homelab backups are active.** Each host writes daily to its own
  encrypted append-only Restic repository on the external EXCERIA filesystem
  at `hl03:/srv/backup`. Retention/prune and integrity checks run locally on
  hl03. Database/SQLite preparation, actual restores and a full repository
  read were verified on 2026-08-01. HAOS and NAS/Samba are intentionally not
  backed up. Do not remove the encrypted migration exports until the planned
  removable offline copy has several verified generations.
- **The removable offline mirror is planned, not implemented.** When the real
  USB HDD is available, inventory it read-only and match only its verified
  UUID/device identity. The intended flow is `restic copy`, check, flush,
  unmount and USB power-off. Never add a generic hotplug/format rule or use a
  destructive `rsync --delete` mirror.

## Commands

```bash
# Apply system + home-manager (single command, nix-ai only)
sudo nixos-rebuild switch --flake .#nix-ai

# Test without switching
sudo nixos-rebuild test --flake .#nix-ai

# macOS host
darwin-rebuild switch --flake .#nix-mac

# Build a homelab host on nix-ai
ssh nix-ai 'cd /home/ecomex/nix-configs && nixos-rebuild build --flake .#hl01'

# Build and deploy all homelab hosts from nix-ai (one shared sudo prompt)
ssh -t nix-ai 'cd /home/ecomex/nix-configs && ./scripts/deploy-homelab.sh'

# Clean Nix generations older than seven days on nix-ai and hl01-hl03
ssh -t nix-ai 'cd /home/ecomex/nix-configs && ./scripts/cleanup-homelab.sh'

# Deploy a homelab host from nix-ai (run interactively for target sudo)
ssh -t nix-ai
cd /home/ecomex/nix-configs
nixos-rebuild switch --flake .#hl01 \
  --target-host ecomex@10.20.50.11 --ask-sudo-password

# Format (alejandra via nix fmt)
nix fmt

# Update flake inputs (updates flake.lock)
nix flake update

# Build a custom package from pkgs/
nix build .#package-name
```

There is no test suite, typecheck, or lint beyond `nix fmt`. Verify edits by
running `nixos-rebuild build --flake .#nix-ai` (or `test`). On hosts without
nix (e.g. the Windows workstation), push and let CI validate: GitHub Actions
(`.github/workflows/check.yml`) evaluates every NixOS host config on push.
For homelab changes, build every affected `hl0*` configuration on `nix-ai`.
When a change rotates Restic server credentials or alters the target, deploy
`hl03` before the clients and verify the target before starting backups.

## Hard constraints

- **Git staging is mandatory before any build.** Nix flakes only see files
  tracked by git. Always `git add` new/changed files before `nixos-rebuild`
  or `nix build`, or the change is silently ignored.
- **State version is 26.05** for both NixOS and home-manager. Never change.
- **Unfree packages** are enabled globally; do not gate them.
- **Flakes + nix-command** are enabled system-wide via `configuration.nix`.
- **User password** is read from `/etc/nixos-secrets/ecomex` (outside the
  repo, mode 600), generated with `mkpasswd -m yescrypt`. Do not inline a
  hash. The hl hosts use the same pattern (file injected at install time via
  nixos-anywhere `--extra-files`).
- **Secrets for hl hosts** go through sops-nix: encrypted files under
  `secrets/`, recipients in `.sops.yaml` (admin age key + per-host SSH host
  keys via ssh-to-age). Never commit plaintext secrets.
- **LUKS root** with TPM2 auto-unlock (PCRs 0+7) is configured in
  `hosts/nix-ai/configuration.nix`. Re-enroll on hardware change with
  `sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 /dev/disk/by-uuid/<uuid>`.

## Module registration (two-step, easy to forget)

Adding a NixOS module:
1. Create `modules/nixos/<name>.nix`
2. Register in `modules/nixos/default.nix`: `<name> = import ./<name>.nix;`
3. Import in `hosts/<host>/configuration.nix`: `inputs.self.nixosModules.<name>`

Home-manager is the same pattern: `modules/home-manager/<name>.nix` →
`modules/home-manager/default.nix` → import in the appropriate profile under
`home-manager/`.

A file in `modules/.../` that is not registered in `default.nix` is invisible
to the flake. Step 2 is the most commonly missed.

## Networking on nix-ai

- Static IPv4 `10.20.50.20/24`, gateway `10.20.50.1`, DNS `10.20.50.1` and
  `8.8.8.8`, on interface `enp42s0`, via NetworkManager `ensureProfiles`.
- Wake-on-LAN enabled on `enp42s0`.
- `wolow-companion` service runs for remote power via the Wolow mobile app.

## Binary caches (do not remove)

`configuration.nix` pins `niri.cachix.org`, `comfyui.cachix.org`, and
`nix-community.cachix.org` with trusted public keys. Removing these forces
long source builds of niri / comfyui / home-manager dependencies.

## Custom packages

- `pkgs/<name>/default.nix` + register in `pkgs/default.nix` as
  `<name> = pkgs.callPackage ./<name> { };`.
- Exposed via the `additions` overlay in `overlays/default.nix`; both NixOS
  and home-manager pick them up through `home-manager.useGlobalPkgs = true`.
- `pkgs.unstable.<pkg>` accesses nixpkgs-unstable via the `unstable-packages`
  overlay.

## ComfyUI

Runs as a systemd service (comfyui-nix flake, CUDA). Data dir
`/var/lib/comfyui`; web UI `http://localhost:8188`. Config in
`modules/nixos/comfyui.nix`. Manager-installed custom nodes live in
`/var/lib/comfyui/custom_nodes/`, pip deps in `/var/lib/comfyui/.venv/`.

## Conventions that differ from defaults

- Nix channel disabled (`nix.channel.enable = false`); flake registry and
  `nixPath` are derived from flake inputs. Do not add channel-based config.
- `programs.nix-ld.enable = true` for VSCode remote server / dynamic
  linking — keep it.
- Comments in this repo are in English and German mixed. Match the
  surrounding file; do not translate existing comments.
- When disabling rather than removing a module, comment out the import line
  in `configuration.nix` / `home.nix` (the existing pattern). Keep the
  module file intact so it can be re-enabled.
