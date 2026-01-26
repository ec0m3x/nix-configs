{ pkgs, config, ... }:
{
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  # Add docker-compose and related tools
  environment.systemPackages = with pkgs; [
    docker-compose
  ];

  # Add user to docker group
  users.users.ecomex.extraGroups = [ "docker" ];
}
