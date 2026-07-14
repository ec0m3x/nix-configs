{
  inputs,
  pkgs,
  ...
}: {
  # Import niri nixos module from flake
  imports = [inputs.niri.nixosModules.niri];

  # Enable niri at system level for greetd session availability
  programs.niri.enable = true;

  # Enable XWayland support for X11 applications
  programs.xwayland.enable = true;

  # Install xwayland-satellite for rootless Xwayland
  environment.systemPackages = with pkgs; [
    xwayland-satellite
  ];

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    MOZ_ENABLE_WAYLAND = "1";
  };

  security.pam.services.greetd.enableGnomeKeyring = true;
}
