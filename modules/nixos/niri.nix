{ inputs, pkgs, ... }:
{
  # Import niri nixos module from flake
  imports = [ inputs.niri.nixosModules.niri ];

  # Enable niri at system level for SDDM session availability
  programs.niri.enable = true;

  # Enable XWayland support for X11 applications
  programs.xwayland.enable = true;

  # Install xwayland-satellite for rootless Xwayland
  environment.systemPackages = with pkgs; [
    xwayland-satellite
  ];
}
