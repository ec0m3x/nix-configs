# Gemeinsame Home-Config-Basis für alle Hosts (nix-ai, nix-mac).
# Host-spezifische Ergänzungen in home-<host>.nix, die diese Datei
# importieren.
{
  inputs,
  lib,
  config,
  pkgs,
  ...
}: {
  imports = [
    # CLI / headless-taugliche Module (plattformübergreifend):
    inputs.self.homeManagerModules.bat
    inputs.self.homeManagerModules.bottom
    inputs.self.homeManagerModules.eza
    inputs.self.homeManagerModules.fastfetch
    inputs.self.homeManagerModules.fzf
    inputs.self.homeManagerModules.git
    inputs.self.homeManagerModules.huggingface-cli
    inputs.self.homeManagerModules.opencode
    inputs.self.homeManagerModules.pi-coding-agent
    inputs.self.homeManagerModules.starship
    inputs.self.homeManagerModules.tmux
    inputs.self.homeManagerModules.zsh
  ];

  home = {
    username = "ecomex";
    homeDirectory = if pkgs.stdenv.isDarwin then "/Users/${config.home.username}" else "/home/${config.home.username}";

    sessionVariables = {
      GH_CONFIG_DIR = "$HOME/.local/share/gh";
    };
  };

  # Disable home-manager news
  news.display = "silent";

  # Nicely reload system units when changing configs (nur Linux)
  systemd.user.startServices = lib.mkIf pkgs.stdenv.isLinux "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "26.05";
}
