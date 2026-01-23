{ pkgs, ... }:
{
  programs.git = {
    enable = true;
    settings.user = {
      name = "ecomex";
      email = "ecomex@nixos";
    };
  };
  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "ssh";
    };
  };
}