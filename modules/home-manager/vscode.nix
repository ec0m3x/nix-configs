{
  config,
  lib,
  pkgs,
  ...
}: {
  programs.vscode = {
    enable = true;
    package = pkgs.vscode;
  };

  # libsecret is required for VSCode to access the system keyring (gnome-keyring)
  home.packages = with pkgs; [
    libsecret
  ];
}
