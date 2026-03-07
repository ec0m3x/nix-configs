{ config, lib, pkgs, ... }:
{
  # Nextcloud desktop client for file synchronization
  services.nextcloud-client = {
    enable = true;
    startInBackground = true;
  };
}
