{ config, lib, pkgs, ... }:
{
  # Vesktop - Discord client with Vencord built-in
  home.packages = with pkgs; [
    vesktop
  ];
}
