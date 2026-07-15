{pkgs, ...}: {
  # greetd - Lightweight login manager for Wayland
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --remember-session";
      };
    };
  };

  # Enable asterisk feedback for password entry in greetd
  security.pam.services.greetd.text = ''
    # Account management.
    account required ${pkgs.linux-pam}/lib/security/pam_unix.so

    # Authentication management.
    auth optional ${pkgs.linux-pam}/lib/security/pam_unix.so likeauth nullok
    auth optional ${pkgs.gnome-keyring}/lib/security/pam_gnome_keyring.so
    auth sufficient ${pkgs.linux-pam}/lib/security/pam_unix.so likeauth nullok try_first_pass pwfeedback
    auth required ${pkgs.linux-pam}/lib/security/pam_deny.so

    # Password management.
    password sufficient ${pkgs.linux-pam}/lib/security/pam_unix.so nullok yescrypt
    password optional ${pkgs.gnome-keyring}/lib/security/pam_gnome_keyring.so use_authtok

    # Session management.
    session required ${pkgs.linux-pam}/lib/security/pam_env.so conffile=/etc/pam/environment readenv=0
    session required ${pkgs.linux-pam}/lib/security/pam_unix.so
    session required ${pkgs.linux-pam}/lib/security/pam_loginuid.so
    session optional ${pkgs.systemd}/lib/security/pam_systemd.so
    session required ${pkgs.linux-pam}/lib/security/pam_limits.so
    session optional ${pkgs.gnome-keyring}/lib/security/pam_gnome_keyring.so auto_start
  '';
}
