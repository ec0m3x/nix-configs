# NixOS Configuration

Personal NixOS flake-based configuration repository for `nix-desktop` (hostname) and `ecomex` (user).

This configuration follows a modular approach based on the [nix-starter-config](https://github.com/Misterio77/nix-starter-configs) standard template.

## System Overview

- **Hostname**: `nix-desktop`
- **User**: `ecomex`
- **NixOS Version**: 25.11 (stable)
- **Kernel**: XanMod latest
- **Desktop Environment**: KDE Plasma with KWin
- **Graphics**: NVIDIA with beta drivers, CUDA support
- **Shell**: Zsh with custom home-manager configuration
- **Networking**: Static IP (10.20.50.30/24)

## Quick Start

### System Configuration

```bash
# Apply system configuration
sudo nixos-rebuild switch --flake .#nix-desktop

# Test configuration without switching
sudo nixos-rebuild test --flake .#nix-desktop

# Build without activating
sudo nixos-rebuild build --flake .#nix-desktop
```

### Home Manager Configuration

```bash
# Apply home-manager configuration
home-manager switch --flake .#ecomex@nix-desktop

# Build without switching
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

## Repository Structure

```
.
├── flake.nix              # Main flake configuration
├── flake.lock             # Dependency lock file
├── CLAUDE.md              # AI assistant documentation
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
└── nix-shell/            # Development environment shells
    └── comfyUI/          # ComfyUI FHS environment
```

## Module System

This configuration uses a modular architecture where functionality is split into focused modules:

### NixOS Modules (`modules/nixos/`)

Imported via `inputs.self.nixosModules.<name>` in configuration.nix:
- `boot` - Boot loader and kernel configuration
- `locale` - Localization settings
- `nvidia` - NVIDIA driver configuration
- `gaming` - Gaming-related packages and settings
- `plasma` - KDE Plasma desktop environment
- `ollama` - Ollama LLM service
- `sunshine` - Game streaming server
- `tailscale` - VPN networking
- `core-packages` - Essential system packages
- `docker` - Docker containerization platform

### Home-Manager Modules (`modules/home-manager/`)

Imported via `inputs.self.homeManagerModules.<name>` in home.nix:
- `bat` - Better cat with syntax highlighting
- `bottom` - System resource monitor
- `fastfetch` - System information tool
- `fzf` - Fuzzy finder
- `git` - Git configuration
- `starship` - Shell prompt
- `tmux` - Terminal multiplexer
- `zsh` - Z shell configuration

## Overlay System

Three overlays are defined in `overlays/default.nix`:

1. **additions**: Makes custom packages from `pkgs/` available
2. **modifications**: Allows overriding existing nixpkgs packages
3. **unstable-packages**: Provides access to unstable nixpkgs via `pkgs.unstable.<package>`

Both NixOS and home-manager configurations apply these overlays automatically.

## Adding Components

### Adding a NixOS Module

1. Create module file in `modules/nixos/new-module.nix`
2. Register it in `modules/nixos/default.nix`:
   ```nix
   new-module = import ./new-module.nix;
   ```
3. Import it in `hosts/nix-desktop/configuration.nix`:
   ```nix
   inputs.self.nixosModules.new-module
   ```

### Adding a Home-Manager Module

1. Create module file in `modules/home-manager/new-module.nix`
2. Register it in `modules/home-manager/default.nix`:
   ```nix
   new-module = import ./new-module.nix;
   ```
3. Import it in `home-manager/home.nix`:
   ```nix
   inputs.self.homeManagerModules.new-module
   ```

### Adding Custom Packages

1. Create package directory: `pkgs/package-name/`
2. Add `default.nix` with derivation
3. Register in `pkgs/default.nix`:
   ```nix
   package-name = pkgs.callPackage ./package-name { };
   ```
4. Package will be available via overlays in all configurations

### Adding Overlays

Modify existing package versions or apply patches in `overlays/default.nix` under the `modifications` overlay.

## Development Shells

### ComfyUI FHS Environment

```bash
cd nix-shell/comfyUI
nix-shell shell.nix
```

## Important Notes

- **Git staging required**: Nix flakes only see files tracked by git. Always `git add` new files before building.
- **Flake lock**: Dependencies are pinned in `flake.lock`. Run `nix flake update` to update.
- **State version**: Set to 25.11 - do not change after initial installation.
- **Unfree packages**: Enabled in both NixOS and home-manager configurations.
- **Experimental features**: Flakes and nix-command are enabled system-wide.

## Troubleshooting

### Nix says files don't exist

Nix flakes only see files tracked by git. Run `git add .` to include new files.

### Wrong package version installed

Dependencies follow `flake.lock`. Run `nix flake update` to update to latest versions.

## Resources

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [Nix Package Search](https://search.nixos.org/packages)
- [NixOS Wiki](https://wiki.nixos.org/)

## Credits

Based on [nix-starter-config](https://github.com/Misterio77/nix-starter-configs) by Misterio77.
