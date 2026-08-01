# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a NixOS flake-based configuration repository. It manages both system-wide NixOS configuration and user-level home-manager configuration for user `ecomex`.

- **`nix-ai`**: AI workstation (NixOS, x86_64-linux), currently headless. Its
  desktop imports remain commented out and are re-enabled by uncommenting the
  import lines.
- **`nix-mac`**: MacBook (nix-darwin, aarch64-darwin).
- **`hl01`–`hl03`**: bare-metal NixOS homelab hosts. The Proxmox migration is
  technically complete; read `docs/homelab-migration.md` before changing
  `hosts/hl0*` or `hosts/homelab/`. `hl01` also runs a declaratively
  provisioned Home Assistant OS VM via libvirt/KVM.

## Common Commands

### System Configuration
```bash
# Rebuild NixOS system configuration (applies system + home-manager)
sudo nixos-rebuild switch --flake .#nix-ai

# Test system configuration without switching
sudo nixos-rebuild test --flake .#nix-ai

# Build system configuration without activating
sudo nixos-rebuild build --flake .#nix-ai

# Build a homelab host on nix-ai
nixos-rebuild build --flake .#hl01

# Apply a homelab host remotely
nixos-rebuild switch --flake .#hl01 \
  --target-host ecomex@10.20.50.11 \
  --sudo --ask-sudo-password
```

### Home Manager Configuration

Home-manager is integrated as a NixOS or nix-darwin module. Do not run a
standalone `home-manager switch`; use the host's `nixos-rebuild` or
`darwin-rebuild` command.

### Flake Management
```bash
# Update all flake inputs (nixpkgs, home-manager, etc.)
nix flake update

# Format all Nix files using alejandra
nix fmt

# Build custom packages
nix build .#package-name

# Enter shell with custom package
nix shell .#package-name
```

### Development Shells
```bash
# Enter ComfyUI FHS environment
cd nix-shell/comfyUI
nix-shell shell.nix
```

## Architecture

### Flake Structure

The `flake.nix` file is the entry point that defines:
- **Inputs**:
  - nixpkgs (26.05 stable) and nixpkgs-unstable
  - home-manager (release-26.05, for user configuration)
  - niri-flake (scrollable-tiling Wayland compositor)
  - noctalia-shell (desktop shell for Wayland)
  - zen-browser (privacy-focused Firefox fork)
- **Outputs**: NixOS configurations, the nix-darwin configuration, custom
  packages, overlays, and reusable modules
- **Systems**: `nix-ai`, `hl01`, `hl02`, and `hl03` (NixOS) plus `nix-mac`
  (nix-darwin); home-manager is integrated for the workstation/Mac user

### Directory Layout

```
.
├── flake.nix              # Main flake configuration
├── hosts/                 # Per-host NixOS configurations
│   ├── nix-ai/            # AI workstation (currently headless)
│   │   ├── configuration.nix
│   │   └── hardware-configuration.nix
│   ├── nix-mac/           # MacBook (nix-darwin)
│   │   └── configuration.nix
│   ├── homelab/           # Shared hl01-hl03 base configuration
│   ├── hl01/              # Application host + disko layout
│   ├── hl02/              # DNS/proxy host + disko layout
│   └── hl03/              # Cloud/data host + disko layout
├── home-manager/          # Home-manager user configurations
│   ├── home.nix           # Shared base home config for ecomex
│   ├── home-nix-ai.nix    # Host-specific config for nix-ai (imports home.nix)
│   └── home-nix-mac.nix   # Host-specific config for nix-mac (imports home.nix)
├── modules/               # Reusable modules
│   ├── nixos/            # System-level modules
│   └── home-manager/     # User-level modules
├── overlays/             # Package overlays and modifications
├── pkgs/                 # Custom package definitions
├── wallpapers/           # Wallpaper images for Noctalia auto-rotation
└── nix-shell/            # Development environment shells
    └── comfyUI/
```

### Module System

This configuration uses a modular approach where functionality is split into focused modules:

**NixOS Modules** (`modules/nixos/`):
- Imported via `inputs.self.nixosModules.<name>` in configuration.nix
- Each module file must be registered in `modules/nixos/default.nix`
- The registry includes workstation modules plus homelab services such as
  Traefik, Vaultwarden, SearXNG, Stirling-PDF, Nextcloud, LiteLLM,
  cloudflared, restic, Immich, Paperless, Open WebUI, Hermes/AVA,
  Haushaltsbuch, and Honcho. Treat `modules/nixos/default.nix` as the current
  source of truth.

**Home-Manager Modules** (`modules/home-manager/`):
- Imported via `inputs.self.homeManagerModules.<name>` in home.nix
- Each module file must be registered in `modules/home-manager/default.nix`
- Available: bat, bottom, eza, fastfetch, fzf, git, kitty, nextcloud-client, niri, noctalia, spotify, starship, thunderbird, tmux, vesktop, vscode, zen-browser, zsh

### Overlay System

Three overlays are defined in `overlays/default.nix`:
1. **additions**: Makes custom packages from `pkgs/` directory available
2. **modifications**: Allows overriding existing nixpkgs packages
3. **unstable-packages**: Provides access to unstable nixpkgs via `pkgs.unstable.<package>`

Both NixOS and home-manager configurations apply these overlays automatically.

### Niri Compositor & Noctalia Shell

This repository includes a complete Wayland desktop environment setup using
Niri compositor and Noctalia shell. The module imports are currently disabled
on headless `nix-ai`:

**Niri Compositor**:
- Scrollable-tiling Wayland compositor with unique layout paradigm
- System-level module (`modules/nixos/niri.nix`) enables SDDM session support
- User-level module (`modules/home-manager/niri.nix`) provides:
  - Display configuration (3440x1440@99.982Hz on DP-2)
  - Keyboard layout (German) and touchpad settings
  - Layout configuration (gaps, borders, focus rings)
  - Comprehensive keybindings for window management, workspaces, launching apps
  - XWayland support via xwayland-satellite for X11 applications
  - GNOME Keyring integration for secret management
  - Complementary tools: fuzzel (launcher), dolphin (file manager), grim/slurp (screenshots), mako (notifications)

**Noctalia Shell**:
- Modern desktop shell for Wayland compositors (500+ configuration options)
- Declarative configuration in `modules/home-manager/noctalia.nix`
- Features include:
  - App launcher with clipboard history and icon modes
  - Audio/MPRIS controls with visualizer
  - Top bar with extensive widget customization
  - Floating auto-hide dock with app grouping
  - Control center with network/Bluetooth/wallpaper shortcuts
  - Calendar with weather integration (location: Weikersheim, Germany)
  - Automatic wallpaper rotation from `/wallpapers/` directory
  - Session menu (lock, suspend, hibernate, reboot, shutdown)
  - System monitor with threshold alerts
  - OSD notifications with urgency levels

**Wallpapers**:
- Located in `/wallpapers/` directory (~100 images)
- Automatically rotated by Noctalia shell
- Mix of numbered and themed wallpapers

### Docker Support

Docker virtualization is configured via `modules/nixos/docker.nix`:
- Docker daemon with auto-start on boot
- Weekly automatic pruning of unused containers, images, and volumes
- Docker-compose and related tools included
- User `ecomex` added to docker group for rootless container management
- Use standard docker commands: `docker ps`, `docker run`, `docker-compose up`, etc.

### Key System Details

- **Networking**: NetworkManager on `nix-ai`; static networking on hl01-hl03.
- **Shell**: Zsh (system-level enabled), user `ecomex` in groups audio/video/input/render/networkmanager/wheel.
- **Desktop** (`nix-ai`): Plasma, Niri, Noctalia, greetd, PipeWire, gaming,
  and other desktop imports are currently commented out.
- **Browser**: Zen Browser (privacy-focused Firefox fork)
- **Graphics**: NVIDIA drivers with CUDA support (`cudatoolkit`, `nvtop`), VAAPI enabled
- **Virtualization**: Docker with auto-pruning on `nix-ai`; libvirt/KVM for
  the HAOS VM on `hl01`
- **Game streaming**: Wolf is active on `nix-ai`; Sunshine is currently
  commented out.
- **VSCode server**: `programs.nix-ld.enable` for dynamic linking

Note: the XanMod kernel line in the host configs is currently commented out (stock kernel in use).

## Adding New Components

### Adding a NixOS Module
1. Create module file in `modules/nixos/new-module.nix`
2. Register it in `modules/nixos/default.nix`: `new-module = import ./new-module.nix;`
3. Import it in the relevant host's `hosts/<host>/configuration.nix`: `inputs.self.nixosModules.new-module`

### Adding a Home-Manager Module
1. Create module file in `modules/home-manager/new-module.nix`
2. Register it in `modules/home-manager/default.nix`: `new-module = import ./new-module.nix;`
3. Import it in `home-manager/home.nix`: `inputs.self.homeManagerModules.new-module`

### Adding Custom Packages
1. Create package directory: `pkgs/package-name/`
2. Add `default.nix` with derivation
3. Register in `pkgs/default.nix`: `package-name = pkgs.callPackage ./package-name { };`
4. Package will be available via overlays in all configurations

### Adding Overlays
Modify existing package versions or apply patches in `overlays/default.nix` under the `modifications` overlay.

## Important Notes

- **Git staging required**: Nix flakes only see files tracked by git. Always `git add` new files before building.
- **Flake lock**: Dependencies are pinned in `flake.lock`. Run `nix flake update` to update.
- **State version**: 26.05 across all hosts (NixOS `system.stateVersion`) and home-manager (`home.stateVersion`). Do not change this after initial installation.
- **Homelab secrets**: encrypted with sops-nix under `secrets/`; never commit
  plaintext. Host password hashes and SSH hostkeys are injected during
  nixos-anywhere installation.
- **Unfree packages**: Enabled in both NixOS and home-manager configurations.
- **Experimental features**: Flakes and nix-command are enabled system-wide.
