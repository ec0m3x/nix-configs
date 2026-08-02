# Gemeinsame Basis für die Homelab-Hosts hl01–hl03 (ehemals Proxmox pve01–pve03).
# Host-spezifisch bleiben: Hostname, statische IP, MAC-Pinning der NIC auf
# `lan0`, das disko-Layout und die Dienst-Module der jeweiligen Migrationsphase.
{
  inputs,
  lib,
  config,
  pkgs,
  ...
}: {
  imports = [
    inputs.home-manager.nixosModules.home-manager
    inputs.self.nixosModules.boot
    inputs.self.nixosModules.core-packages
    inputs.self.nixosModules.homelab-gitops
    inputs.self.nixosModules.locale
    inputs.self.nixosModules.nh
    inputs.self.nixosModules.ssh
    inputs.self.nixosModules.tailscale
  ];

  nixpkgs = {
    hostPlatform = "x86_64-linux";
    overlays = [
      inputs.self.overlays.additions
      inputs.self.overlays.modifications
      inputs.self.overlays.unstable-packages
    ];
    config.allowUnfree = true;
  };

  nix = let
    flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
  in {
    settings = {
      experimental-features = "nix-command flakes";
      auto-optimise-store = true;
      # Erlaubt deklarative Remote-Deployments vom Buildhost. Nur Mitglieder
      # der administrativen wheel-Gruppe dürfen unsignierte Closures senden.
      trusted-users = [
        "root"
        "@wheel"
      ];
      flake-registry = "";
      nix-path = config.nix.nixPath;
    };
    channel.enable = false;
    registry = lib.mapAttrs (_: flake: {inherit flake;}) flakeInputs;
    nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
  };

  # Statisches LAN ohne NetworkManager. Die NIC wird pro Host per
  # MAC-Adresse auf den stabilen Namen `lan0` gepinnt (udev .link-Datei),
  # damit wechselnde Kernel-Benennungen (USB-NICs auf hl01!) egal sind.
  networking = {
    useDHCP = false;
    defaultGateway = "10.20.50.1";
    # Bootstrap-DNS ist das Gateway; AdGuard (hl02) wird erst nach
    # erfolgreichem Umzug als Resolver eingetragen.
    nameservers = ["10.20.50.1"];
    firewall.enable = true;
    # Der Service-Wildcard *.hl.sk4i.com zeigt auf Traefik im Tailnet. Die
    # Host-FQDNs bleiben deshalb als explizite LAN-Ziele davon ausgenommen.
    hosts = {
      "10.20.50.11" = ["hl01.hl.sk4i.com"];
      "10.20.50.12" = ["hl02.hl.sk4i.com"];
      "10.20.50.13" = ["hl03.hl.sk4i.com"];
      "10.20.50.14" = ["haos.hl.sk4i.com"];
    };
  };

  programs.zsh.enable = true;

  # Der GitOps-Controller auf nix-ai darf ausschließlich bereits kopierte,
  # zum Host passende NixOS-Closures über den validierenden Wrapper aktivieren.
  services.homelabGitOps.target.enable = true;

  # Home Manager runs as part of the NixOS activation. Homelab hosts use a
  # small server profile rather than the nix-ai/macOS workstation profile.
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";
    extraSpecialArgs = {inherit inputs;};
    users.ecomex = import ../../home-manager/home-homelab.nix;
  };

  users.users.ecomex = {
    isNormalUser = true;
    shell = pkgs.zsh;
    # Hash wird bei der Installation via nixos-anywhere --extra-files nach
    # /etc/nixos-secrets/ecomex eingespielt (mkpasswd -m yescrypt).
    hashedPasswordFile = "/etc/nixos-secrets/ecomex";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGox9JI8NEi1IxF2AXSQQF+Pnm/kxt1/RtnTyy6Rokk/ ecomex@nix-ai"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIMITvvLRVK0B6amvBv6ZT1eb80fYLVYP9xdRREl7ftk ecomex@nix-ai"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKGL9iDJCW/+SzxmSNrXvzD++sjageJ+IaFFGYdc3k9T ecomex@nix-ai"
    ];
    extraGroups = ["wheel" "users"];
  };

  security.sudo.extraConfig = ''
    Defaults pwfeedback
    Defaults insults
  '';

  # sops-nix: Secrets werden mit dem SSH-Hostkey (ed25519 → age) des Hosts
  # entschlüsselt. Der Hostkey wird bei der Installation via
  # nixos-anywhere --extra-files vorab eingespielt, damit Secrets ab dem
  # ersten Boot funktionieren. Public-Keys stehen in .sops.yaml.
  sops.age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "26.05";
}
