# NixOS Configuration

Personal NixOS flake-based configuration for `nix-ai` (hostname) and `ecomex` (user).

Based on the [nix-starter-config](https://github.com/Misterio77/nix-starter-configs) standard template.

## System Overview

- **Active host**: `nix-ai` — AI/desktop workstation
- **User**: `ecomex`
- **NixOS Version**: 26.05 (stable)
- **Kernel**: Stock (Linux)
- **Desktop**: KDE Plasma + Niri (scrollable-tiling Wayland compositor)
- **Shell**: Wayland via Noctalia shell
- **Graphics**: NVIDIA with CUDA support
- **Shell**: Zsh
- **Networking**: NetworkManager

> `nix-server` is an inactive reference config (headless game streaming server). It is retained as a template but no machine currently runs it.

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
- `latex` — Full TeX Live installation
- `locale` — Localization settings
- `nh` — `nh` NixOS helper
- `niri` — Niri Wayland compositor (SDDM session)
- `nvidia` — NVIDIA drivers and CUDA
- `ollama` — Ollama LLM service
- `pipewire` — Audio
- `plasma` — KDE Plasma desktop
- `ssh` — SSH daemon
- `sunshine` — Game streaming server
- `tailscale` — VPN networking

### Home-Manager Modules (`modules/home-manager/`)

Imported via `inputs.self.homeManagerModules.<name>` in `home.nix`:

- `bat` — Better `cat` with syntax highlighting
- `bottom` — System resource monitor
- `eza` — Modern `ls` replacement
- `fastfetch` — System information tool
- `fzf` — Fuzzy finder
- `git` — Git configuration
- `kitty` — Terminal emulator
- `nextcloud-client` — Nextcloud desktop client
- `niri` — Niri user config (display, keybindings, layout)
- `noctalia` — Noctalia desktop shell
- `spotify` — Spotify client
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
