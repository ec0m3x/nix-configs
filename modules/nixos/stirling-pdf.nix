{pkgs, ...}: {
  services.stirling-pdf = {
    enable = true;
    package = pkgs.stirling-pdf;
    environment = {
      SERVER_ADDRESS = "127.0.0.1";
      SERVER_PORT = 8082;
      DISABLE_ADDITIONAL_FEATURES = true;
      LANGS = "de_DE";
      SYSTEM_DEFAULTLOCALE = "de-DE";
      SECURITY_ENABLELOGIN = false;
    };
  };
}
