# Ava — Hermes Agent (Nous Research), der Kategorisierungs-Agent des
# Haushaltsbuchs.
#
# Anders als beim Haushaltsbuch ist das Image hier fremder Code mit eigenem
# Releasezyklus, deshalb das offizielle Image von Docker Hub statt eines
# selbstgebauten. Gepinnt wird eine Release-Version, nicht `latest` — das
# zeigt bei diesem Projekt auf den jeweils aktuellen main-Build.
#
# Der Agent verwaltet seinen kompletten Zustand selbst unter /opt/data
# (Config, .env, Skills, Memories, Sessions). Das ist bewusst ein Volume und
# nicht deklarativ: Hermes schreibt sich im Betrieb eigene Skills, ein
# unveränderliches Installat würde gegen sein Design arbeiten. Die
# Erstkonfiguration läuft einmalig über den interaktiven Setup-Wizard.
#
# Update: neuen Digest von
#   https://hub.docker.com/v2/repositories/nousresearch/hermes-agent/tags
# holen, hier eintragen, committen — GitOps rollt aus.
{
  config,
  lib,
  ...
}: let
  # v2026.7.30
  avaImage = "docker.io/nousresearch/hermes-agent@sha256:b869e64d6496d4763d5e4fb675b5f504cb23b0e35ec9b790481a56118602b10f";

  # OpenAI-kompatibler Endpoint. Das Haushaltsbuch läuft auf demselben Host
  # ebenfalls mit --network=host und spricht ihn über Loopback an; der Server
  # bindet deshalb auf 127.0.0.1 und 8642 wird nicht in der Firewall geöffnet.
  apiPort = 8642;
in {
  sops.secrets.ava_environment = {
    mode = "0400";
    restartUnits = ["podman-ava.service"];
  };

  # Die Zugangsdaten der Modell-Anbieter schreibt der Setup-Wizard nach
  # /opt/data/.env. Hier steht nur, was beide Container teilen müssen:
  # der Schlüssel, mit dem das Haushaltsbuch den Trigger absetzt.
  sops.templates.ava_env = {
    mode = "0400";
    restartUnits = ["podman-ava.service"];
    content = ''
      ${config.sops.placeholder.ava_environment}
      API_SERVER_ENABLED=true
      API_SERVER_HOST=127.0.0.1
      API_SERVER_PORT=${toString apiPort}
      # Muss zu HERMES_MODEL in der Haushaltsbuch-Env passen — die App schickt
      # diesen Namen im Chat-Request. Ohne das gilt der Profilname.
      API_SERVER_MODEL_NAME=ava
      TZ=Europe/Berlin
    '';
  };

  # uid/gid 10000 = Service-User `hermes` im offiziellen Image. 0700 wie vom
  # Setup-Wizard angelegt — hier liegen die Provider-Credentials.
  systemd.tmpfiles.rules = [
    "d /srv/ava 0700 10000 10000 -"
  ];

  virtualisation.podman = {
    enable = lib.mkDefault true;
    autoPrune.enable = lib.mkDefault true;
  };
  virtualisation.oci-containers = {
    backend = "podman";
    containers.ava = {
      image = avaImage;
      cmd = ["gateway" "run"];
      environmentFiles = [config.sops.templates.ava_env.path];
      volumes = ["/srv/ava:/opt/data:rw"];
      extraOptions = [
        "--network=host"
        "--security-opt=no-new-privileges"
        "--memory=2g"
      ];
    };
  };
}
