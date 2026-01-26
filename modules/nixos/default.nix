# Add your reusable NixOS modules to this directory, on their own file (https://nixos.wiki/wiki/Module).
# These should be stuff you would like to share with others, not your personal configurations.
{
  # List your module files here
  # my-module = import ./my-module.nix;
  sunshine = import ./sunshine.nix;
  gaming = import ./gaming.nix;
  boot = import ./boot.nix;
  locale = import ./locale.nix;
  nh = import ./nh.nix;
  nvidia = import ./nvidia.nix;
  ollama = import ./ollama.nix;
  pipewire = import ./pipewire.nix;
  plasma = import ./plasma.nix;
  ssh = import ./ssh.nix;
  tailscale = import ./tailscale.nix;
  core-packages = import ./core-packages.nix;
  docker = import ./docker.nix;
}
