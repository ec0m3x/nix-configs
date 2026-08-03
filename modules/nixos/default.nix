# Add your reusable NixOS modules to this directory, on their own file (https://nixos.wiki/wiki/Module).
# These should be stuff you would like to share with others, not your personal configurations.
{
  # List your module files here
  # my-module = import ./my-module.nix;
  ava = import ./ava.nix;
  boot = import ./boot.nix;
  cloudflared = import ./cloudflared.nix;
  comfyui = import ./comfyui.nix;
  core-packages = import ./core-packages.nix;
  docker = import ./docker.nix;
  forgejo = import ./forgejo.nix;
  gaming = import ./gaming.nix;
  haos-vm = import ./haos-vm.nix;
  haushaltsbuch = import ./haushaltsbuch.nix;
  homelab-gitops = import ./homelab-gitops.nix;
  homelab-metrics = import ./homelab-metrics.nix;
  homepage-dashboard = import ./homepage-dashboard.nix;
  latex = import ./latex.nix;
  homelab-backup = import ./homelab-backup.nix;
  immich = import ./immich.nix;
  llama-swap = import ./llama-swap.nix;
  locale = import ./locale.nix;
  litellm = import ./litellm.nix;
  nextcloud = import ./nextcloud.nix;
  nh = import ./nh.nix;
  niri = import ./niri.nix;
  nvidia = import ./nvidia.nix;
  ollama = import ./ollama.nix;
  open-webui = import ./open-webui.nix;
  offline-backup-mirror = import ./offline-backup-mirror.nix;
  paperless = import ./paperless.nix;
  pipewire = import ./pipewire.nix;
  restic-target = import ./restic-target.nix;
  samba = import ./samba.nix;
  searxng = import ./searxng.nix;
  ssh = import ./ssh.nix;
  stirling-pdf = import ./stirling-pdf.nix;
  sunshine = import ./sunshine.nix;
  tailscale = import ./tailscale.nix;
  traefik = import ./traefik.nix;
  vaultwarden = import ./vaultwarden.nix;
  wolow-companion = import ./wolow-companion.nix;
  wolf = import ./wolf.nix;
}
