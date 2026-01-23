{ ... }:
{
  programs = {
    zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting = {
        enable = true;
      };

      history = {
        save = 10000;
        size = 10000;
        path = "$HOME/.cache/zsh_history";
      };

      shellAliases = {
        ls = "eza -gl --git --color=automatic";
        tree = "eza --tree";
        cat = "bat";

        ip = "ip --color";
        ipb = "ip --color --brief";

        gac = "git add -A  && git commit -a";
        gp = "git push";
        gst = "git status -sb";

        htop = "btm -b";
        neofetch = "fastfetch";

        ts = "tailscale";
        tst = "tailscale status";
        tsu = "tailscale up";
        tsd = "tailscale down";

        speedtest = "nix-shell -p speedtest-cli --run speedtest";

        desktop-up   = "sudo systemctl start display-manager";
        desktop-down = "sudo systemctl stop display-manager && sudo loginctl terminate-user ecomex";

        rln = "nh os switch";
        rlh = "nh home switch";
        cleanup-nix = "nh clean all --keep-since 5d --keep 3";
      };
    };
  };
}