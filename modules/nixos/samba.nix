# Generisches Samba-Modul: aktiviert den Dienst + globale Defaults +
# Firewall. Host-spezifische Shares (Pfade, User, Freigabenamen) werden
# in `hosts/<host>/configuration.nix` via `services.samba.settings.*`
# definiert — siehe nix-ai als Beispiel.
{
  ...
}: {
  services.samba = {
    enable = true;
    openFirewall = true;

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
    };
  };
}
