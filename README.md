# NixOS Configuration

Personal NixOS flake-based configuration for `nix-ai` (hostname) and `ecomex` (user).

Based on the [nix-starter-config](https://github.com/Misterio77/nix-starter-configs) standard template.

## System Overview

- **Active hosts**:
  - `nix-ai` — AI/desktop workstation (NixOS, x86_64-linux)
  - `nix-mac` — MacBook (nix-darwin, aarch64-darwin)
- **User**: `ecomex`
- **NixOS Version**: 26.05 (stable)
- **Kernel**: Stock (Linux)
- **Desktop**: Niri (scrollable-tiling Wayland compositor) + Noctalia shell
  > Note: `nix-ai` is currently running **headless** — the desktop modules
  > (Niri, Noctalia, greetd, etc.) are commented out in `configuration.nix`
  > and `home.nix`. Re-enable by uncommenting the import lines.
- **Display Manager**: greetd + tuigreet
- **Graphics**: NVIDIA with CUDA support
- **Shell**: Zsh
- **Networking**: NetworkManager

> `nix-server` is an inactive reference config (headless game streaming server). It is retained as a template but no machine currently runs it.

## Installation from NixOS Minimal Image

This guide assumes you are booting from a fresh [NixOS minimal ISO](https://nixos.org/download/#nixos-iso) and want to apply this flake to your machine. The process is broken into four phases: preparing the disk, installing the system, post-install configuration, and notes for different hardware.

### Phase 1: Boot the Minimal ISO

1. Download the NixOS minimal ISO and flash it to a USB stick:
   ```bash
   # Write ISO to USB (replace /dev/sdX with your USB device)
   sudo dd if=nixos-minimal-*.iso of=/dev/sdX bs=4M status=progress
   # or use balenaEtcher / Ventoy
   ```

2. Boot from the USB stick and log in as `root` (no password needed).

### Phase 2: Partition & Format the Disk

This config uses **LUKS-encrypted root** with a separate EFI partition. Adjust device names (`/dev/nvme0n1`) as needed for your hardware.

```bash
# Identify your target disk
lsblk

# Create partitions (UEFI/GPT)
# 1. EFI: 1 GB, ESP flag
# 2. Root: rest of disk, LUKS
parted /dev/nvme0n1 -- mklabel gpt
parted /dev/nvme0n1 -- mkpart primary 1GB 2GB        # EFI
parted /dev/nvme0n1 -- set 1 esp on
parted /dev/nvme0n1 -- mkpart primary 2GB 100%       # Root

# Format EFI partition
mkfs.fat -F32 /dev/nvme0n1p1

# Create LUKS-encrypted root partition
cryptsetup luksFormat /dev/nvme0n1p2
cryptsetup open /dev/nvme0n1p2 luks-root

# Format the decrypted root
mkfs.ext4 /dev/mapper/luks-root
```

### Phase 3: Mount & Install

```bash
# Mount the root partition
mount /dev/mapper/luks-root /mnt

# Mount the EFI partition
mkdir -p /mnt/boot
mount /dev/nvme0n1p1 /mnt/boot

# Generate initial hardware configuration
nixos-generate-config --root /mnt
# → This creates /mnt/etc/nixos/hardware-configuration.nix
#   You will need this file later (it contains UUIDs for your disk)

# Clone this flake repo (replace with your repo URL)
nix-shell -p git --run "git clone https://github.com/<your-username>/nix-configs.git /mnt/etc/nixos"

# OR: if installing from a local copy, copy your config to /mnt/etc/nixos
# cp -r /path/to/nix-configs/* /mnt/etc/nixos/

# Copy the generated hardware-configuration into the flake
cp /mnt/etc/nixos/hardware-configuration.nix /mnt/etc/nixos/hosts/nix-ai/hardware-configuration.nix
# (Review the copied file — it should match the structure of the existing
#  hosts/nix-ai/hardware-configuration.nix: LUKS device, boot partition,
#  kernel modules, CPU microcode)

# Stage all files for git (flakes only see tracked files)
cd /mnt/etc/nixos
git add -A

# Create the password hash file (outside the repo — not visible in git)
mkdir -p /mnt/etc/nixos-secrets
nix-shell -p mkpasswd --run "mkpasswd -m yescrypt" | tee /mnt/etc/nixos-secrets/ecomex
chmod 600 /mnt/etc/nixos-secrets/ecomex

# Install the system
nixos-install --flake .#nix-ai
# → No password prompt during install — the hash is read from the file above
```

### Phase 4: Post-Install

```bash
# Reboot into the new system
reboot

# After reboot, log in via greetd (tuigreet) with your password
# Niri starts automatically

# To apply future configuration changes:
sudo nixos-rebuild switch --flake .#nix-ai

# To update home-manager (runs as NixOS module, applied with the above)
# — no separate home-manager command needed
```

### Notes for Reinstallation on Different Hardware

- The `hardware-configuration.nix` is machine-specific (disk UUIDs, kernel modules). Always regenerate it with `nixos-generate-config` on the new machine.
- The `configuration.nix` in `hosts/nix-ai/` contains machine-specific settings like networking (static IP `10.20.50.20/24` on `enp42s0`, gateway `10.20.50.1`), TPM2 LUKS enrollment, and Bluetooth. Adjust these for your hardware.
- TPM2 auto-unlock for LUKS can be enrolled after install:
  ```bash
  sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 /dev/disk/by-uuid/<your-luks-uuid>
  ```

## Installation on macOS (nix-darwin)

This guide sets up the `nix-mac` host (Apple Silicon, `aarch64-darwin`) from
a fresh macOS install. The flake exposes `darwinConfigurations.nix-mac` in
`flake.nix`; home-manager runs as a darwin module, so a single
`darwin-rebuild switch` applies both system and user config.

### Step 1: Install Nix

Use the Determinate installer (brings flakes + nix-command out of the box
and is more robust on macOS than the official installer):

```bash
curl --proto '=https' --tlsv1.2 -fsSL https://install.determinate.systems/nix \
  | sh -s -- install

# Reload shell, then verify:
nix --version
nix run nixpkgs#hello   # should print "Hello, world!"
```

### Step 2: Clone the repo & stage files

```bash
git clone https://github.com/<your-username>/nix-configs.git ~/Code/nix-configs
cd ~/Code/nix-configs

# Flakes only see git-tracked files — always stage before building.
git add -A
```

### Step 3: Homebrew (optional but expected by `nix-mac`)

`hosts/nix-mac/configuration.nix` enables `homebrew` with Casks. If you
don't have Homebrew yet:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

If you don't want Homebrew, comment out the `homebrew` block in
`hosts/nix-mac/configuration.nix` before the first switch — otherwise
activation will fail.

### Step 4: Make sure the user exists

`nix-mac` references `users.users.ecomex` and
`home-manager.users.ecomex` (in `flake.nix`). The macOS account must
already exist under **System Settings → Users & Groups** — nix-darwin
only manages the shell/groups, it does not create the user. Adjust the
names in `hosts/nix-mac/configuration.nix` and `flake.nix` if yours differ.

### Step 5: First build (do not switch yet)

```bash
nix build .#darwinConfigurations.nix-mac.system
```

This pulls all flake inputs and compiles. Common failures at this stage:
- *`does not provide attribute ...`* → files not `git add`-ed.
- *Homebrew errors* → see Step 3.

### Step 6: First activation

```bash
# darwin-rebuild is inside the result symlink:
./result/sw/bin/darwin-rebuild switch --flake .#nix-mac
```

The first switch installs the nix-darwin profile (`~/.nix-profile`,
`/etc/nix-darwin`) and activates the configuration. You may be prompted
once to allow changes to your `~/.zshrc` / `~/.zprofile` — answer `y`.
After the first successful switch, `darwin-rebuild` is on your PATH via
the Nix profile and you can use the short form:

```bash
darwin-rebuild switch --flake .#nix-mac
```

### Step 7: Apply future changes

```bash
cd ~/Code/nix-configs
git add -A   # mandatory — flakes ignore untracked files
darwin-rebuild switch --flake .#nix-mac
```

### Test without switching

```bash
darwin-rebuild build --flake .#nix-mac   # build only
darwin-rebuild check  --flake .#nix-mac  # non-persistent activation check
```

### Notes specific to `nix-mac`

- **Home-manager is a darwin module** (`flake.nix` wires
  `home-manager.darwinModules.home-manager`), so do **not** run
  `home-manager switch` — `darwin-rebuild switch` covers both.
- **`additions` overlay is Linux-only** (it pulls `wolow-companion` and
  other Linux packages), so `nix-mac` only applies `modifications` and
  `unstable-packages` (`hosts/nix-mac/configuration.nix`).
- **State version is 6** (nix-darwin-specific, not 26.05). Do not change
  after first activation.
- **Channels are disabled** (`channel.enable = false`); the flake
  registry and `nixPath` are derived from flake inputs. Do not add
  channel-based config.
- **Cachix**: `nix-community.cachix.org` is already pinned as a
  substituter in `hosts/nix-mac/configuration.nix`, saving build time for
  home-manager dependencies.
- **Login shell**: nix-darwin only changes the login shell after a
  re-login. Log out and back in if `zsh` is not active after the switch.

### Reinstalling / moving to a new Mac

- The `nix-mac` config is not hardware-specific (no
  `hardware-configuration.nix` equivalent on macOS), so the same flake can
  be applied to a different Mac without regeneration. Just repeat
  Steps 1, 2, and 6 on the new machine.
- macOS system defaults set via `system.defaults` are applied
  idempotently; manual changes in System Settings may be overwritten on
  the next `darwin-rebuild switch`.

## Quick Start

### System Configuration (nix-ai)

home-manager runs as a NixOS module — a single rebuild applies both system and user config:

```bash
# Apply system + home-manager configuration
sudo nixos-rebuild switch --flake .#nix-ai

# Test without switching
sudo nixos-rebuild test --flake .#nix-ai

# Build without activating
sudo nixos-rebuild build --flake .#nix-ai
```

### System Configuration (nix-mac, macOS)

home-manager runs as a darwin module — `darwin-rebuild switch` applies both:

```bash
# Apply system + home-manager configuration
darwin-rebuild switch --flake .#nix-mac

# Build without activating
darwin-rebuild build --flake .#nix-mac

# Non-persistent activation check
darwin-rebuild check --flake .#nix-mac
```

### Flake Management

```bash
# Update all flake inputs
nix flake update

# Format all Nix files using alejandra
nix fmt

# Build custom packages
nix build .#package-name

# Enter shell with custom package
nix shell .#package-name
```

## Repository Structure

```
.
├── flake.nix              # Main flake configuration
├── flake.lock             # Dependency lock file
├── hosts/                 # Per-host configurations
│   ├── nix-ai/            # AI/desktop workstation (active, NixOS)
│   │   ├── configuration.nix
│   │   └── hardware-configuration.nix
│   ├── nix-mac/           # MacBook (active, nix-darwin)
│   │   └── configuration.nix
│   └── nix-server/        # Headless game streaming server (inactive/reference)
│       ├── configuration.nix
│       ├── hardware-configuration.nix
│       └── monitor.nix
├── home-manager/          # Home-manager user configurations
│   └── home.nix           # Main home config for ecomex
├── modules/               # Reusable modules
│   ├── nixos/             # System-level modules
│   └── home-manager/      # User-level modules
├── overlays/              # Package overlays and modifications
├── pkgs/                  # Custom package definitions
├── wallpapers/            # Wallpapers for Noctalia auto-rotation
```

## Module System

### NixOS Modules (`modules/nixos/`)

Imported via `inputs.self.nixosModules.<name>` in `configuration.nix`:

- `boot` — Bootloader and kernel configuration
- `comfyui` — ComfyUI AI image generation (CUDA, systemd service)
- `core-packages` — Essential system packages
- `docker` — Docker with auto-pruning
- `gaming` — Gaming packages and settings
- `greetd` — Lightweight login manager (tuigreet)
- `latex` — Full TeX Live installation
- `llama-swap` — LLM request router
- `locale` — Localization settings
- `nh` — `nh` NixOS helper
- `niri` — Niri Wayland compositor (greetd session)
- `nvidia` — NVIDIA drivers and CUDA
- `ollama` — Ollama LLM service
- `pipewire` — Audio
- `ssh` — SSH daemon
- `sunshine` — Game streaming server
- `tailscale` — VPN networking

### Home-Manager Modules (`modules/home-manager/`)

Imported via `inputs.self.homeManagerModules.<name>` in `home.nix`:

- `bat` — Better `cat` with syntax highlighting
- `bottom` — System resource monitor
- `default-apps` — Default MIME application associations
- `eza` — Modern `ls` replacement
- `fastfetch` — System information tool
- `fzf` — Fuzzy finder
- `git` — Git configuration
- `huggingface-cli` — Hugging Face CLI
- `kitty` — Terminal emulator
- `nextcloud-client` — Nextcloud desktop client
- `niri` — Niri user config (display, keybindings, layout)
- `noctalia` — Noctalia desktop shell
- `opencode` — OpenCode CLI tool
- `pi-coding-agent` — Pi coding agent
- `spotify` — Spotify client
- `telegram` — Telegram client
- `starship` — Shell prompt
- `thunderbird` — Email client
- `tmux` — Terminal multiplexer
- `vesktop` — Discord (Vencord)
- `vscode` — VS Code
- `zen-browser` — Privacy-focused Firefox fork
- `zsh` — Zsh configuration

## Overlay System

Three overlays are defined in `overlays/default.nix`:

1. **additions** — Makes custom packages from `pkgs/` available
2. **modifications** — Allows overriding existing nixpkgs packages
3. **unstable-packages** — Provides `pkgs.unstable.<package>` from nixpkgs-unstable

Overlays are applied via `home-manager.useGlobalPkgs = true`, so both NixOS and home-manager share the same package set.

## Flake Inputs

| Input | Channel | Purpose |
|---|---|---|
| nixpkgs | nixos-26.05 | Main package set |
| nixpkgs-unstable | nixos-unstable | Unstable packages overlay |
| home-manager | release-26.05 | User environment management |
| niri-flake | — | Niri Wayland compositor |
| noctalia-shell | — | Wayland desktop shell |
| zen-browser | — | Zen Browser |
| comfyui-nix | — | ComfyUI AI image generation (CUDA) |

## Adding Components

### Adding a NixOS Module

1. Create `modules/nixos/new-module.nix`
2. Register in `modules/nixos/default.nix`:
   ```nix
   new-module = import ./new-module.nix;
   ```
3. Import in `hosts/nix-ai/configuration.nix`:
   ```nix
   inputs.self.nixosModules.new-module
   ```

### Adding a Home-Manager Module

1. Create `modules/home-manager/new-module.nix`
2. Register in `modules/home-manager/default.nix`:
   ```nix
   new-module = import ./new-module.nix;
   ```
3. Import in `home-manager/home.nix`:
   ```nix
   inputs.self.homeManagerModules.new-module
   ```

### Adding Custom Packages

1. Create `pkgs/package-name/default.nix`
2. Register in `pkgs/default.nix`:
   ```nix
   package-name = pkgs.callPackage ./package-name { };
   ```
3. Package is then available via overlays in all configurations.

## ComfyUI

ComfyUI runs as a systemd service via the [comfyui-nix](https://github.com/utensils/comfyui-nix) flake. It uses CUDA for NVIDIA GPU acceleration.

```bash
# Start/restart the service
sudo systemctl restart comfyui

# Check status
systemctl status comfyui

# Access the web UI
# http://localhost:8188
```

- **Data directory**: `/var/lib/comfyui` (models, output, custom nodes)
- **Config**: `modules/nixos/comfyui.nix`
- **ComfyUI Manager**: enabled (`--enable-manager`)
- **Binary cache**: `comfyui.cachix.org` and `nix-community.cachix.org` configured

To add custom nodes declaratively, use the `customNodes` option in `modules/nixos/comfyui.nix`. Manager-installed nodes go to `/var/lib/comfyui/custom_nodes/` and their pip dependencies to `/var/lib/comfyui/.venv/`.

## Important Notes

- **Git staging required**: Nix flakes only see tracked files — run `git add` before building.
- **Flake lock**: Dependencies are pinned in `flake.lock`. Run `nix flake update` to update.
- **State version**: 26.05 — do not change after initial installation.
- **Unfree packages**: Enabled globally.
- **Experimental features**: Flakes and nix-command enabled system-wide.

## Resources

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [Nix Package Search](https://search.nixos.org/packages)
- [NixOS Wiki](https://wiki.nixos.org/)

## Credits

Based on [nix-starter-config](https://github.com/Misterio77/nix-starter-configs) by Misterio77.
