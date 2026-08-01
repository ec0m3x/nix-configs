{
  config,
  lib,
  pkgs,
  ...
}: let
  tlsConfig = {
    certResolver = "cloudflare";
    domains = [
      {
        main = "hl.sk4i.com";
        sans = ["*.hl.sk4i.com"];
      }
    ];
  };

  mkServer = url: {
    loadBalancer.servers = [{inherit url;}];
  };

  mkInternalRouter = host: service: {
    rule = "Host(`${host}`)";
    entryPoints = [
      "websecure-lan"
      "websecure-tail"
    ];
    inherit service;
    tls = tlsConfig;
  };

  mkPublicRouter = host: service: {
    rule = "Host(`${host}`)";
    entryPoints = ["web-lan"];
    inherit service;
  };
in {
  sops.secrets.traefik_cloudflare_token = {};
  sops.templates.traefik_env = {
    owner = "traefik";
    group = "traefik";
    mode = "0400";
    restartUnits = ["traefik.service"];
    content = ''
      CF_DNS_API_TOKEN=${config.sops.placeholder.traefik_cloudflare_token}
    '';
  };

  services.traefik = {
    enable = true;
    package = pkgs.traefik;
    environmentFiles = [config.sops.templates.traefik_env.path];
    staticConfigOptions = {
      entryPoints = {
        web-lan = {
          address = "10.20.50.12:80";
          forwardedHeaders.trustedIPs = [
            "10.20.50.13/32"
            "10.20.50.31/32"
            "10.20.50.33/32"
          ];
        };
        websecure-lan.address = "10.20.50.12:443";
        web-tail = {
          address = "100.113.0.83:80";
          http.redirections.entryPoint = {
            to = "websecure-tail";
            scheme = "https";
          };
        };
        websecure-tail.address = "100.113.0.83:443";
      };

      certificatesResolvers.cloudflare.acme = {
        email = "admin@sk4i.com";
        storage = "/var/lib/traefik/acme.json";
        dnsChallenge = {
          provider = "cloudflare";
          # Avoid stale negative TXT caches on the local bootstrap resolver.
          resolvers = [
            "1.1.1.1:53"
            "8.8.8.8:53"
          ];
        };
      };

      log.level = "INFO";
      accessLog = {};
    };

    dynamicConfigOptions = {
      http = {
        middlewares.deny-admin.ipAllowList.sourceRange = ["127.0.0.1/32"];

        services = {
          vaultwarden = mkServer "http://127.0.0.1:8222";
          searxng = mkServer "http://127.0.0.1:8081";
          stirling-pdf = mkServer "http://127.0.0.1:8082";
          litellm = mkServer "http://10.20.50.13:4000";

          adguard = mkServer "http://10.20.50.49:80";
          ava = mkServer "http://10.20.50.11:9119";
          home-assistant = mkServer "http://10.20.50.14:8123";
          haushaltsbuch = mkServer "http://10.20.50.11:8787";
          immich = mkServer "http://10.20.50.11:2283";
          llama = mkServer "http://10.20.50.20:9292";
          ollama = mkServer "http://10.20.50.20:11434";
          open-webui = mkServer "http://10.20.50.11:8080";
          paperless = mkServer "http://10.20.50.11:8000";

          nextcloud = mkServer "http://10.20.50.13:80";
        };

        routers = {
          vaultwarden = mkInternalRouter "vault.hl.sk4i.com" "vaultwarden";
          searxng = mkInternalRouter "search.hl.sk4i.com" "searxng";
          stirling-pdf = mkInternalRouter "pdf.hl.sk4i.com" "stirling-pdf";
          litellm = mkInternalRouter "litellm.hl.sk4i.com" "litellm";

          adguard = mkInternalRouter "dns.hl.sk4i.com" "adguard";
          ava = mkInternalRouter "ava.hl.sk4i.com" "ava";
          home-assistant = mkInternalRouter "ha.hl.sk4i.com" "home-assistant";
          haushaltsbuch = mkInternalRouter "hb.hl.sk4i.com" "haushaltsbuch";
          llama = mkInternalRouter "llama.hl.sk4i.com" "llama";
          ollama = mkInternalRouter "ollama.hl.sk4i.com" "ollama";
          open-webui = mkInternalRouter "openwebui.hl.sk4i.com" "open-webui";
          paperless = mkInternalRouter "docs.hl.sk4i.com" "paperless";

          vault-public = mkPublicRouter "vault.sk4i.com" "vaultwarden";
          vault-public-secure = {
            rule = "Host(`vault.sk4i.com`)";
            entryPoints = [
              "websecure-lan"
              "websecure-tail"
            ];
            service = "vaultwarden";
            tls.certResolver = "cloudflare";
          };
          vault-public-admin =
            (mkPublicRouter "vault.sk4i.com" "vaultwarden")
            // {
              rule = "Host(`vault.sk4i.com`) && PathPrefix(`/admin`)";
              middlewares = ["deny-admin"];
              priority = 100;
            };
          cloud-public = mkPublicRouter "cloud.sk4i.com" "nextcloud";
          photos-public = mkPublicRouter "photos.sk4i.com" "immich";
        };
      };
    };
  };

  # The Tailnet address must exist before Traefik binds its Tailnet
  # entrypoints. This also makes restarts robust after boot.
  systemd.services.traefik = {
    after = lib.mkAfter ["tailscaled.service"];
    wants = lib.mkAfter ["tailscaled.service"];
    # A router/repeater outage can delay the Tailnet address for several
    # minutes after boot. Keep retrying instead of leaving Traefik failed at
    # systemd's default start limit.
    unitConfig.StartLimitIntervalSec = lib.mkForce 0;
    serviceConfig.ExecStartPre = lib.mkBefore [
      (pkgs.writeShellScript "wait-for-traefik-tailnet-address" ''
        for _ in $(${pkgs.coreutils}/bin/seq 1 300); do
          if ${pkgs.iproute2}/bin/ip -4 address show dev tailscale0 |
            ${pkgs.gnugrep}/bin/grep -q "100.113.0.83/"; then
            exit 0
          fi
          ${pkgs.coreutils}/bin/sleep 1
        done
        exit 1
      '')
    ];
  };

  networking.firewall.interfaces.lan0.allowedTCPPorts = [
    80
    443
  ];
}
