{ config, lib, pkgs, ... }:
{
  xdg.configFile."mimeapps.list".force = true;

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      # Browser
      "text/html"             = "zen-beta.desktop";
      "x-scheme-handler/http" = "zen-beta.desktop";
      "x-scheme-handler/https" = "zen-beta.desktop";
      "x-scheme-handler/ftp"  = "zen-beta.desktop";
      "application/xhtml+xml" = "zen-beta.desktop";
    };
  };
}
