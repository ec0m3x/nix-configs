{
  config,
  pkgs,
  ...
}: {
  sops.secrets.hermes_environment = {
    owner = "hermes";
    group = "hermes";
    mode = "0400";
    restartUnits = ["hermes-dashboard.service"];
  };

  users.groups.hermes.gid = 1001;
  users.users.hermes = {
    isNormalUser = true;
    uid = 1001;
    group = "hermes";
    home = "/home/hermes";
    createHome = true;
    shell = pkgs.bashInteractive;
  };

  # The restored uv-managed CPython and its venv originate from Debian.
  # nix-ld supplies the conventional ELF interpreter and common libraries
  # without modifying the preserved Hermes installation.
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib
      zlib
      openssl
      libffi
      sqlite
    ];
  };

  systemd.services.hermes-dashboard = {
    description = "Hermes Agent Web Dashboard";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target"];
    wants = ["network-online.target"];
    unitConfig.ConditionPathIsExecutable = "/home/hermes/.local/bin/hermes";
    serviceConfig = {
      Type = "simple";
      User = "hermes";
      Group = "hermes";
      UMask = "0077";
      WorkingDirectory = "/home/hermes";
      ExecStart = "/home/hermes/.local/bin/hermes dashboard --host 10.20.50.11 --port 9119 --no-open";
      EnvironmentFile = config.sops.secrets.hermes_environment.path;
      Restart = "on-failure";
      RestartSec = 5;
      ProtectProc = "invisible";
      ProcSubset = "pid";
      MemoryHigh = "2G";
      MemoryMax = "3G";
    };
  };

  networking.firewall.interfaces.lan0.allowedTCPPorts = [9119];
}
