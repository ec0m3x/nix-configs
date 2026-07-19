# Samba-Server auf nix-ai. Stellt /mnt/ssd (512 GB SSD) im Netz als
# Freigabe `home-share` zur Verfügung.
#   - Gast-Zugang: lesend (ohne Passwort)
#   - `ecomex`: lesend + schreibend (Passwort via `smbpasswd -a ecomex`)
#
# Passwort ist NICHT deklarativ (gehört nicht ins Repo). Einmal nach dem
# ersten Switch setzen:
#   sudo smbpasswd -a ecomex
{
  pkgs,
  config,
  ...
}: {
  services.samba = {
    enable = true;
    openFirewall = true; # Samba-Ports überall offen (user entschieden)

    settings = {
      global = {
        workgroup = "WORKGROUP";
        "server string" = "nix-ai samba";
        "server role" = "standalone";
        security = "user";

        # Gast-Zugang erlauben, gemappt auf `nobody`
        "guest account" = "nobody";
        "map to guest" = "bad user";
      };

      home-share = {
        path = "/mnt/ssd/shares";
        browseable = "yes";
        public = "yes"; # = guest ok = yes
        "read only" = "yes"; # Default: nur Lesen
        "write list" = "ecomex"; # nur ecomex darf schreiben
        "force user" = "ecomex"; # Schreib-I/O als ecomex (konsistente Ownership)
        "force group" = "users";
        "create mask" = "0644";
        "directory mask" = "0755";
      };
    };
  };

  # Share-Verzeichnis gehört ecomex — sonst schlägt `force user` fehl, weil
  # die ext4-Root der SSD default root:root ist. Das Verzeichnis liegt
  # extra unter /mnt/ssd/shares, damit die SSD nicht direkt exponiert wird.
  systemd.tmpfiles.rules = [
    "d /mnt/ssd 0755 ecomex users -"
    "d /mnt/ssd/shares 0755 ecomex users -"
  ];
}
