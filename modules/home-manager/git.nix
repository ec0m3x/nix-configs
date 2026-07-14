{pkgs, ...}: {
  programs.git = {
    enable = true;
    settings.user = {
      name = "ecomex";
      email = "ec0m3x@users.noreply.github.com";
    };
  };
  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "ssh";
    };
  };
}
