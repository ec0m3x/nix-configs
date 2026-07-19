# Host-spezifische Home-Config für nix-mac (nix-darwin, aarch64-darwin).
# Importiert die gemeinsame Basis (`home.nix`). Mac-spezifische Ergänzungen
# (andere Module, Pakete, programme.*-Optionen) hier pflegen.
{...}: {
  imports = [
    ./home.nix
  ];
}
