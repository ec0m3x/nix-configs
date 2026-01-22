{ config, pkgs, ... }:
{

  system.activationScripts = {
    script.text = ''
      install -d -m 755 /data/ollama -o ollama -g users
    '';
  };

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