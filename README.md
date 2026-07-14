# NixOS Configuration

Personal NixOS flake-based configuration for `nix-ai` (hostname) and `ecomex` (user).

Based on the [nix-starter-config](https://github.com/Misterio77/nix-starter-configs) standard template.

## System Overview

- **Active host**: `nix-ai` — AI/desktop workstation
- **User**: `ecomex`
- **NixOS Version**: 26.05 (stable)
- **Kernel**: Stock (Linux)
- **Desktop**: Niri (scrollable-tiling Wayland compositor) + Noctalia shell
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

# Install the system
nixos-install --flake .#nix-ai
# → You will be prompted to set a password for user 'ecomex'
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

## Quick Start

### System Configuration

home-manager runs as a NixOS module — a single rebuild applies both system and user config:

```bash
# Apply system + home-manager configuration
sudo nixos-rebuild switch --flake .#nix-ai

# Test without switching
sudo nixos-rebuild test --flake .#nix-ai

# Build without activating
sudo nixos-rebuild build --flake .#nix-ai
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
├── hosts/                 # Per-host NixOS configurations
│   ├── nix-ai/            # AI/desktop workstation (active)
│   │   ├── configuration.nix
│   │   └── hardware-configuration.nix
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
└── nix-shell/             # Development environment shells
    └── comfyUI/           # ComfyUI FHS environment
```

## Module System

### NixOS Modules (`modules/nixos/`)

Imported via `inputs.self.nixosModules.<name>` in `configuration.nix`:

- `boot` — Bootloader and kernel configuration
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

## Development Shells

```bash
cd nix-shell/comfyUI
nix-shell shell.nix
```

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
