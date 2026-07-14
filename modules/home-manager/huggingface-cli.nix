{pkgs, ...}: {
  home.packages = [pkgs.python3Packages.huggingface-hub];

  home.sessionVariables = {
    HF_HOME = "$HOME/.cache/huggingface";
  };
}
