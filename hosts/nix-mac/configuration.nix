# nix-darwin configuration for the MacBook (Apple Silicon).
# Apply with: darwin-rebuild switch --flake .#nix-mac
{
  inputs,
  lib,
  config,
  pkgs,
  ...
}: {
  # You can import reusable darwin modules here if you add some under modules/darwin/.
  # imports = [
  #   ./darwin-module.nix
  # ];

  nixpkgs = {
    # 'additions' overlay is Linux-only (wolow-companion), so we only apply
    # modifications and unstable-packages here.
    overlays = [
      inputs.self.overlays.modifications
      inputs.self.overlays.unstable-packages
    ];
    config = {
      allowUnfree = true;
    };
  };

  nix = let
    flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
  in {
    settings = {
      experimental-features = "nix-command flakes";
      auto-optimise-store = true;
      flake-registry = "";
      # Workaround for https://github.com/NixOS/nix/issues/9574
      nix-path = config.nix.nixPath;
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
    channel.enable = false;
    registry = lib.mapAttrs (_: flake: {inherit flake;}) flakeInputs;
    nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
  };

  # System-wide packages available in the global profile.
  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    ripgrep
    fd
  ];

  # Zsh shell (matches the nix-ai setup).
  programs.zsh.enable = true;

  # Configure your user. The user must already exist on the Mac; nix-darwin
  # will manage its shell and groups. Create it beforehand via
  # System Settings -> Users & Groups if it does not exist yet.
  users.users.ecomex = {
    shell = pkgs.zsh;
    home = "/Users/ecomex";
  };

  # Homebrew integration (the user opted into Casks).
  homebrew = {
    enable = true;
    brews = [
      # CLI tools not (yet) in nixpkgs / handy to keep via brew.
    ];
    casks = [
      # GUI apps managed via Homebrew Casks. Add your apps here, e.g.:
      # "raycast"
      # "1password"
      # "visual-studio-code"
      # "ghostty"
      # "firefox"
    ];
    # Keep brew-managed apps when they are not declared here anymore.
    onActivation.cleanup = "uninstall";
    # Avoid auto-updating brew on every activation (run `brew upgrade` manually).
    onActivation.autoUpdate = false;
  };

  # macOS system defaults (a small sensible selection; extend as needed).
  system.defaults = {
    NSGlobalDomain = {
      AppleShowAllExtensions = true;
      InitialKeyRepeat = 14;
      KeyRepeat = 1;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      "com.apple.keyboard.fnState" = true;
    };
    dock = {
      autohide = true;
      orientation = "left";
      show-recents = false;
      tilesize = 36;
    };
    finder = {
      AppleShowAllExtensions = true;
      ShowPathbar = true;
      ShowStatusBar = true;
      _showRelativePath = true;
    };
    trackpad = {
      Clicking = true;
      TrackpadRightClick = true;
    };
  };

  # Used by nix-darwin to know whether this is the first activation.
  # https://github.com/LnL/nix-darwin/blob/master/docs/index.md
  system.stateVersion = 6;
}
