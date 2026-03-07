{ config, lib, pkgs, ... }:
{
  # Spotify music streaming client
  home.packages = with pkgs; [
    spotify
  ];
}
