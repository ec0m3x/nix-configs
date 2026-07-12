{ pkgs, ... }:
{
  programs.nh = {
    enable = true;
    flake = "/home/ecomex/nix-configs";
    clean = {
      enable = true;
      extraArgs = "--keep-since 5d --keep 5";
    };
  };
}