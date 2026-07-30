{
  config,
  pkgs,
  ...
}: {
  sops.secrets.searxng_secret = {};
  sops.templates.searxng_env = {
    owner = "searx";
    group = "searx";
    mode = "0400";
    restartUnits = [
      "searx-init.service"
      "searx.service"
    ];
    content = ''
      SEARXNG_SECRET=${config.sops.placeholder.searxng_secret}
    '';
  };

  services.searx = {
    enable = true;
    package = pkgs.unstable.searxng;
    domain = "search.hl.sk4i.com";
    environmentFile = config.sops.templates.searxng_env.path;
    redisCreateLocally = true;
    settings = {
      use_default_settings = true;
      general = {
        debug = false;
        instance_name = "SearXNG";
        privacypolicy_url = false;
        contact_url = false;
      };
      server = {
        bind_address = "127.0.0.1";
        port = 8081;
        secret_key = "$SEARXNG_SECRET";
        limiter = false;
        image_proxy = true;
      };
      ui.static_use_hash = true;
      enabled_plugins = [
        "Hash plugin"
        "Self Information"
        "Tracker URL remover"
        "Ahmia blacklist"
      ];
      search = {
        safe_search = 2;
        autocomplete = "google";
        formats = [
          "html"
          "json"
        ];
      };
      engines = [
        {
          name = "google";
          engine = "google";
          shortcut = "gg";
          use_mobile_ui = false;
        }
        {
          name = "duckduckgo";
          engine = "duckduckgo";
          shortcut = "ddg";
          display_error_messages = true;
        }
      ];
    };
  };
}
