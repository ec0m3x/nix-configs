# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example'
pkgs: {
  wolow-companion = pkgs.callPackage ./wolow-companion { };
}
