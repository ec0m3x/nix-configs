# Homepage — zentraler Einstiegspunkt ins Homelab.
#
# Läuft auf hl02 neben Traefik und bindet deshalb nur auf Loopback, genau wie
# searxng (8081), stirling-pdf (8082) und vaultwarden (8222). Port 8083, weil
# der nixpkgs-Default 8082 mit Stirling-PDF kollidieren würde.
#
# Die gesamte Konfiguration ist deklarativ: das nixpkgs-Modul rendert
# settings/services/widgets/bookmarks als YAML nach /etc/homepage-dashboard/.
# Es gibt keinen State, der gesichert werden müsste (homelab-backup.nix braucht
# also keinen Eintrag).
#
# Konvention der Dienst-Einträge:
#   href        = die schöne HTTPS-URL über Traefik (das, was der Mensch nutzt)
#   siteMonitor = die interne Backend-URL (der Statuscheck läuft damit nicht
#                 über Traefik/TLS in sich selbst zurück)
{pkgs, ...}: let
  dashboardHost = "dash.hl.sk4i.com";
  listenPort = 8083;

  glancesPort = 61208;
  glancesUrl = address: "http://${address}:${toString glancesPort}";

  # Auslastungs-Kachel je Host. `version = 4` ist für Glances 4.x zwingend,
  # sonst fragt Homepage /api/3 ab und bekommt nur 404.
  mkGlancesWidget = label: address: disks: {
    glances = {
      inherit label;
      url = glancesUrl address;
      version = 4;
      cpu = true;
      mem = true;
      uptime = true;
      cputemp = true;
      # Sensor-Label der Intel-CPUs in hl01–hl03 (coretemp).
      cpuSensorLabel = "Package id";
      disk = disks;
      diskUnits = "bytes";
      expanded = true;
    };
  };

  # Dateisystem-Kachel für die Host-Gruppe weiter unten.
  mkFsWidget = address: mountpoint: {
    type = "glances";
    url = glancesUrl address;
    version = 4;
    metric = "fs:${mountpoint}";
    chart = false;
    diskUnits = "bytes";
  };
in {
  services.homepage-dashboard = {
    enable = true;
    package = pkgs.homepage-dashboard;
    inherit listenPort;
    openFirewall = false;

    # Homepage validiert den Host-Header. Der Default deckt nur
    # localhost:8082 ab — der von Traefik durchgereichte Name muss explizit
    # hier stehen, sonst liefert die App ausschließlich Host-Validation-Fehler.
    allowedHosts = "${dashboardHost},localhost:${toString listenPort},127.0.0.1:${toString listenPort}";

    settings = {
      title = "sk4i Homelab";
      description = "Central entry point for the sk4i homelab";
      language = "en";
      theme = "dark";
      color = "slate";
      headerStyle = "boxedWidgets";
      statusStyle = "dot";
      target = "_blank";
      useEqualHeights = true;
      hideVersion = true;

      # Reihenfolge und Spaltenzahl der Gruppen aus `services` unten.
      layout = {
        Infrastructure = {
          style = "column";
          columns = 4;
        };
        Productivity = {
          style = "column";
          columns = 4;
        };
        AI = {
          style = "column";
          columns = 4;
        };
        Hosts = {
          style = "column";
          columns = 4;
        };
      };

      quicklaunch = {
        provider = "custom";
        url = "https://search.hl.sk4i.com/search?q=";
        target = "_blank";
        searchDescriptions = true;
      };
    };

    # Kopfzeile: Suche, Auslastung aller drei Hosts, Wetter, Uhr.
    widgets = [
      {
        search = {
          provider = "custom";
          url = "https://search.hl.sk4i.com/search?q=";
          target = "_blank";
        };
      }
      # Mountpoints laut hosts/hl0*/disko.nix.
      (mkGlancesWidget "hl01" "10.20.50.11" ["/" "/srv"])
      (mkGlancesWidget "hl02" "10.20.50.12" ["/"])
      # /srv/backup ist die restic-Ziel-SSD (nofail): fehlt sie, meldet die
      # Kachel einen Fehler — genau das will man hier sehen.
      (mkGlancesWidget "hl03" "10.20.50.13" ["/" "/srv" "/srv/backup"])
      {
        openmeteo = {
          label = "Weikersheim";
          latitude = "49.4783";
          longitude = "9.8967";
          timezone = "Europe/Berlin";
          units = "metric";
          cache = 5;
        };
      }
      {
        datetime = {
          text_size = "xl";
          locale = "en-GB";
          format = {
            dateStyle = "long";
            timeStyle = "short";
            hourCycle = "h23";
          };
        };
      }
    ];

    services = [
      {
        Infrastructure = [
          {
            "AdGuard Home" = {
              icon = "adguard-home.png";
              href = "https://dns.hl.sk4i.com";
              description = "DNS resolver and ad blocking";
              siteMonitor = "http://10.20.50.49:80";
            };
          }
          {
            "Home Assistant" = {
              icon = "home-assistant.png";
              href = "https://ha.hl.sk4i.com";
              description = "Home automation (HAOS VM on hl01)";
              siteMonitor = "http://10.20.50.14:8123";
            };
          }
          {
            Vaultwarden = {
              icon = "vaultwarden.png";
              href = "https://vault.hl.sk4i.com";
              description = "Password manager";
              siteMonitor = "http://127.0.0.1:8222";
            };
          }
        ];
      }
      {
        Productivity = [
          {
            Nextcloud = {
              icon = "nextcloud.png";
              # Kein interner Router: Nextcloud würde cloud.hl.sk4i.com als
              # untrusted domain ablehnen (siehe nextcloud.nix).
              href = "https://cloud.sk4i.com";
              description = "Files, calendar and contacts";
              siteMonitor = "http://10.20.50.13:80";
            };
          }
          {
            Immich = {
              icon = "immich.png";
              href = "https://photos.hl.sk4i.com";
              description = "Photo and video library";
              siteMonitor = "http://10.20.50.11:2283";
            };
          }
          {
            Forgejo = {
              icon = "forgejo.png";
              href = "https://git.hl.sk4i.com";
              description = "Git forge";
              siteMonitor = "http://10.20.50.13:3000";
            };
          }
          {
            Paperless = {
              icon = "paperless-ngx.png";
              href = "https://docs.hl.sk4i.com";
              description = "Document archive";
              siteMonitor = "http://10.20.50.11:8000";
            };
          }
          {
            Haushaltsbuch = {
              icon = "mdi-cash-multiple";
              href = "https://hb.hl.sk4i.com";
              description = "Household budget";
              siteMonitor = "http://10.20.50.11:8787";
            };
          }
          {
            "Stirling PDF" = {
              icon = "stirling-pdf.png";
              href = "https://pdf.hl.sk4i.com";
              description = "PDF toolbox";
              siteMonitor = "http://127.0.0.1:8082";
            };
          }
          {
            SearXNG = {
              icon = "searxng.png";
              href = "https://search.hl.sk4i.com";
              description = "Metasearch engine";
              siteMonitor = "http://127.0.0.1:8081";
            };
          }
        ];
      }
      {
        AI = [
          {
            "Open WebUI" = {
              icon = "open-webui.png";
              href = "https://openwebui.hl.sk4i.com";
              description = "Chat frontend";
              siteMonitor = "http://10.20.50.11:8080";
            };
          }
          {
            LiteLLM = {
              icon = "mdi-router-network";
              href = "https://litellm.hl.sk4i.com";
              description = "LLM proxy and API gateway";
              siteMonitor = "http://10.20.50.13:4000/health/liveliness";
            };
          }
          {
            Ollama = {
              icon = "ollama.png";
              href = "https://ollama.hl.sk4i.com";
              description = "Local models on nix-ai";
              siteMonitor = "http://10.20.50.20:11434";
            };
          }
          {
            "llama-swap" = {
              icon = "mdi-swap-horizontal";
              href = "https://llama.hl.sk4i.com";
              description = "llama.cpp model switcher on nix-ai";
              siteMonitor = "http://10.20.50.20:9292";
            };
          }
        ];
      }
      {
        # Host-Status. Bewusst `siteMonitor` gegen die Glances-API statt `ping`:
        # der homepage-dashboard-Unit fehlt unter DynamicUser CAP_NET_RAW.
        Hosts = [
          {
            hl01 = {
              icon = "mdi-server";
              description = "Applications — Immich, Paperless, Open WebUI, Ava, HAOS";
              siteMonitor = glancesUrl "10.20.50.11";
              widgets = [
                (mkFsWidget "10.20.50.11" "/")
                (mkFsWidget "10.20.50.11" "/srv")
              ];
            };
          }
          {
            hl02 = {
              icon = "mdi-server";
              description = "Edge — Traefik, AdGuard, Vaultwarden, SearXNG";
              siteMonitor = glancesUrl "10.20.50.12";
              widgets = [(mkFsWidget "10.20.50.12" "/")];
            };
          }
          {
            hl03 = {
              icon = "mdi-server";
              description = "Cloud and data — Nextcloud, LiteLLM, restic target";
              siteMonitor = glancesUrl "10.20.50.13";
              widgets = [
                (mkFsWidget "10.20.50.13" "/")
                (mkFsWidget "10.20.50.13" "/srv")
                (mkFsWidget "10.20.50.13" "/srv/backup")
              ];
            };
          }
        ];
      }
    ];

    bookmarks = [
      {
        Admin = [
          {
            "nix-configs" = [
              {
                abbr = "GH";
                href = "https://github.com/ec0m3x/nix-configs";
              }
            ];
          }
          {
            Cloudflare = [
              {
                abbr = "CF";
                href = "https://dash.cloudflare.com";
              }
            ];
          }
          {
            Tailscale = [
              {
                abbr = "TS";
                href = "https://login.tailscale.com/admin/machines";
              }
            ];
          }
          {
            Router = [
              {
                abbr = "RT";
                href = "http://10.20.50.1";
              }
            ];
          }
          {
            "NixOS Search" = [
              {
                abbr = "NX";
                href = "https://search.nixos.org/options";
              }
            ];
          }
        ];
      }
    ];
  };

  # Next.js bindet ohne HOSTNAME an 0.0.0.0. hl02 führt tailscale0 als
  # trustedInterfaces, deshalb explizit auf Loopback festnageln —
  # allowedHosts ist nur die zweite Verteidigungslinie.
  systemd.services.homepage-dashboard.environment.HOSTNAME = "127.0.0.1";
}
