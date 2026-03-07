# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a NixOS flake-based configuration repository following the "standard" template structure from nix-starter-config. It manages both system-wide NixOS configuration and user-level home-manager configuration for the hostname `nix-desktop` and user `ecomex`.

## Common Commands

### System Configuration
```bash
# Rebuild NixOS system configuration
sudo nixos-rebuild switch --flake .#nix-desktop

# Test system configuration without switching
sudo nixos-rebuild test --flake .#nix-desktop

# Build system configuration without activating
sudo nixos-rebuild build --flake .#nix-desktop
```

### Home Manager Configuration
```bash
# Apply home-manager configuration
home-manager switch --flake .#ecomex@nix-desktop

# Build home-manager configuration without switching
home-manager build --flake .#ecomex@nix-desktop
```

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
  - nixpkgs (25.11 stable) and nixpkgs-unstable
  - home-manager (for user configuration)
  - niri-flake (scrollable-tiling Wayland compositor)
  - noctalia-shell (desktop shell for Wayland)
  - zen-browser (privacy-focused Firefox fork)
- **Outputs**: NixOS configurations, home-manager configurations, custom packages, overlays, and reusable modules
- **System**: Configured for `nix-desktop` hostname with user `ecomex@nix-desktop`

### Directory Layout

```
.
├── flake.nix              # Main flake configuration
├── hosts/                 # Per-host NixOS configurations
│   └── nix-desktop/       # Desktop configuration
│       ├── configuration.nix
│       ├── hardware-configuration.nix
│       └── monitor.nix
├── home-manager/          # Home-manager user configurations
│   └── home.nix           # Main home config for ecomex
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
- Examples: boot, locale, nvidia, gaming, plasma, niri, docker, ollama, sunshine, tailscale, core-packages

**Home-Manager Modules** (`modules/home-manager/`):
- Imported via `inputs.self.homeManagerModules.<name>` in home.nix
- Each module file must be registered in `modules/home-manager/default.nix`
- Examples: bat, bottom, eza, fastfetch, fzf, git, kitty, nextcloud-client, niri, noctalia, spotify, starship, thunderbird, tmux, vesktop, vscode, zen-browser, zsh

### Overlay System

Three overlays are defined in `overlays/default.nix`:
1. **additions**: Makes custom packages from `pkgs/` directory available
2. **modifications**: Allows overriding existing nixpkgs packages
3. **unstable-packages**: Provides access to unstable nixpkgs via `pkgs.unstable.<package>`

Both NixOS and home-manager configurations apply these overlays automatically.

### Niri Compositor & Noctalia Shell

This configuration includes a complete Wayland desktop environment setup using Niri compositor and Noctalia shell:

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
- Located in `/wallpapers/` directory (82 images)
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

- **Kernel**: XanMod latest kernel (`boot.kernelPackages = pkgs.linuxPackages_xanmod_latest`)
- **Networking**: NetworkManager with DHCP, wake-on-LAN support
- **Shell**: Zsh (system-level enabled)
- **Desktop Options**:
  - **KDE Plasma**: Traditional desktop with KWin (auto-login disabled)
  - **Niri + Noctalia**: Wayland compositor with scrollable-tiling and custom shell
- **Browser**: Zen Browser (privacy-focused Firefox fork)
- **Display**: Ultrawide monitor (3440x1440@99.982Hz on DP-2)
- **Graphics**: NVIDIA with beta drivers, CUDA support, VAAPI enabled
- **Virtualization**: Docker with auto-pruning enabled
- **Login Manager**: SDDM (auto-login disabled)

## Adding New Components

### Adding a NixOS Module
1. Create module file in `modules/nixos/new-module.nix`
2. Register it in `modules/nixos/default.nix`: `new-module = import ./new-module.nix;`
3. Import it in `hosts/nix-desktop/configuration.nix`: `inputs.self.nixosModules.new-module`

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
- **State version**: Currently set to 25.11 - do not change this after initial installation.
- **Unfree packages**: Enabled in both NixOS and home-manager configurations.
- **Experimental features**: Flakes and nix-command are enabled system-wide.
