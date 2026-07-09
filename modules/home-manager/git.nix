{ pkgs, ... }:
{
  programs.git = {
    enable = true;
    settings.user = {
      name = "ecomex";
      email = "skoch@sks-concept.de";
    };
  };
  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "ssh";
    };
  };
}