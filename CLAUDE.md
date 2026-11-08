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
