# This is your system's configuration file.
# Use this to configure your system environment (it replaces /etc/nixos/configuration.nix)
{
  inputs,
  self,
  lib,
  config,
  pkgs,
  ...
}: {
  # You can import other NixOS modules here
  imports = [
    # If you want to use modules your own flake exports (from modules/nixos):
    # inputs.self.nixosModules.example
    inputs.self.nixosModules.boot
    inputs.self.nixosModules.comfyui
    inputs.self.nixosModules.core-packages
    inputs.self.nixosModules.docker
    inputs.self.nixosModules.llama-swap
    inputs.self.nixosModules.locale
    inputs.self.nixosModules.nh
    inputs.self.nixosModules.nvidia
    inputs.self.nixosModules.ollama
    inputs.self.nixosModules.samba
    inputs.self.nixosModules.ssh
    #inputs.self.nixosModules.sunshine
    inputs.self.nixosModules.tailscale
    inputs.self.nixosModules.wolow-companion
    inputs.self.nixosModules.wolf

    # Desktop-Module (headless-Betrieb deaktiviert, Dateien behalten):
    #inputs.self.nixosModules.latex
    #inputs.self.nixosModules.gaming
    #inputs.self.nixosModules.niri
    #inputs.self.nixosModules.pipewire
    #inputs.self.nixosModules.greetd

    # Or modules from other flakes (such as nixos-hardware):
    # inputs.hardware.nixosModules.common-cpu-amd
    # inputs.hardware.nixosModules.common-ssd

    # You can also split up your configuration and import pieces of it here:
    # ./users.nix

    # Import your generated (nixos-generate-config) hardware configuration
    ./hardware-configuration.nix
  ];

  nixpkgs = {
    # You can add overlays here
    overlays = [
      # Add overlays your own flake exports (from overlays and pkgs dir):
      inputs.self.overlays.additions
      inputs.self.overlays.modifications
      inputs.self.overlays.unstable-packages

      # You can also add overlays exported from other flakes:
      # neovim-nightly-overlay.overlays.default

      # Or define it inline, for example:
      # (final: prev: {
      #   hi = final.hello.overrideAttrs (oldAttrs: {
      #     patches = [ ./change-hello-to-hi.patch ];
      #   });
      # })
    ];
    # Configure your nixpkgs instance
    config = {
      # Disable if you don't want unfree packages
      allowUnfree = true;
    };
  };

  nix = let
    flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
  in {
    settings = {
      # Enable flakes and new 'nix' command
      experimental-features = "nix-command flakes";
      # auto-optimize store
      auto-optimise-store = true;
      # Opinionated: disable global registry
      flake-registry = "";
      # Workaround for https://github.com/NixOS/nix/issues/9574
      nix-path = config.nix.nixPath;
      # Binary caches for niri, noctalia and comfyui (avoids building from source)
      substituters = [
        "https://cache.nixos.org"
        "https://niri.cachix.org"
        "https://comfyui.cachix.org"
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964="
        "comfyui.cachix.org-1:33mf9VzoIjzVbp0zwj+fT51HG0y31ZTK3nzYZAX0rec="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
    # Opinionated: disable channels
    channel.enable = false;

    # Opinionated: make flake registry and nix path match flake inputs
    registry = lib.mapAttrs (_: flake: {inherit flake;}) flakeInputs;
    nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
  };

  # Network
  networking = {
    interfaces.enp42s0.wakeOnLan.enable = true;

    networkmanager = {
      enable = true;
      ensureProfiles.profiles."static-enp42s0" = {
        connection = {
          id = "static-enp42s0";
          type = "ethernet";
          interface-name = "enp42s0";
        };
        ipv4 = {
          method = "manual";
          addresses = "10.20.50.20/24";
          gateway = "10.20.50.1";
          dns = "10.20.50.1;8.8.8.8;";
        };
        ipv6.method = "auto";
      };
    };
    hostName = "nix-ai";
  };

  # Zusätzliche Datenträger (SSD + HDD)
  fileSystems."/mnt/ssd" = {
    device = "/dev/disk/by-label/ssd";
    fsType = "ext4";
    options = ["defaults" "nofail"];
  };
  fileSystems."/mnt/hdd" = {
    device = "/dev/disk/by-label/hdd";
    fsType = "ext4";
    options = ["defaults" "nofail"];
  };

  # Host-spezifische Samba-Freigabe auf der SSD.
  # Das generische `samba`-Modul aktiviert nur den Dienst + global-Config;
  # die konkrete Freigabe wird hier pro Host definiert.
  # Passwort für `ecomex` einmalig setzen: `sudo smbpasswd -a ecomex`
  services.samba.settings.home-share = {
    path = "/mnt/ssd/shares";
    browseable = "yes";
    public = "yes"; # = guest ok = yes
    "read only" = "yes"; # Default: nur Lesen
    "write list" = ["ecomex"]; # nur ecomex darf schreiben
    "force user" = "ecomex"; # Schreib-I/O als ecomex (konsistente Ownership)
    "force group" = "users";
    "create mask" = "0644";
    "directory mask" = "0755";
  };

  # Share-Verzeichnis gehört ecomex — sonst schlägt `force user` fehl, weil
  # die ext4-Root der SSD default root:root ist. Verzeichnis liegt extra
  # unter /mnt/ssd/shares, damit die SSD nicht direkt exponiert wird.
  systemd.tmpfiles.rules = [
    "d /mnt/ssd 0755 ecomex users -"
    "d /mnt/ssd/shares 0755 ecomex users -"
  ];

  # Zsh shell
  programs.zsh.enable = true;

  # Configure your system-wide user settings (groups, etc), add more users as needed.
  users.users = {
    ecomex = {
      # You can set an initial password for your user.
      # If you do, you can skip setting a root password by passing '--no-root-passwd' to nixos-install.
      # Be sure to change it (using passwd) after rebooting!
      # Password hash is read from a file outside the repo (not world-readable).
      # Create with: mkpasswd -m yescrypt | sudo tee /etc/nixos-secrets/ecomex
      hashedPasswordFile = "/etc/nixos-secrets/ecomex";
      isNormalUser = true;
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGox9JI8NEi1IxF2AXSQQF+Pnm/kxt1/RtnTyy6Rokk/ ecomex@nix-ai"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIMITvvLRVK0B6amvBv6ZT1eb80fYLVYP9xdRREl7ftk ecomex@nix-ai"
      ];
      # Be sure to add any other groups you need (such as networkmanager, audio, docker, etc)
      extraGroups = [
        "audio"
        "networkmanager"
        "users"
        "video"
        "input"
        "render"
        "wheel"
      ];
    };
  };

  # Sudo: show asterisks on password input and insult on wrong password
  security.sudo.extraConfig = ''
    Defaults pwfeedback
    Defaults insults
  '';

  environment.systemPackages = with pkgs; [
    cudaPackages.cudatoolkit
    nvtopPackages.nvidia
    iperf3
  ];

  # Required for VSCode server / nix-ld dynamic linking
  programs.nix-ld.enable = true;

  # gvfs for Nautilus trash, MTP, network mounts
  # services.gvfs.enable = true;  # headless: deaktiviert

  # Bluetooth (headless: deaktiviert)
  # hardware.bluetooth.enable = true;
  # services.blueman.enable = true;

  # TPM2 auto-unlock for LUKS (enroll with: sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 /dev/disk/by-uuid/6d721ce2-5405-4b81-9d74-366cd5f79480)
  boot.initrd.luks.devices."luks-6d721ce2-5405-4b81-9d74-366cd5f79480".crypttabExtraOpts = [
    "tpm2-device=auto"
    "tpm2-pcrs=0+7"
  ];

  # Wolow Companion (remote power management for Wolow mobile app)
  services.wolow-companion.enable = true;

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "26.05";
}
