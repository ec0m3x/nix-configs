{
  config,
  lib,
  pkgs,
  ...
}: {
  # Proton Mail Desktop - unofficial desktop client (Electron wrapper of web app)
  # https://proton.me/mail
  home.packages = [pkgs.unstable.protonmail-desktop];
}
