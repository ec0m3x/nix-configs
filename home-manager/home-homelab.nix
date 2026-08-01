# Schlankes gemeinsames Home-Manager-Profil für hl01–hl03. Bewusst ohne
# Desktop-, AI-Agent- und große Workstation-spezifische Pakete.
{inputs, ...}: {
  imports = [
    ./home-base.nix
    inputs.self.homeManagerModules.bat
    inputs.self.homeManagerModules.bottom
    inputs.self.homeManagerModules.eza
    inputs.self.homeManagerModules.fastfetch
    inputs.self.homeManagerModules.fzf
    inputs.self.homeManagerModules.git
    inputs.self.homeManagerModules.starship
    inputs.self.homeManagerModules.tmux
    inputs.self.homeManagerModules.zsh
  ];
}
