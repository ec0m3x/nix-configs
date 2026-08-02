{
  config,
  pkgs,
  ...
}: {
  sops.secrets.hermes_environment = {
    owner = "hermes";
    group = "hermes";
    mode = "0400";
    restartUnits = [
      "hermes-dashboard.service"
      "hermes-gateway.service"
    ];
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
    path = [
      pkgs.bash
      pkgs.nodejs
    ];
    preStart = ''
      export PATH="${pkgs.bash}/bin:${pkgs.nodejs}/bin:$PATH"
      if [[ ! -f /home/hermes/.hermes/hermes-agent/hermes_cli/web_dist/index.html ]]; then
        cd /home/hermes/.hermes/hermes-agent/web
        npm run build
      fi
    '';
    script = ''
      export PATH="${pkgs.bash}/bin:${pkgs.nodejs}/bin:$PATH"
      exec /home/hermes/.local/bin/hermes dashboard \
        --host 10.20.50.11 \
        --port 9119 \
        --no-open
    '';
    unitConfig.ConditionFileIsExecutable = "/home/hermes/.local/bin/hermes";
    serviceConfig = {
      Type = "simple";
      User = "hermes";
      Group = "hermes";
      UMask = "0077";
      WorkingDirectory = "/home/hermes";
      EnvironmentFile = config.sops.secrets.hermes_environment.path;
      Restart = "on-failure";
      RestartSec = 5;
      ProtectProc = "invisible";
      ProcSubset = "pid";
      MemoryHigh = "2G";
      MemoryMax = "3G";
    };
  };

  # The dashboard only exposes the web UI. Messaging channels and scheduled
  # jobs are handled by the separate long-running gateway process.
  systemd.services.hermes-gateway = {
    description = "Hermes Agent Gateway";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target"];
    wants = ["network-online.target"];
    path = [
      pkgs.bash
      pkgs.coreutils
      pkgs.curl
      pkgs.git
      pkgs.nodejs
      pkgs.openssh
    ];
    environment = {
      HOME = "/home/hermes";
      HERMES_HOME = "/home/hermes/.hermes";
      VIRTUAL_ENV = "/home/hermes/.hermes/hermes-agent/venv";
    };
    script = ''
      export PATH="/home/hermes/.hermes/hermes-agent/venv/bin:/home/hermes/.local/bin:$PATH"
      exec /home/hermes/.hermes/hermes-agent/venv/bin/python3 \
        -m hermes_cli.main gateway run
    '';
    unitConfig = {
      ConditionPathExists = "/home/hermes/.hermes/hermes-agent/hermes_cli/main.py";
      StartLimitIntervalSec = 0;
    };
    serviceConfig = {
      Type = "simple";
      User = "hermes";
      Group = "hermes";
      UMask = "0077";
      WorkingDirectory = "/home/hermes/.hermes";
      EnvironmentFile = config.sops.secrets.hermes_environment.path;
      Restart = "always";
      RestartSec = 5;
      RestartForceExitStatus = 75;
      RestartPreventExitStatus = 78;
      KillMode = "mixed";
      KillSignal = "SIGTERM";
      ExecReload = "${pkgs.coreutils}/bin/kill -USR1 $MAINPID";
      ExecStopPost = "-/home/hermes/.hermes/hermes-agent/venv/bin/python3 -m gateway.cgroup_cleanup";
      TimeoutStopSec = 210;
      ProtectProc = "invisible";
      ProcSubset = "pid";
    };
  };

  networking.firewall.interfaces.lan0.allowedTCPPorts = [9119];
}
