# Host-spezifische Home-Config für nix-mac (nix-darwin, aarch64-darwin).
# Importiert die gemeinsame Basis (`home.nix`). Mac-spezifische Ergänzungen
# (andere Module, Pakete, programme.*-Optionen) hier pflegen.
{...}: {
  imports = [
    ./home.nix
  ];

  programs.zsh.shellAliases = {
    deploy-homelab = "ssh -t nix-ai 'cd /home/ecomex/nix-configs && ./scripts/deploy-homelab.sh'";
    cleanup-homelab = "ssh -t nix-ai 'cd /home/ecomex/nix-configs && ./scripts/cleanup-homelab.sh'";
  };
}
