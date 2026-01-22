{ ... }:
{
  # Enable the KDE Plasma Desktop Environment.
  services.displayManager = {
    sddm = {
      enable = true;
      wayland.enable = true;
    };
    # optional autolgin
    autoLogin = {
      enable = true;
      user = "ecomex";
    };
  };
  services.desktopManager.plasma6.enable = true;
  programs.xwayland.enable = true;
}