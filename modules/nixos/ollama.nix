{ config, pkgs, ... }:
{

  systemd.tmpfiles.rules = [
    "d /data/ollama 0755 ollama users -"
  ];

  services = {
    ollama = {
      enable = true;
      package = pkgs.ollama-cuda;
      host = "[::]";
      acceleration = "cuda";
      user = "ollama";
      group = "users";
      openFirewall = true;
      models = "/data/ollama";
      loadModels = [ "llama3.2" "nomic-embed-text" ];
    };
  };
}