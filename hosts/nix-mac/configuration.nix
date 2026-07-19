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

  # Determinate verwaltet /etc/nix/nix.conf selbst und blockt nix-darwins
  # Nix-Management. Deshalb deaktivieren wir es hier. Die `settings` unten
  # werden von nix-darwin ignoriert — Substituters stattdessen in
  # /etc/nix/determinate.nix pflegen (z.B. nix-community.cachix.org).
  nix = let
    flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
  in {
    enable = false;
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

  # Homebrew integration.
  # Top-level formulae via `brew leaves`, casks via `brew list --cask`.
  # `cleanup = "uninstall"` entfernt alles, was hier nicht deklariert ist —
  # beim Hinzufügen/Entfernen also die Listen pflegen.
  homebrew = {
    enable = true;
    brews = [
      "espeak-ng"
      "ffmpeg"
      "gh"
      "immich-cli"
      "iperf3"
      "mas"
      "opencode"
      "openjdk"
      "php"
      "syncthing"
      "uv"
      "wakeonlan"
      "whisper-cpp"
      "xcodegen"
      "zsh-autosuggestions"
      "zsh-completions"
      "zsh-syntax-highlighting"
    ];
    casks = [
      "codex"
      "cyberduck"
      "discord"
      "dolphin"
      "google-chrome"
      "microsoft-excel"
      "microsoft-powerpoint"
      "microsoft-teams"
      "minecraft"
      "moonlight"
      "nextcloud"
      "obs"
      "obsidian"
      "sonos"
      "spotify"
      "tailscale-app"
      "telegram-desktop"
      "visual-studio-code"
      "warp"
      "whatsapp"
      "windows-app"
    ];
    # Mac App Store Apps. `mas` muss in `brews` stehen (s.o.). Du musst im
    # App Store eingeloggt sein, damit `mas install` klappt. Apps, die du
    # hier entfernst, werden NICHT automatisch deinstalliert — Limitation
    # von `mas`/`brew bundle`. Manuelles Entfernen dann per
    # `mas uninstall <id>` oder über den App Store.
    masApps = {
      AusweisApp = 948660805;
      Bitwarden = 1352778147;
      "Return Dislikes" = 6605923430;
      Xcode = 497799835;
    };
    # Keep brew-managed apps when they are not declared here anymore.
    onActivation.cleanup = "uninstall";
    # Avoid auto-updating brew on every activation (run `brew upgrade` manually).
    onActivation.autoUpdate = false;
  };

  # macOS system defaults — gespiegelt vom aktuellen Live-Stand via
  # `defaults read NSGlobalDomain`, `com.apple.dock`, `com.apple.finder`
  # und `com.apple.driver.AppleBluetoothMultitouch.trackpad`.
  # Nur Optionen, die nix-darwin als typisierte Options kennt — Rest bleibt
  # auf macOS-Default (wird nicht überschrieben).
  system.defaults = {
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      AppleShowAllExtensions = true;
      NSAutomaticCapitalizationEnabled = true;
      NSAutomaticPeriodSubstitutionEnabled = true;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
      "com.apple.sound.beep.feedback" = 1; # int, 0/1
      "com.apple.springing.enabled" = true;
      "com.apple.springing.delay" = 0.5;
      "com.apple.trackpad.forceClick" = true;
    };
    dock = {
      autohide = false;
      magnification = true;
      largesize = 72;
      tilesize = 57;
      show-recents = false;
      show-process-indicators = true;
      launchanim = true;
      wvous-br-corner = 14; # 14 = Quick Note
      persistent-apps = [
        "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"
        "/System/Applications/Mail.app"
        "/Applications/Warp.app"
        "/Applications/Visual Studio Code.app"
        "/System/Applications/Calendar.app"
        "/Applications/Telegram Desktop.app"
        "/Applications/Obsidian.app"
        "/Applications/Moonlight.app"
        "/Users/ecomex/.hermes/hermes-agent/apps/desktop/release/mac-arm64/Hermes.app"
        "/Applications/WhatsApp.app"
      ];
      persistent-others = [
        "/Users/ecomex/Downloads"
      ];
    };
    finder = {
      AppleShowAllExtensions = true;
      ShowExternalHardDrivesOnDesktop = true;
      ShowHardDrivesOnDesktop = true;
      ShowMountedServersOnDesktop = true;
      ShowRemovableMediaOnDesktop = true;
      ShowPathbar = false;
      ShowStatusBar = false;
      NewWindowTarget = "Home";
    };
    trackpad = {
      Clicking = true;
      TrackpadRightClick = true;
      TrackpadThreeFingerDrag = false;
    };
  };

  # Wöchentlicher Cleanup-Job: Homebrew-Cache leeren (als User) und alte
  # Nix-Generationen löschen (als root via System-Daemon). Läuft sonntags 03:00.
  launchd.daemons.nix-gc = {
    script = ''
      exec /nix/var/nix/profiles/default/bin/nix-collect-garbage --delete-older-than 7d
    '';
    serviceConfig = {
      RunAtLoad = false;
      StartCalendarInterval = [{Weekday = 0; Hour = 3; Minute = 0;}];
      StandardOutPath = "/var/log/nix-gc.log";
      StandardErrorPath = "/var/log/nix-gc.log";
    };
  };

  launchd.user.agents.brew-cleanup = {
    script = ''
      exec /opt/homebrew/bin/brew cleanup --prune=all
    '';
    serviceConfig = {
      RunAtLoad = false;
      StartCalendarInterval = [{Weekday = 0; Hour = 3; Minute = 30;}];
      StandardOutPath = "/tmp/brew-cleanup.log";
      StandardErrorPath = "/tmp/brew-cleanup.log";
    };
  };

  # WLAN automatisch deaktivieren, wenn Ethernet die Default-Route ist,
  # und aktivieren, wenn kein Ethernet vorliegt. Pollt alle 15 s die Route.
  # macOS hat dafür keine eingebaute Option; das Script umgeht das.
  launchd.daemons.eth-wifi-switch = {
    script = ''
      wifi_dev=$(networksetup -listallhardwareports | awk '/^Wi-Fi/{getline;print $NF}')
      default_if=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
      if [ -z "$default_if" ] || [ "$default_if" = "$wifi_dev" ]; then
        networksetup -setairportpower "$wifi_dev" on
      else
        networksetup -setairportpower "$wifi_dev" off
      fi
    '';
    serviceConfig = {
      RunAtLoad = true;
      StartInterval = 15;
      StandardOutPath = "/var/log/eth-wifi-switch.log";
      StandardErrorPath = "/var/log/eth-wifi-switch.log";
    };
  };

  # Used by nix-darwin to know whether this is the first activation.
  # https://github.com/LnL/nix-darwin/blob/master/docs/index.md
  system.primaryUser = "ecomex";
  system.stateVersion = 6;
}
