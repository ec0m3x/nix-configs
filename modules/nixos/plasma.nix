{ ... }:
{
  # Enable the KDE Plasma Desktop Environment.
  services.displayManager = {
    sddm = {
      enable = true;
      wayland.enable = true;
    };
    # optional autolgin
    #autoLogin = {
    #  enable = true;
    #  user = "ecomex";
    #};
  };
  services.desktopManager.plasma6.enable = true;

  # Force software cursor (needed with NVIDIA on Wayland)
  environment.variables.KWIN_FORCE_SW_CURSOR = "1";
}