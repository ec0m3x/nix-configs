{ config, lib, pkgs, inputs, ... }:
{
  # Zen Browser - Privacy-focused Firefox fork with beautiful design
  # https://zen-browser.app/
  imports = [
    inputs.zen-browser.homeModules.default
  ];

  programs.zen-browser = {
    enable = true;
  };
}
