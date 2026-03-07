# Add your reusable home-manager modules to this directory, on their own file (https://nixos.wiki/wiki/Module).
# These should be stuff you would like to share with others, not your personal configurations.
{
  # List your module files here
  # my-module = import ./my-module.nix;
  bat = import ./bat.nix;
  bottom = import ./bottom.nix;
  fastfetch = import ./fastfetch.nix;
  fzf = import ./fzf.nix;
  git = import ./git.nix;
  kitty = import ./kitty.nix;
  nextcloud-client = import ./nextcloud-client.nix;
  niri = import ./niri.nix;
  noctalia = import ./noctalia.nix;
  spotify = import ./spotify.nix;
  starship = import ./starship.nix;
  thunderbird = import ./thunderbird.nix;
  tmux = import ./tmux.nix;
  vesktop = import ./vesktop.nix;
  vscode = import ./vscode.nix;
  zen-browser = import ./zen-browser.nix;
  zsh = import ./zsh.nix;
}
