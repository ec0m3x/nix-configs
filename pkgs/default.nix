# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example'
pkgs: {
  vaultwarden-1_37_1 = pkgs.callPackage ./vaultwarden-1_37_1 {};
  wolow-companion = pkgs.callPackage ./wolow-companion {};
}
