{ config, lib, pkgs, inputs, ... }:
{
  # Noctalia - A beautiful, minimal desktop shell for Wayland
  # https://github.com/noctalia-dev/noctalia-shell
  # https://noctalia.dev/

  # Noctalia uses Quickshell (Qt/QML) and works with Niri, Hyprland, Sway, and other Wayland compositors
  # Configuration is stored in ~/.config/noctalia/

  # Install noctalia-shell from flake input and required dependencies
  home.packages = [
    inputs.noctalia.packages.${pkgs.system}.default
  ] ++ (with pkgs; [
    # Qt/QML runtime for Quickshell
    qt6.qtbase
    qt6.qtdeclarative
    qt6.qtwayland

    # Additional tools that work well with Noctalia
    libnotify
    playerctl
    pamixer
    brightnessctl
  ]);

  # Optional: Set environment variables for Qt on Wayland
  home.sessionVariables = {
    QT_QPA_PLATFORM = "wayland";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
  };
}
