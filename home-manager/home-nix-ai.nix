# Host-spezifische Home-Config für nix-ai (NixOS, x86_64-linux).
# Headless-Betrieb — Desktop-Module sind bewusst nicht enthalten.
# Die Moduldateien existieren weiter unter modules/home-manager/ und
# können bei Bedarf hier einklinkt werden.
{
  inputs,
  ...
}: {
  imports = [
    ./home.nix
  ];
}
