{ config, lib, pkgs, ... }:
{
  # Thunderbird - Free and open-source email client
  # https://www.thunderbird.net/
  programs.thunderbird = {
    enable = true;
    profiles.default = {
      isDefault = true;
    };
  };
}
