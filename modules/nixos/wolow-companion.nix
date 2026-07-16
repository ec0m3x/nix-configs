{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.wolow-companion;
in {
  options.services.wolow-companion = {
    enable = lib.mkEnableOption "Wolow Companion remote power management daemon";
  };

  config = lib.mkIf cfg.enable {
    # Polkit rule: allow root to execute power commands ignoring inhibitor locks
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
          var ignoreInhibitActions = [
              "org.freedesktop.login1.power-off-ignore-inhibit",
              "org.freedesktop.login1.reboot-ignore-inhibit",
              "org.freedesktop.login1.suspend-ignore-inhibit",
              "org.freedesktop.login1.hibernate-ignore-inhibit"
          ];
          if (ignoreInhibitActions.indexOf(action.id) !== -1 && subject.user === "root") {
              return polkit.Result.YES;
          }
      });
    '';

    systemd.services.wolow-companion = {
      description = "Wolow Companion - Remote control daemon";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.wolow-companion}/bin/wolow-companion";
        Restart = "on-failure";
        RestartSec = 5;
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };
  };
}
