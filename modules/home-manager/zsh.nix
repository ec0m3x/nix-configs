{ ... }:
{
  programs = {
    zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting = {
        enable = true;
      };

      history = {
        save = 10000;
        size = 10000;
        path = "$HOME/.cache/zsh_history";
      };

      shellAliases = {
        desktop-up   = "sudo systemctl start display-manager";
        desktop-down = "sudo systemctl stop display-manager && sudo loginctl terminate-user ecomex";

        rln = "sudo nixos-rebuild switch --flake .#nix-desktop";
        rlh = "home-manager switch --flake .#ecomex@nix-desktop";
        cleanup-nix = "nh clean all --keep-since 5d --keep 3";
      };
    };
  };
}