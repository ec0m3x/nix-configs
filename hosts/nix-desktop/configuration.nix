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
    inputs.self.nixosModules.locale
    inputs.self.nixosModules.nh
    inputs.self.nixosModules.nvidia
    inputs.self.nixosModules.ollama
    inputs.self.nixosModules.pipewire
    inputs.self.nixosModules.plasma
    inputs.self.nixosModules.ssh
    inputs.self.nixosModules.tailscale
    inputs.self.nixosModules.sunshine
    inputs.self.nixosModules.gaming

    # Or modules from other flakes (such as nixos-hardware):
    # inputs.hardware.nixosModules.common-cpu-amd
    # inputs.hardware.nixosModules.common-ssd

    # You can also split up your configuration and import pieces of it here:
    # ./users.nix
    ./monitor.nix

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
      # Opinionated: disable global registry
      flake-registry = "";
      # Workaround for https://github.com/NixOS/nix/issues/9574
      nix-path = config.nix.nixPath;
    };
    # Opinionated: disable channels
    channel.enable = false;

    # Opinionated: make flake registry and nix path match flake inputs
    registry = lib.mapAttrs (_: flake: {inherit flake;}) flakeInputs;
    nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
  };

  # Kernel modules
  boot.kernelModules = [ "uinput" ];

  # Network
  networking = {
    networkmanager.enable = false;
    hostName = "nix-desktop";
    defaultGateway.address = "10.20.50.1";
    nameservers = [ "10.20.50.1" ];
    interfaces = {
      enp4s0 = {
        wakeOnLan.enable = true;
        useDHCP = false;
        ipv4.addresses = [{
          address = "10.20.50.30";
          prefixLength = 24;
        }];
      };
    };
  };

  # Zsh shell
  programs.zsh.enable = true;

  # Disable the desktop start
  systemd.defaultUnit = lib.mkForce "multi-user.target";

  # Configure your system-wide user settings (groups, etc), add more users as needed.
  users.users = {
    ecomex = {
      # You can set an initial password for your user.
      # If you do, you can skip setting a root password by passing '--no-root-passwd' to nixos-install.
      # Be sure to change it (using passwd) after rebooting!
      initialPassword = "ultrageheim";
      isNormalUser = true;
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = [
        # Add your SSH public key(s) here, if you plan on using SSH to connect
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGox9JI8NEi1IxF2AXSQQF+Pnm/kxt1/RtnTyy6Rokk/ ecomex@MacBook.local"
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

  environment.systemPackages = with pkgs; [
  libevdev
  cudaPackages.cudatoolkit
  libva-utils
  nvidia-vaapi-driver
  ethtool
  ];

  # Udev-Regel für uinput hinzufügen
  # Dies erlaubt der Gruppe 'input' (in der Sunshine läuft), virtuelle Eingaben zu senden
  services.udev.extraRules = ''
    KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"
  '';

  # Umgebungsvariable für die gesamte Session setzen
  environment.variables = {
    "KWIN_FORCE_SW_CURSOR" = "1";
  };

  #vscode-server
  programs.nix-ld.enable = true;

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.11";
}
