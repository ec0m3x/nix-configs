{ config, lib, pkgs, inputs, ... }:
{
  # Niri - Scrollable-tiling Wayland compositor
  # https://github.com/YaLTeR/niri
  # Note: Niri is enabled at system level (NixOS module)
  # This module only provides user-specific configuration

  # Niri configuration file
  xdg.configFile."niri/config.kdl".text = ''
      input {
          keyboard {
              xkb {
                  layout "de"
              }
          }

          touchpad {
              tap
              natural-scroll
          }
      }

      output "DP-2" {
          mode "3440x1440@99.982"
      }

      layout {
          gaps 16
          center-focused-column "never"

          preset-column-widths {
              proportion 0.33333
              proportion 0.5
              proportion 0.66667
          }

          default-column-width { proportion 0.5; }

          border {
              width 1
          }

          focus-ring {
              width 1
          }
      }

      prefer-no-csd

      hotkey-overlay {
          skip-at-startup
      }

      binds {
          Mod+Return { spawn "kitty"; }
          Mod+T { spawn "kitty"; }
          Mod+D { spawn "dolphin"; }
          Mod+Space { spawn "fuzzel"; }
          Mod+V { spawn "sh" "-c" "cliphist list | fuzzel --dmenu | cliphist decode | wl-copy"; }
          Mod+Q { close-window; }

          Mod+Left  { focus-column-left; }
          Mod+Down  { focus-workspace-down; }
          Mod+Up    { focus-workspace-up; }
          Mod+Right { focus-column-right; }
          Mod+H     { focus-column-left; }
          Mod+J     { focus-window-down; }
          Mod+K     { focus-window-up; }
          Mod+L     { focus-column-right; }

          Mod+Ctrl+Left  { move-column-left; }
          Mod+Ctrl+Down  { move-window-down; }
          Mod+Ctrl+Up    { move-window-up; }
          Mod+Ctrl+Right { move-column-right; }
          Mod+Ctrl+H     { move-column-left; }
          Mod+Ctrl+J     { move-window-down; }
          Mod+Ctrl+K     { move-window-up; }
          Mod+Ctrl+L     { move-column-right; }

          Mod+Home { focus-column-first; }
          Mod+End  { focus-column-last; }
          Mod+Ctrl+Home { move-column-to-first; }
          Mod+Ctrl+End  { move-column-to-last; }

          Mod+Shift+Left  { focus-monitor-left; }
          Mod+Shift+Down  { focus-monitor-down; }
          Mod+Shift+Up    { focus-monitor-up; }
          Mod+Shift+Right { focus-monitor-right; }
          Mod+Shift+H     { focus-monitor-left; }
          Mod+Shift+J     { focus-monitor-down; }
          Mod+Shift+K     { focus-monitor-up; }
          Mod+Shift+L     { focus-monitor-right; }

          Mod+1 { focus-workspace 1; }
          Mod+2 { focus-workspace 2; }
          Mod+3 { focus-workspace 3; }
          Mod+4 { focus-workspace 4; }
          Mod+5 { focus-workspace 5; }
          Mod+6 { focus-workspace 6; }
          Mod+7 { focus-workspace 7; }
          Mod+8 { focus-workspace 8; }
          Mod+9 { focus-workspace 9; }

          Mod+Ctrl+1 { move-column-to-workspace 1; }
          Mod+Ctrl+2 { move-column-to-workspace 2; }
          Mod+Ctrl+3 { move-column-to-workspace 3; }
          Mod+Ctrl+4 { move-column-to-workspace 4; }
          Mod+Ctrl+5 { move-column-to-workspace 5; }
          Mod+Ctrl+6 { move-column-to-workspace 6; }
          Mod+Ctrl+7 { move-column-to-workspace 7; }
          Mod+Ctrl+8 { move-column-to-workspace 8; }
          Mod+Ctrl+9 { move-column-to-workspace 9; }

          Mod+Comma  { consume-window-into-column; }
          Mod+Period { expel-window-from-column; }

          Mod+R { switch-preset-column-width; }
          Mod+F { maximize-column; }
          Mod+Shift+F { fullscreen-window; }
          Mod+C { center-column; }

          Mod+Minus { set-column-width "-10%"; }
          Mod+Equal { set-column-width "+10%"; }
          Mod+0 { set-column-width "50%"; }

          Mod+Shift+E { quit; }
          Mod+Shift+P { power-off-monitors; }

          Mod+Shift+Ctrl+T { toggle-debug-tint; }

          // Screenshot bindings
          Print { spawn "sh" "-c" "grim -g \"$(slurp)\" \"$HOME/Bilder/Screenshots/$(date +'%Y-%m-%d_%H-%M-%S').png\" && notify-send 'Screenshot' 'Area saved'"; }
          Shift+Print { spawn "sh" "-c" "grim \"$HOME/Bilder/Screenshots/$(date +'%Y-%m-%d_%H-%M-%S').png\" && notify-send 'Screenshot' 'Screen saved'"; }

          // Media control bindings
          XF86AudioPlay { spawn "playerctl" "play-pause"; }
          XF86AudioPause { spawn "playerctl" "play-pause"; }
          XF86AudioNext { spawn "playerctl" "next"; }
          XF86AudioPrev { spawn "playerctl" "previous"; }

          // Volume control bindings
          XF86AudioRaiseVolume { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%+"; }
          XF86AudioLowerVolume { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-"; }
          XF86AudioMute { spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"; }
      }

      spawn-at-startup "noctalia-shell"

      cursor {
          xcursor-theme "Adwaita"
          xcursor-size 24
      }
    '';

  # Install complementary tools for niri
  home.packages = with pkgs; [
    # Application launcher
    fuzzel

    # File manager
    kdePackages.dolphin

    # Screenshot tool
    grim
    slurp

    # Clipboard manager
    wl-clipboard
    cliphist

    # Notification daemon
    mako
    libnotify  # provides notify-send

    # Media player control
    playerctl

    # Audio control
    pamixer

    # Brightness control
    brightnessctl
  ];

  # Clipboard history daemon
  services.cliphist.enable = true;

  # GNOME Keyring for secret management
  services.gnome-keyring = {
    enable = true;
    components = [ "secrets" ];
  };

  # Note: polkit-kde-agent is started automatically by niri-flake via systemd service

  # XDG portal configuration for Niri
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
      xdg-desktop-portal-wlr
    ];
    config = {
      # Default portal configuration for Niri
      niri = {
        default = [ "gtk" ];
        "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
      };
      # Fallback configuration for other compositors
      common = {
        default = [ "gtk" ];
      };
    };
  };
}
