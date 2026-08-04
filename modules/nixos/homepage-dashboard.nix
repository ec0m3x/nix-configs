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

      # Karten bekommen backdrop-blur. Zusammen mit den halbtransparenten
      # Flächen aus customCSS ergibt das den Glas-Look; nur deshalb darf
      # unten kein Hintergrundbild mit blur/saturate/brightness dazukommen —
      # die beiden Optionen schließen sich in Homepage aus.
      cardBlur = "md";

      # Reihenfolge und Form der Gruppen aus `services` unten.
      #
      # Bewusst eine Liste und kein Attrset: Homepage sortiert die Gruppen nach
      # der Reihenfolge im layout-Block, Nix gibt Attributnamen aber immer
      # alphabetisch aus. Als Attrset stünde hier also AI, Hosts,
      # Infrastructure, Productivity — und Hosts (volle Breite) mitten im
      # Umbruch zerreißt die Zeilen der Spalten-Gruppen. Die Listenform mit je
      # einem Schlüssel pro Eintrag löst Homepage wieder zu genau diesem
      # Objekt auf (utils/config/config.js).
      #
      # `columns` wirkt ausschließlich bei `style = "row"` (siehe
      # components/services/list.jsx); Spalten-Gruppen ordnet Homepage selbst
      # per Breakpoint an (1 / 2 / 3 / 4 ab md/lg/xl) und ist damit auf dem
      # Handy schon einspaltig. Hosts ist als Zeile gesetzt: die drei
      # metriklastigen Kacheln stehen unten über die volle Breite
      # nebeneinander statt gequetscht in einer Viertelspalte.
      layout = [
        {Infrastructure.style = "column";}
        {Productivity.style = "column";}
        {AI.style = "column";}
        {
          Hosts = {
            style = "row";
            columns = 3;
          };
        }
        # Die Bookmark-Gruppe aus `bookmarks` unten. Ohne Eintrag hier hängt
        # Homepage sie als eigener Block ans Seitenende, wo die fünf Links über
        # die volle Breite auseinandergezogen werden; als Zeile bilden sie den
        # Abschluss unter den Hosts.
        {
          Admin = {
            style = "row";
            columns = 5;
          };
        }
      ];

      quicklaunch = {
        provider = "custom";
        url = "https://search.hl.sk4i.com/search?q=";
        target = "_blank";
        searchDescriptions = true;
        # Ohne diese Option rendert Homepage den Such-Button für Touch-Geräte
        # gar nicht — auf dem Handy gibt es keine Tastatur, die Quicklaunch
        # sonst öffnen könnte.
        mobileButtonPosition = "bottom-right";
      };
    };

    # Dark-Glass-Theme. Landet als /etc/homepage-dashboard/custom.css und wird
    # von Homepage selbst als letztes Stylesheet eingebunden.
    #
    # Die Klassen unten stammen aus dem Upstream-Markup von Homepage 1.12
    # (src/components/services/item.jsx, group.jsx, bookmarks/item.jsx,
    # widgets/widget/container*.jsx) — nur diese semantischen Hooks sind
    # stabil, die Tailwind-Utilities daneben nicht.
    #
    # Jede Regel, die gegen eine Tailwind-Utility ankommen muss, hängt an
    # einer Container-ID (#layout-groups für Gruppen aus `layout`, #bookmarks,
    # #information-widgets): ID schlägt Klasse, damit ist die Ladereihenfolge
    # der Stylesheets egal und es braucht kein !important.
    #
    # Das Dashboard ist per `theme = "dark"` fest dunkel, deshalb gibt es hier
    # bewusst keine Light-Variante.
    customCSS = ''
      /* ---------- Palette ----------
         html trägt .dark und .theme-slate (siehe styles/theme.css). Zwei
         Klassen plus Element schlagen die Upstream-Defaults, ohne die
         Farbverläufe der Icons oder den Theme-Wechsel zu brechen:
         --bg-color  = Seitenfläche, --color-logo-* = alle Masken-Icons
         (mdi-*, si-*), --scrollbar-* = Scrollleiste. */
      html.theme-slate.dark {
        --bg-color: 7 10 18;
        --color-logo-start: 167 139 250;
        --color-logo-stop: 56 189 248;
        --scrollbar-thumb: rgb(167 139 250 / 0.35);
        --scrollbar-track: transparent;
      }

      :root {
        --sk-accent: 167 139 250; /* violet-400 */
        --sk-accent2: 56 189 248; /* sky-400 */
        --sk-glass: 12 16 28;
        --sk-radius: 14px;
      }

      /* ---------- Hintergrund ----------
         Aurora und Raster sind Pseudo-Elemente von body: die liegen im
         Stacking-Kontext über der Farbfläche von #__next (positioniert
         schlägt in-flow) und unter dem Seiteninhalt (der trägt z-10).
         body scrollt nicht — gescrollt wird #inner_wrapper —, deshalb
         bleiben beide Layer stehen und kosten kein Repaint. */
      body::before,
      body::after {
        content: "";
        position: fixed;
        z-index: 0;
        pointer-events: none;
      }

      body::before {
        inset: -25vmax;
        background:
          radial-gradient(35vmax 35vmax at 20% 12%, rgb(var(--sk-accent) / 0.22), transparent 62%),
          radial-gradient(30vmax 30vmax at 82% 6%, rgb(var(--sk-accent2) / 0.18), transparent 64%),
          radial-gradient(42vmax 42vmax at 62% 94%, rgb(217 70 239 / 0.12), transparent 66%);
        animation: sk-drift 44s ease-in-out infinite alternate;
      }

      body::after {
        inset: 0;
        background-image:
          linear-gradient(to right, rgb(255 255 255 / 0.04) 1px, transparent 1px),
          linear-gradient(to bottom, rgb(255 255 255 / 0.04) 1px, transparent 1px);
        background-size: 54px 54px;
        -webkit-mask-image: radial-gradient(125% 85% at 50% 0%, #000 28%, transparent 76%);
        mask-image: radial-gradient(125% 85% at 50% 0%, #000 28%, transparent 76%);
      }

      @keyframes sk-drift {
        from {
          transform: translate3d(-2%, -1%, 0) scale(1);
        }
        to {
          transform: translate3d(3%, 2%, 0) scale(1.08);
        }
      }

      @keyframes sk-pulse {
        50% {
          opacity: 0.3;
        }
      }

      /* ---------- Gruppen-Header ----------
         Der Disclosure-Button ist eine Flex-Zeile mit [Icon] h2 [Pfeil].
         h2 wird zum Flex-Item mit Restbreite, dann kann ::before den
         Akzentpunkt und ::after die Haarlinie bis zum Pfeil setzen. */
      :is(#layout-groups, #services, #bookmarks) h2:is(.service-group-name, .bookmark-group-name) {
        display: flex;
        flex: 1 1 auto;
        align-items: center;
        gap: 0.65rem;
        font-size: 0.78rem;
        font-weight: 600;
        letter-spacing: 0.2em;
        text-transform: uppercase;
        color: rgb(var(--color-200) / 0.9);
      }

      :is(#layout-groups, #services, #bookmarks) h2:is(.service-group-name, .bookmark-group-name)::before {
        content: "";
        flex: 0 0 auto;
        width: 6px;
        height: 6px;
        border-radius: 999px;
        background: rgb(var(--sk-accent));
        box-shadow:
          0 0 0 3px rgb(var(--sk-accent) / 0.15),
          0 0 12px 2px rgb(var(--sk-accent) / 0.55);
      }

      :is(#layout-groups, #services, #bookmarks) h2:is(.service-group-name, .bookmark-group-name)::after {
        content: "";
        flex: 1 1 auto;
        height: 1px;
        background: linear-gradient(
          to right,
          rgb(var(--sk-accent) / 0.35),
          rgb(255 255 255 / 0.07) 38%,
          transparent
        );
      }

      /* ---------- Karten ---------- */
      :is(#layout-groups, #services) .service-card,
      #bookmarks .bookmark > a {
        border: 1px solid rgb(255 255 255 / 0.07);
        border-radius: var(--sk-radius);
        background:
          linear-gradient(158deg, rgb(255 255 255 / 0.07), rgb(255 255 255 / 0.02) 58%),
          rgb(var(--sk-glass) / 0.55);
        box-shadow:
          inset 0 1px 0 rgb(255 255 255 / 0.06),
          0 10px 26px -16px rgb(0 0 0 / 0.9);
        transition:
          transform 180ms ease,
          border-color 180ms ease,
          box-shadow 180ms ease,
          background 180ms ease;
      }

      /* Nur für echte Zeigergeräte: auf Touch bleibt :hover nach dem Tap
         kleben, und ein angehobenes Kärtchen ohne Grund sieht kaputt aus. */
      @media (hover: hover) {
        :is(#layout-groups, #services) .service-card:hover,
        #bookmarks .bookmark > a:hover {
          transform: translateY(-2px);
          border-color: rgb(var(--sk-accent) / 0.45);
          background:
            linear-gradient(158deg, rgb(var(--sk-accent) / 0.14), rgb(255 255 255 / 0.03) 60%),
            rgb(var(--sk-glass) / 0.62);
          box-shadow:
            inset 0 1px 0 rgb(255 255 255 / 0.08),
            0 0 0 1px rgb(var(--sk-accent) / 0.18),
            0 18px 40px -20px rgb(var(--sk-accent) / 0.55);
        }
      }

      :is(#layout-groups, #services) .service-card :focus-visible,
      #bookmarks .bookmark > a:focus-visible {
        outline: 2px solid rgb(var(--sk-accent) / 0.8);
        outline-offset: 2px;
        border-radius: 8px;
      }

      /* Icon sitzt auf einer eigenen Fliese statt frei in der Zeile. */
      :is(#layout-groups, #services) .service-icon {
        margin: 0.35rem 0 0.35rem 0.35rem;
        border-radius: 10px;
        background: rgb(255 255 255 / 0.04);
        box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.05);
      }

      :is(#layout-groups, #services) .service-name {
        font-weight: 600;
      }

      :is(#layout-groups, #services) .service-description {
        margin-top: 0.15rem;
        color: rgb(var(--color-300) / 0.62);
      }

      /* In der Zeilen-Anordnung bricht ein zweiteiliger Name („NixOS Search")
         um und macht die ganze Grid-Zeile höher als die übrigen Kacheln. Die
         Beschreibung daneben kürzt Homepage schon selbst. */
      :is(#layout-groups, #bookmarks) .bookmark-name {
        white-space: nowrap;
      }

      :is(#layout-groups, #bookmarks) .bookmark-icon {
        border-radius: calc(var(--sk-radius) - 1px) 0 0 calc(var(--sk-radius) - 1px);
        background: rgb(255 255 255 / 0.05);
        color: rgb(var(--sk-accent));
        letter-spacing: 0.08em;
      }

      /* ---------- Status ----------
         Die Zustandsfarbe steckt bei statusStyle = "dot" als Tailwind-Klasse
         am Punkt selbst (bg-emerald-500 / bg-rose-500 / bg-white bei noch
         unbekanntem Status), eine semantische Klasse gibt es dafür nicht —
         daher Teilstring-Selektoren auf das class-Attribut. */
      :is(.site-monitor-status, .docker-status) > div[class*="bg-emerald"] {
        box-shadow:
          0 0 0 3px rgb(16 185 129 / 0.14),
          0 0 10px 1px rgb(16 185 129 / 0.75);
      }

      :is(.site-monitor-status, .docker-status) > div[class*="bg-rose"] {
        box-shadow:
          0 0 0 3px rgb(244 63 94 / 0.16),
          0 0 10px 1px rgb(244 63 94 / 0.8);
        animation: sk-pulse 1.6s ease-in-out infinite;
      }

      :is(.site-monitor-status, .docker-status) > div[class*="bg-white"],
      :is(.site-monitor-status, .docker-status) > div[class*="bg-black"] {
        animation: sk-pulse 2.4s ease-in-out infinite;
      }

      /* ---------- Kopfzeile ----------
         headerStyle = "boxedWidgets" gibt jedem Widget eine eigene Box. Je
         nach Widget ist der Container ein div, ein a oder ein form, deshalb
         alle drei Hooks. */
      #information-widgets :is(.widget-container, .information-widget-link, .information-widget-form) {
        border: 1px solid rgb(255 255 255 / 0.07);
        border-radius: var(--sk-radius);
        background:
          linear-gradient(158deg, rgb(255 255 255 / 0.06), rgb(255 255 255 / 0.02) 60%),
          rgb(var(--sk-glass) / 0.5);
        box-shadow:
          inset 0 1px 0 rgb(255 255 255 / 0.05),
          0 10px 26px -18px rgb(0 0 0 / 0.9);
      }

      /* Suche, Wetter und Uhr sammelt Homepage in #information-widgets-right
         und rendert sie hinter den Auslastungs-Kacheln. Als Kopfzeile gehören
         sie nach oben und auf eine eigene Zeile — ohne die 100 %-Basis teilen
         sie sich die Zeile mit den Auslastungs-Kacheln und alles wird
         gequetscht. */
      #widgets-wrap > #information-widgets-right {
        order: -1;
        flex: 1 1 100%;
      }

      /* Die drei Auslastungs-Kacheln teilen sich eine Zeile zu gleichen
         Teilen. Ohne Basis wachsen sie nach Inhalt und ergeben eine Treppe,
         weil jeder Host unterschiedlich viele Dateisysteme meldet. */
      #widgets-wrap > .information-widget-link {
        flex: 1 1 0;
        min-width: 0;
      }

      /* Hostname unter der Auslastungs-Kachel. */
      #information-widgets .information-widget-label {
        margin-top: 0.4rem;
        padding-top: 0.35rem;
        border-top: 1px solid rgb(255 255 255 / 0.06);
        font-size: 0.66rem;
        letter-spacing: 0.18em;
        text-transform: uppercase;
        color: rgb(var(--sk-accent) / 0.85);
      }

      :is(#information-widgets, #layout-groups, #services) .resource-usage {
        background: rgb(255 255 255 / 0.08);
      }

      :is(#information-widgets, #layout-groups, #services) .resource-usage > div {
        background: linear-gradient(90deg, rgb(var(--sk-accent2)), rgb(var(--sk-accent)));
        box-shadow: 0 0 8px rgb(var(--sk-accent) / 0.45);
      }

      #information-widgets .information-widget-search input {
        border-color: rgb(255 255 255 / 0.09);
        border-radius: 10px;
        background: rgb(255 255 255 / 0.05);
      }

      #information-widgets .information-widget-datetime span {
        font-variant-numeric: tabular-nums;
      }

      /* Uhr als Blickfang. Nur wo background-clip: text trägt — sonst bliebe
         transparenter Text ohne Verlauf übrig, also unsichtbar. */
      @supports (-webkit-background-clip: text) or (background-clip: text) {
        #information-widgets .information-widget-datetime span {
          background: linear-gradient(100deg, rgb(var(--color-200)), rgb(var(--sk-accent)));
          -webkit-background-clip: text;
          background-clip: text;
          color: transparent;
        }
      }

      /* ---------- Quicklaunch ----------
         Der Dialog und der Mobil-Button hängen an keiner ID; beim Button
         reicht Element + zwei Klassen gegen die Utilities, beim Dialog wird
         [class] als Attribut-Selektor mitgezählt. */
      [role="dialog"] dialog[class] {
        border: 1px solid rgb(255 255 255 / 0.09);
        border-radius: var(--sk-radius);
        background: rgb(9 12 22 / 0.92);
        box-shadow: 0 30px 80px -30px rgb(0 0 0 / 0.95);
        backdrop-filter: blur(16px);
      }

      [role="dialog"] dialog input {
        border-color: rgb(255 255 255 / 0.08);
        background: transparent;
      }

      button.fixed.rounded-full {
        padding: 0.85rem;
        color: #fff;
        border: 1px solid rgb(255 255 255 / 0.18);
        background: linear-gradient(140deg, rgb(var(--sk-accent)), rgb(var(--sk-accent2)));
        box-shadow: 0 12px 30px -10px rgb(var(--sk-accent) / 0.75);
        /* Randlose Displays: der Button soll nicht unter der Home-Leiste liegen. */
        margin-bottom: env(safe-area-inset-bottom);
        margin-right: env(safe-area-inset-right);
      }

      #footer {
        opacity: 0.7;
        transition: opacity 200ms ease;
      }

      #footer:hover {
        opacity: 1;
      }

      /* ---------- Mobil ---------- */
      @media (max-width: 640px) {
        /* Homepage nutzt m-4/m-5 — auf 360 px Breite ist das Rand statt Inhalt. */
        #information-widgets,
        #tabs {
          margin: 0.75rem 0.75rem 0;
        }

        #layout-groups,
        #services,
        #bookmarks {
          margin: 0.75rem;
        }

        #footer {
          padding: 1.25rem 0.75rem calc(1.25rem + env(safe-area-inset-bottom));
        }

        /* Jede Kachel über die volle Breite; Suche breit, darunter Wetter und
           Uhr als Paar. Die Selektoren müssen die Desktop-Regeln oben genau
           spiegeln: eine Media Query erhöht die Spezifität nicht, ein
           `> *` würde gegen `> .information-widget-link` verlieren. */
        #widgets-wrap > .information-widget-link,
        #widgets-wrap > #information-widgets-right {
          flex: 1 1 100%;
        }

        #information-widgets-right > .information-widget-search {
          flex: 1 1 100%;
        }

        #information-widgets-right > .widget-container {
          flex: 1 1 calc(50% - 0.25rem);
        }

        /* Das lange Datumsformat passt in halber Breite nicht in text-xl. */
        #information-widgets .information-widget-datetime span {
          font-size: 0.95rem;
        }

        /* Die Werte einer Glances-Kachel zweispaltig statt im Flattersatz —
           das halbiert die Höhe der drei Host-Boxen. */
        #information-widgets .information-widget-resources .information-widget-resource {
          flex: 1 1 calc(50% - 0.5rem);
          margin-right: 0;
          padding-top: 0.25rem;
          padding-bottom: 0.25rem;
        }

        /* Fingerfreundliche Trefferflächen. */
        :is(#layout-groups, #services) .service-title {
          min-height: 3.25rem;
        }

        #bookmarks .bookmark > a {
          min-height: 2.75rem;
        }

        /* iOS zoomt in Eingabefelder unter 16 px hinein und kommt nicht von
           allein zurück. */
        [role="dialog"] dialog input,
        #information-widgets input {
          font-size: 16px;
        }

        body::after {
          background-size: 38px 38px;
        }
      }

      /* ---------- Bewegung ---------- */
      @media (prefers-reduced-motion: reduce) {
        *,
        *::before,
        *::after {
          animation-duration: 0.01ms !important;
          animation-iteration-count: 1 !important;
          transition-duration: 0.01ms !important;
        }
      }
    '';

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
