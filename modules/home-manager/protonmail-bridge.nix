{
  config,
  lib,
  pkgs,
  ...
}: {
  # ProtonMail Bridge - local IMAP/SMTP server for Proton Mail
  # https://proton.me/mail/bridge
  home.packages = [pkgs.protonmail-bridge];

  # Run bridge as a systemd user service
  systemd.user.services.protonmail-bridge = {
    Unit = {
      Description = "ProtonMail Bridge local IMAP/SMTP server";
    };
    Service = {
      ExecStart = "${pkgs.protonmail-bridge}/bin/protonmail-bridge --cli";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install = {
      WantedBy = ["default.target"];
    };
  };
}
