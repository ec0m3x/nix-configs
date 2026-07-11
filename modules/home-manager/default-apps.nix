{ config, lib, pkgs, ... }:
{
  # Make home-manager app paths visible to graphical sessions (KDE/Dolphin)
  xdg.systemDirs.data = [
    "/etc/profiles/per-user/${config.home.username}/share"
    "/run/current-system/sw/share"
  ];

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
