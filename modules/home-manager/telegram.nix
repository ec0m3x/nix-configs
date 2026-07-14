{
  config,
  lib,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    pkgs.unstable.telegram-desktop
  ];
}
