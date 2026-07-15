# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)
{
  inputs,
  lib,
  config,
  pkgs,
  ...
}: {
  # You can import other home-manager modules here
  imports = [
    # If you want to use modules your own flake exports (from modules/home-manager):
    # inputs.self.homeManagerModules.example
    inputs.self.homeManagerModules.bat
    inputs.self.homeManagerModules.default-apps
    inputs.self.homeManagerModules.bottom
    inputs.self.homeManagerModules.eza
    inputs.self.homeManagerModules.fastfetch
    inputs.self.homeManagerModules.fzf
    inputs.self.homeManagerModules.git
    inputs.self.homeManagerModules.huggingface-cli
    inputs.self.homeManagerModules.kitty
    inputs.self.homeManagerModules.nextcloud-client
    inputs.self.homeManagerModules.niri
    inputs.self.homeManagerModules.opencode
    inputs.self.homeManagerModules.pi-coding-agent
    inputs.self.homeManagerModules.noctalia
    inputs.self.homeManagerModules.spotify
    inputs.self.homeManagerModules.telegram
    inputs.self.homeManagerModules.starship
    inputs.self.homeManagerModules.thunderbird
    inputs.self.homeManagerModules.tmux
    inputs.self.homeManagerModules.vesktop
    inputs.self.homeManagerModules.vscode
    inputs.self.homeManagerModules.zen-browser
    inputs.self.homeManagerModules.zsh

    # Or modules exported from other flakes (such as nix-colors):
    # inputs.nix-colors.homeManagerModules.default

    # You can also split up your configuration and import pieces of it here:
    # ./nvim.nix
  ];

  home = {
    username = "ecomex";
    homeDirectory = "/home/ecomex";

    sessionVariables = {
      GH_CONFIG_DIR = "$HOME/.local/share/gh";
    };

    pointerCursor = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
      size = 16;
      gtk.enable = true;
    };
  };

  gtk = {
    enable = true;
    theme = {
      name = "Tokyonight-Dark";
      package = pkgs.tokyonight-gtk-theme;
    };
    iconTheme = {
      name = "candy-icons";
      package = pkgs.candy-icons;
    };
  };

  qt = {
    enable = true;
    platformTheme.name = "gtk";
  };

  # Add stuff for your user as you see fit:
  # programs.neovim.enable = true;
  # home.packages = with pkgs; [ steam ];

  # Disable home-manager news
  news.display = "silent";

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "26.05";
}
