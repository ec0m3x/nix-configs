# Gemeinsame Home-Manager-Basis für Linux und macOS. Profile wählen darüber
# hinaus nur die Module, die auf dem jeweiligen Host wirklich benötigt werden.
{
  config,
  lib,
  pkgs,
  ...
}: {
  home = {
    username = "ecomex";
    homeDirectory =
      if pkgs.stdenv.isDarwin
      then "/Users/${config.home.username}"
      else "/home/${config.home.username}";

    sessionVariables = {
      GH_CONFIG_DIR = "$HOME/.local/share/gh";
      # sops sucht den age-Key über Gos os.UserConfigDir(). Auf macOS ist das
      # ~/Library/Application Support, nicht der XDG-Pfad — ohne diese
      # Variable scheitert jedes Entschlüsseln mit "no master key was able to
      # decrypt the file", obwohl der richtige Key da liegt (vgl. die
      # gleichartige Windows-Falle in .sops.yaml). Unter Linux zeigt die
      # Variable auf genau den Ort, den sops ohnehin prüft.
      SOPS_AGE_KEY_FILE = "$HOME/.config/sops/age/keys.txt";
    };
  };

  news.display = "silent";

  # Nicely reload system units when changing configs (nur Linux).
  systemd.user.startServices = lib.mkIf pkgs.stdenv.isLinux "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "26.05";
}
