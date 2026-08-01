# Host-spezifische Home-Config für nix-ai (NixOS, x86_64-linux).
# Headless-Betrieb — Desktop-Module sind bewusst nicht enthalten.
# Die Moduldateien existieren weiter unter modules/home-manager/ und
# können bei Bedarf hier einklinkt werden.
{inputs, ...}: {
  imports = [
    ./home.nix
    inputs.self.homeManagerModules.codex
  ];

  programs.zsh.shellAliases = {
    deploy-homelab = "(cd /home/ecomex/nix-configs && ./scripts/deploy-homelab.sh)";
    cleanup-homelab = "(cd /home/ecomex/nix-configs && ./scripts/cleanup-homelab.sh)";
  };
}
