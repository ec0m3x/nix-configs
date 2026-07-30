# Homelab-Migration: Proxmox → NixOS

Migration der drei Proxmox-Mini-PCs (`pve01`–`pve03`) auf bare-metal NixOS
(`hl01`–`hl03`), zentral verwaltet über dieses Repo. Referenz für Netzplan
und bisherige Architektur: Repo `homelab-kubernetes` (wird nach Abschluss
archiviert).

## Beschlossene Architektur

- **k3s wird abgeschafft.** Dienste mit stabilen, gut gepflegten
  NixOS-Modulen werden nativ betrieben. Schnelllebige oder unter NixOS
  schwer wartbare Anwendungen dürfen als deklarative OCI-Container laufen.
  Die konkrete Betriebsform wird pro Dienst vor der Migration festgelegt.
- **Home Assistant** läuft später als VM auf hl01, nicht als nativer
  NixOS-Dienst. HAOS ist ausdrücklich nicht Teil des ersten
  Phase-4-Cutovers; Virtualisierung, Restore und USB-Passthrough folgen nach
  der Hostmigration als eigener Schritt.
- **Backups** über restic (NixOS-Module) statt PBS; Ziel: 1-TB-Platte auf hl03.
- IP-Adressen bleiben: hl01 = 10.20.50.11, hl02 = .12, hl03 = .13.
- **Tailscale läuft nativ auf allen drei NixOS-Hosts.** Das gemeinsame
  Homelab-Modul aktiviert den Dienst; Rollen und Anmeldung bleiben
  hostspezifisch. hl02 ist zusätzlich Subnet-Router für `10.20.50.0/24`.
- Secrets via sops-nix (age; Admin-Key wie im homelab-kubernetes-Repo,
  Host-Keys = SSH-Hostkeys via ssh-to-age).

## Verbindliche Go/No-Go-Gates

Vor dem Löschen oder Neuformatieren eines Proxmox-Hosts muss für die jeweilige
Phase ein Go/No-Go-Gate dokumentiert und vollständig erfüllt sein:

- aktuelles Backup aller betroffenen VMs, LXCs, Datenbanken und Nutzdaten;
- Restore-Verfahren dokumentiert und mindestens stichprobenartig verifiziert;
- Zugriff auf Quell- und Zielsystem geprüft, inklusive Notfallzugang;
- Zielkonfiguration evaluiert sowie Installations- und Rollback-Befehle
  vorbereitet;
- konkrete Rückfallmöglichkeit mit Aufbewahrungsfrist benannt;
- Abhängigkeiten und erwartete Downtime bekannt und angekündigt.

Ein Host wird nur überschrieben, wenn alle Punkte erfüllt sind. Ein
fehlgeschlagener oder nicht eindeutig prüfbarer Punkt bedeutet **No-Go**.

## Hardware

| Host | IP | RAM | Disks | NIC (MAC → `lan0`) |
|---|---|---|---|---|
| hl01 | 10.20.50.11 | 16 GiB | PM871b 256 GB (root), 860 EVO 250 GB (→ /srv) | **USB-Adapter** 00:24:9b:49:70:91 (onboard defekt/down) |
| hl02 | 10.20.50.12 | 8 GiB | 860 EVO 250 GB (root) | 64:00:6a:3e:65:e2 |
| hl03 | 10.20.50.13 | 8 GiB | LITEON 256 GB (root), 840 PRO 120 GB (→ /srv), 1 TB EXCERIA (USB, → restic) | 98:90:96:b2:db:a5 |

Alle drei: Intel i5-4590T (4 Cores), UEFI-Boot.

## Ziel-Dienstverteilung

| Host | Dienste |
|---|---|
| hl01 (16 GiB) | immich, paperless-ngx, open-webui, haushaltsbuch + honcho, ava; später Samba-NAS und Home Assistant (VM) |
| hl02 (8 GiB) | AdGuard Home, Tailscale-Subnet-Router, Vaultwarden, SearXNG, Stirling-PDF, Reverse-Proxy (Wildcard `*.hl.sk4i.com`, Tailnet-Einstieg) |
| hl03 (8 GiB) | Nextcloud, LiteLLM + Postgres, cloudflared (Cloudflare-Tunnel), restic-Backup-Ziel |

## Installation & Betrieb

- **Erstinstallation**: nixos-anywhere per kexec über SSH direkt aus dem
  laufenden Proxmox (root-SSH vorhanden). Disk-Layouts deklarativ via disko
  (`hosts/hl0X/disko.nix`). Vor jeder Installation per `--extra-files`
  einspielen: `/etc/nixos-secrets/ecomex` (Passwort-Hash) und die vorab
  generierten SSH-Hostkeys (damit sops-Secrets ab dem ersten Boot
  entschlüsselbar sind).
- **Updates**: `nixos-rebuild switch --flake .#hl0X --target-host ecomex@10.20.50.1X --sudo --ask-sudo-password`
  von nix-ai aus (Windows kann nicht bauen), oder lokal auf dem Host via nh.
- **Fallback**: Monitor + Tastatur bereithalten — bei kexec-/Boot-Problemen
  gibt es keine Remote-Konsole mehr (kein Proxmox).

## Phasen und Status

### Phase 0 — Repo-Scaffolding ✅ (2026-07-30)
- [x] flake-Inputs disko + sops-nix, nixosConfigurations hl01–hl03
- [x] hosts/homelab/common.nix (Basis), hosts/hl0X/ (configuration + disko)
- [x] .sops.yaml (Admin-Key; Host-Keys folgen je Phase)
- [x] Eval-Test aller Host-Configs via GitHub Actions (.github/workflows/check.yml)

### Phase 1 — pve02 → hl02 (AdGuard + Tailscale-Router) ✅ (2026-07-30)

**Vorbereitung:**

- [x] Buildhost nix-ai festgelegt; Root-SSH von dort auf pve02 geprüft.
- [x] Bestehenden Yescrypt-Passwort-Hash für ecomex aus nix-ai sicher für
      `--extra-files` übernommen; Format und Dateirechte geprüft.
- [x] SSH-Hostkeys für hl02 erzeugen, Public-Key via ssh-to-age in
      `.sops.yaml` eintragen und Private-Key für `--extra-files` vorbereiten.
- [x] AdGuard-Konfiguration aus LXC 106 außerhalb des Repos gesichert.
- [x] Tailscale-State aus LXC 109 gesichert und für `--extra-files`
      vorbereitet; er erhält die bestehende Node-Identität.
- [x] Aktuelle PBS-Backups von LXC 106, LXC 109 und VM 302 verifiziert.
- [x] Bestehende DNS-Fallbacks über Router/Gateway getestet.
- [x] hl02-Konfiguration evaluiert, vollständig gebaut und Disko inklusive
      UEFI-Boot mit `nixos-anywhere --vm-test` geprüft.
- [x] Passwortdatei in `--extra-files` ergänzt und finalen
      nixos-anywhere-Befehl vorbereitet.

**Gesicherte Artefakte (nicht in Git):**

- Mac: `~/.local/share/nix-configs-migration/hl02/`
- Buildhost: `/home/ecomex/.local/share/nix-configs-migration/hl02/`
- `source/AdGuardHome.yaml` — SHA-256
  `3010aec115fcae327ada55b62c6329269c6373d283f185e21685f9efdeea791c`
- `extra-files/var/lib/tailscale/tailscaled.state` — SHA-256
  `2b90c048d7e698e9e97d5112fcc505e686de7c19b53cad7a7a0c186d76f63026`
- `extra-files/etc/ssh/ssh_host_ed25519_key` — geplanter
  SSH-Fingerprint `SHA256:epexazKu2tYjyyULtmMcnrgkUVbMWhRe+lYs+e1lUUk`

**Vorbereiteter Installationsbefehl (erst nach Go):**

```bash
cd /home/ecomex/nix-configs
nix run github:nix-community/nixos-anywhere -- \
  --flake .#hl02 \
  --extra-files /home/ecomex/.local/share/nix-configs-migration/hl02/extra-files \
  root@10.20.50.12
```

Nach dem ersten Boot muss der alte Known-Hosts-Eintrag für `10.20.50.12`
entfernt und der oben dokumentierte neue Hostkey-Fingerprint geprüft werden.
AdGuard übernimmt zusätzlich zur Host-IP `.12` vorerst seine bisherige
Service-IP `.49`, sodass Router und Clients nicht gleichzeitig umgestellt
werden müssen.

**AdGuard-Restore nach dem ersten Boot:**

```bash
scp /home/ecomex/.local/share/nix-configs-migration/hl02/source/AdGuardHome.yaml \
  ecomex@10.20.50.12:/tmp/AdGuardHome.yaml
ssh ecomex@10.20.50.12
sudo systemctl stop adguardhome
sudo sh -c '
  install -m 600 /tmp/AdGuardHome.yaml \
    /var/lib/AdGuardHome/AdGuardHome.yaml
  chown --reference=/var/lib/private/AdGuardHome \
    /var/lib/AdGuardHome/AdGuardHome.yaml
'
rm /tmp/AdGuardHome.yaml
sudo systemctl start adguardhome
```

`adguardhome` ist ein dynamischer systemd-Benutzer und deshalb nach dem
Stoppen nicht per Benutzername auflösbar. Die Eigentümerschaft muss vom
persistenten State-Verzeichnis numerisch übernommen werden.

**Go/No-Go vor dem Wipe von pve02:**

- [x] Wiederherstellung von AdGuard-Konfiguration und Tailscale-Zugang ist
      nachvollziehbar dokumentiert.
- [x] Notfallzugang per Monitor und Tastatur ist verfügbar.
- [x] PBS-Restore von CT 106 wurde unter temporärer VMID 9106 geprüft;
      die wiederhergestellte AdGuard-Datei war bytegenau identisch.
- [x] Zustand und Quorum des k3s-Clusters sind gesund; API-/etcd-Readiness
      und serverseitiger Drain-Dry-Run für k3s02 waren erfolgreich.
- [x] Downtime freigegeben. Vor Disko wird bei jedem fehlgeschlagenen
      Preflight abgebrochen; danach ist der Rückfall die erneute
      Proxmox-Installation mit Restore der PBS-Sicherungen.
- [x] PBS-Sicherungen bleiben mindestens 14 Tage nach erfolgreicher Abnahme
      erhalten.
- [x] Alle Vorbereitungspunkte sind erfüllt — **Go am 2026-07-30 erteilt**.

**Durchführung und Abnahme:**

- [x] k3s02 ordnungsgemäß gedraint, aus dem Cluster entfernt und VM 302
      heruntergefahren; k3s01 und k3s03 blieben gesund.
- [x] Finale PBS-Snapshots erstellt: CT 106 `2026-07-30T16:05:26Z`,
      CT 109 `2026-07-30T16:05:43Z`, VM 302 `2026-07-30T16:05:57Z`.
- [x] pve02 mit nixos-anywhere und Disko als NixOS-Host hl02 installiert;
      UEFI-Boot, Root-Dateisystem und SSH-Hostkey geprüft.
- [x] AdGuard-Konfiguration wiederhergestellt; alte Service-IP
      `10.20.50.49`, Weboberfläche, Filter sowie DNS über UDP und TCP geprüft.
- [x] Tailscale-State und Node-Identität übernommen; Subnetzroute
      `10.20.50.0/24`, Forwarding und Tailnet-Verbindung geprüft.
- [x] Kontrollierter Neustart erfolgreich; `.12` und `.49`, SSH, AdGuard und
      Tailscale kamen ohne manuellen Eingriff zurück, keine Units fehlgeschlagen.
- [x] Remote-Build von nix-ai sowie Build und Switch auf hl02 nach Ergänzung
      des aktuellen Buildhost-SSH-Schlüssels erfolgreich getestet.
- [x] Verwaisten Proxmox-Knoten pve02 nach Sicherung der drei
      Gastdefinitionen aus Corosync und pmxcfs entfernt; Cluster wieder
      korrekt mit 2/2 Stimmen quorat, `local-lvm` nur noch auf pve03.
- [x] Rückfallfrist: Die drei finalen PBS-Sicherungen mindestens bis
      einschließlich **2026-08-13** aufbewahren.

### Phase 2 — k3s-Apps → hl02, Reverse-Proxy-Wechsel ✅ (2026-07-30)

**Live-Inventar vom 2026-07-30:**

- k3s01 und k3s03 sind `Ready`; embedded etcd hat damit nur zwei Mitglieder
  und verliert beim Ausfall eines Nodes das Quorum.
- k3s01 liegt bei 88 Prozent RAM. Die Migration der dort laufenden
  Stirling-PDF- und SearXNG-Pods hat deshalb Vorrang.
- Vaultwarden `1.37.1`: SQLite-PVC mit `Retain`, etwa 2,5 MiB Daten,
  einschließlich `db.sqlite3`, `rsa_key.pem` und Icon-Cache; Secrets:
  Admin-Token und SMTP-Zugang.
- SearXNG: zustandslos; Konfiguration und Secret-Key deklarativ, Cache und
  Valkey absichtlich flüchtig.
- Stirling-PDF `2.14.2`: zustandslos; alle vier gemounteten Verzeichnisse
  sind `emptyDir`.
- Traefik ist alleiniger TLS-Einstieg für alle `*.hl.sk4i.com`-Hosts und
  Ziel des Cloudflare-Tunnels. Die Routing-Tabelle umfasst k3s-Dienste und
  zwölf externe LAN-Backends.

**Beschlossene Betriebsform:**

- Vaultwarden nativ über das NixOS-Modul und ein isoliert gepinntes Paket
  `1.37.1` mit Web-Vault `2026.6.4`. Der vollständige Datenbestand
  (`db.sqlite3`, Schlüssel, Anhänge und Icon-Cache) sowie Admin- und
  SMTP-Secrets werden übernommen.
- SearXNG nativ über `services.searx` und `pkgs.unstable.searxng`; lokales,
  flüchtiges Valkey.
- Stirling-PDF nativ über `services.stirling-pdf` mit der stabilen
  Nixpkgs-Version `2.10.1`; es sind keine Nutzdaten zu übernehmen.
- Traefik nativ über das NixOS-Modul; vorhandene Routen bleiben konzeptionell
  gleich. Wildcard-TLS per ACME DNS-01 und Cloudflare-Token aus sops-nix.
- cloudflared bleibt bis Phase 3 auf k3s und wird beim Proxy-Cutover auf
  hl02 umgestellt.

**Vaultwarden-Datenübernahme:**

1. Für den Schattenbetrieb das Kubernetes-Deployment kurz auf null
   skalieren, den vollständigen NFS-Pfad
   `/srv/data/kubernetes/vaultwarden/vaultwarden-data` als Archiv außerhalb
   des Clusters sichern und das Deployment anschließend wieder starten.
   Eine Live-Kopie ist nicht zulässig: Die Datenbank ist auf dem NFS-Share
   während des laufenden Pods gesperrt und das Container-Image enthält kein
   `sqlite3` für einen Online-Snapshot.
2. Die gesicherte Datenbank mit `PRAGMA quick_check` prüfen, nach
   `/var/lib/vaultwarden` auf hl02 übertragen, Eigentümer und Modus auf den
   NixOS-Dienst setzen und den Dienst ausschließlich über
   `127.0.0.1:8222` testen.
3. Beim Cutover das Kubernetes-Deployment auf null skalieren, damit keine
   Schreibzugriffe mehr stattfinden. Danach das vollständige
   `/data`-Verzeichnis final synchronisieren und die kopierte Datenbank auf
   hl02 erneut mit `PRAGMA quick_check` prüfen.
4. Login, Tresor-Synchronisierung, Anhänge, Web-Vault, `/alive`,
   Admin-Zugang nur über den Tailnet-Host und SMTP testen. Erst danach
   Ingress umstellen.
5. Das gestoppte Kubernetes-Deployment und das unveränderte PVC mindestens
   bis zum Ende des Rollback-Fensters behalten. Der bereits erstellte
   Vaultwarden-Export bleibt verschlüsselt als zusätzliche Rückfallebene.

**Go/No-Go vor dem Cutover:**

- [x] Live-Ressourcen, Daten, Secret-Namen, Ingress-Routen und tatsächliche
      Versionen inventarisiert.
- [x] Betriebsform bestätigt: alle drei Apps nativ; Vaultwarden exakt
      `1.37.1`, SearXNG aus unstable, Stirling-PDF stabil.
- [x] Zielpaket und Zielmodule evaluiert; vollständiger hl02-Build inklusive
      Vaultwarden `1.37.1` erfolgreich.
- [x] Zielkonfiguration auf hl02 aktiviert und alle drei Apps ausschließlich
      über Loopback im Schattenbetrieb testen.
- [x] Externes Backupziel für die nach hl02 kopierten Vaultwarden-Daten
      einrichten und Restore testen; lokales Backup allein reicht nicht.
- [x] Frischen PBS-Snapshot von NAS-CT 210 erstellen und isolierten Restore
      testen.
- [x] Konsistenten Vaultwarden-Snapshot samt `/data` sichern,
      SQLite-Integrität prüfen und die Datenkopie auf Mac, nix-ai und hl02
      verifizieren.
- [x] Proxy parallel auf hl02 testen, ohne Wildcard-DNS oder
      Cloudflare-Tunnel zu ändern.
- [ ] Rücksynchronisierung neuer Vaultwarden-Schreibzugriffe nach k3s als
      vollständigen Post-Cutover-Rollback testen.
- [x] Vaultwarden stoppen, letzte Daten synchronisieren, Wildcard-DNS und
      Tunnelziele auf hl02 umstellen.

**Durchführung und Abnahme:**

- Vaultwarden, SearXNG, Stirling-PDF und Traefik laufen nativ auf hl02.
  Vaultwarden bindet auf `127.0.0.1:8222`, SearXNG auf `127.0.0.1:8081`
  und Stirling-PDF auf `127.0.0.1:8082`; nur Traefik ist von außen
  erreichbar.
- Schattenkopie:
  `~/.local/share/nix-configs-migration/hl02/source/vaultwarden-20260730-193040/vaultwarden-data.tar.gz`,
  SHA-256
  `467b4709740b7eb7272da5649ba5a2879b91274755c168ef8bb7526ad80fa684`;
  SQLite `quick_check` war `ok`. Login, Tresoreinträge und SMTP-Mail für
  einen neuen Geräte-Login wurden über die Zielinstanz geprüft.
- Finale Kopie nach Stoppen des Quell-Pods:
  `~/.local/share/nix-configs-migration/hl02/source/vaultwarden-final-20260730-200043/vaultwarden-data.tar.gz`,
  1.414.225 Bytes, SHA-256
  `5e14d53b04f066c43535034c25de169c9caf791915e06638487a0c1f25cc427f`.
  SHA-256 der enthaltenen `db.sqlite3`:
  `10bfea4c24a5be39b05cb53248f7f35be518bd1757a2a9324a1937fee2a31ee5`;
  SQLite `quick_check` war erneut `ok`.
- Der NixOS-Backupdienst erzeugte anschließend eine frische konsistente
  Online-Sicherung. Klartext-SHA-256:
  `93860ea7498984a894438187f6d9ad89058ef9c3160cbb45cb59861210d049e1`.
  Die externe Kopie liegt mit dem Ed25519-Schlüssel des Macs verschlüsselt
  unter
  `~/.local/share/nix-configs-migration/hl02/external-backup/vaultwarden-online-20260730-201927.tar.gz.age`;
  SHA-256 der verschlüsselten Datei:
  `48c6ebcaf0e1d75eae0c446c1a76382b0a9d84579d904b9a09c644ba1cbf07f0`.
  Entschlüsselung, Archiv-Restore, Schlüsseldatei und SQLite
  `quick_check` wurden geprüft; die temporäre Klartextkopie auf dem Mac
  wurde danach gelöscht.
- Frischer verschlüsselter PBS-Snapshot von NAS-CT 210:
  `PBS:backup/ct/210/2026-07-30T18:16:35Z`. Vollständiger Restore unter der
  temporären CT-ID 9210 ohne Netzwerkstart war erfolgreich; im Restore
  meldete Vaultwardens Datenbank `quick_check=ok` und hatte den erwarteten
  SHA-256-Wert
  `10bfea4c24a5be39b05cb53248f7f35be518bd1757a2a9324a1937fee2a31ee5`.
  CT 9210 und ihre Test-Volumes wurden anschließend entfernt.
- Das k3s-Vaultwarden-Deployment steht auf null Replikas und trägt
  `kustomize.toolkit.fluxcd.io/reconcile: disabled`. Ein manuell ausgelöster
  Flux-Reconcile ließ Deployment und Replikazahl damit unverändert. Das PVC
  bleibt mit Reclaim-Policy `Retain` als Rückfallmöglichkeit erhalten.
  SearXNG und Stirling-PDF bleiben während des Rollback-Fensters ebenfalls
  im Cluster, erhalten aber keinen Produktivverkehr mehr.
- Traefik besitzt ein Let's-Encrypt-Zertifikat für `hl.sk4i.com` und
  `*.hl.sk4i.com` sowie ein separates Zertifikat für `vault.sk4i.com`.
  Vaultwardens öffentlicher `/admin`-Pfad liefert `403`.
- Cloudflare-Tunnel-Konfiguration Version 29 leitet `cloud.sk4i.com`,
  `photos.sk4i.com` und `vault.sk4i.com` an `http://10.20.50.12:80`.
  Nextcloud, Immich und Vaultwarden wurden über den öffentlichen
  Cloudflare-Weg jeweils mit HTTP 200 geprüft.
- Der unproxied Cloudflare-A-Record `*.hl.sk4i.com` zeigt auf die neue
  Tailnet-IP `100.113.0.83`. Auflösung über die autoritativen Nameserver
  und AdGuard sowie die internen HTTPS-Routen wurden geprüft.
- Die alten Routen `npm.hl.sk4i.com` und `ha.hl.sk4i.com` wurden bewusst
  entfernt. Nginx Proxy Manager ist außer Betrieb; Home Assistant wird in
  Phase 4 als neue VM auf hl01 eingerichtet und erhält dann wieder eine
  Route.

**Rollback-Fenster:**

- Die k3s-Ressourcen und das Vaultwarden-PVC nicht löschen, bis ein externes
  Backup von hl02 inklusive Restore-Test vorliegt.
- Bei einem reinen Proxyfehler können die drei Cloudflare-Tunnelziele wieder
  von `.12` auf `.34` und der Wildcard-A-Record von `100.113.0.83` auf
  `100.88.238.61` gesetzt werden.
- Nach neuen Schreibzugriffen auf hl02 darf das alte Vaultwarden-Deployment
  nicht einfach gestartet werden. Für einen vollständigen
  Applikations-Rollback zuerst Vaultwarden auf hl02 stoppen, seinen aktuellen
  Datenstand konsistent in das behaltene PVC zurückkopieren und mit
  `PRAGMA quick_check` prüfen; erst danach die Reconcile-Sperre entfernen und
  das k3s-Deployment starten.

### Phase 3 — pve03 → hl03 (Nextcloud, LiteLLM, restic) ✅ (2026-07-30)

**Live-Inventar vom 2026-07-30:**

- pve03 besitzt 8 GiB RAM und nur noch etwa 0,9 GiB `MemAvailable`. Es laufen
  genau VM 114 `nextcloud-vm`, VM 200 `pbs01` und VM 303 `k3s03`.
- Die LITEON-SSD mit 256 GB ist die Proxmox-Systemdisk und das deklarierte
  NixOS-Root-Ziel. Die Samsung 840 PRO mit 120 GB enthält noch die bewusst
  aufbewahrte letzte ZFS-Replik von NAS-CT 210. Der Replikationsjob ist mit
  `keep=1` entfernt, die strikte HA-Regel erlaubt nur noch `pve01:2`; CT 210
  läuft weiterhin als HA-Ressource auf pve01. Damit ist pve03 kein
  Replikations- oder Failover-Ziel mehr.
- Die EXCERIA PLUS mit 1 TB ist per USB angeschlossen und vollständig als
  Raw-Disk an PBS-VM 200 durchgereicht. Ihr ext4-Dateisystem enthält den
  verschlüsselten PBS-Datastore: etwa 419 GiB belegt, 451 GiB frei. Der letzte
  Garbage-Collection-Lauf war erfolgreich; tägliche Verify- und Prune-Jobs
  sind konfiguriert.
- Die age-verschlüsselten Recovery-Bundles für PBS-Konfiguration,
  PVE-Cluster-Konfiguration und Restore-Inventar liegen außerhalb der Hosts
  auf dem Mac. Alle drei ließen sich mit dem separaten Recovery-age-Key
  entschlüsseln.
- Nextcloud-VM 114: Debian 12, Nextcloud `34.0.1`, Apache und MariaDB;
  Datenverzeichnis `/var/www/nextcloud-data` mit 4,5 GiB und 26.290 Dateien,
  MariaDB etwa 12,8 MiB. `pkgs.nextcloud34` liefert exakt Version `34.0.1`.
  Beim Restore werden die veralteten Proxy-/URL-Werte `.44` und
  `cloud.sks-concept.de` durch hl02 und `cloud.sk4i.com` ersetzt.
- LiteLLM läuft vollständig auf k3s01: Image `1.94.0`, PostgreSQL `18.4`,
  Datenbankgröße 78 MiB, 17 Proxy-Modelle, 45 Virtual Keys und 2 Benutzer.
  Das Retain-PVC liegt weiter auf NAS-CT 210. Die Nixpkgs-Pakete sind mit
  `1.86.0` beziehungsweise `1.89.0` älter; Ziel ist deshalb der bereits
  gepinnte OCI-Container mit nativem PostgreSQL.
- Auf k3s03 laufen keine zustandsbehafteten Anwendungen. Einer der zwei
  cloudflared-Connectoren und k3s-Infrastruktur liegen dort. Vor dem Wipe muss
  k3s03 sauber aus dem zweiköpfigen etcd-Cluster entfernt werden; ein
  Connector auf k3s01 bleibt während der Migration aktiv.

**Verbindlicher Umgang mit der 1-TB-Platte:**

- Das bestehende ext4-Dateisystem und den PBS-Datastore nicht formatieren.
  hl03 mountet die Partition anhand ihrer UUID; neue restic-Repositories
  liegen in einem getrennten Verzeichnis neben dem unangetasteten
  PBS-Datastore.
- Damit bleiben die bisherigen verschlüsselten PBS-Sicherungen während der
  Migration von pve01 verfügbar und restic kann die neuen NixOS-Dienste auf
  dem noch freien Platz sichern. Erst nach Ablauf aller Rollback-Fenster
  werden die alten PBS-Daten kontrolliert entfernt.
- Vor dem Wipe PBS-VM 200 sauber herunterfahren, aktuelle PBS-Konfiguration
  erneut extern sichern und einen Wiederanlauf des Datastores aus dem
  Recovery-Bundle dokumentieren. Disko darf ausschließlich die LITEON-Rootdisk
  und nach Freigabe die Samsung-`/srv`-SSD verändern, niemals die EXCERIA.

**Vorbereitete Exporte und Zielkonfiguration:**

- Der konsistente Nextcloud-Schattenexport liegt age-verschlüsselt auf dem Mac
  und mit identischem SHA-256 auf nix-ai:
  `nextcloud-shadow-20260730-203650/nextcloud-shadow.tar.zst.age`,
  4.001.403.887 Byte,
  SHA-256 `47314f1bd55d33c163ff4a0f61d281484f2a19f35ef7d46b6e7cf7cfe662ad90`.
  Er enthält 53.666 Dateien aus Webroot und Datenverzeichnis sowie den
  transaktionskonsistenten MariaDB-Dump
  `nextcloud.sql.zst` mit SHA-256
  `13b9542f3bb3cb568604c628edb080203da187406c6a56b323d507cab1c0be6b`.
  Komplettes Entschlüsseln/Entpacken und ein Restore in eine temporäre
  MariaDB mit allen 144 Tabellen waren erfolgreich.
- Der LiteLLM-Custom-Dump liegt ebenfalls verschlüsselt auf beiden Systemen:
  `litellm-shadow-20260730-203650/litellm-postgres.dump.age`,
  2.779.779 Byte,
  SHA-256 `e89e78f8e3faca3c74dba731662fed5327b35efc34df16379d1d67a5efc500c6`.
  Ein vollständiger Restore in eine temporäre PostgreSQL-18-Datenbank wurde
  geprüft: 68 physische Tabellen, 17 Modelle, 45 Virtual Keys, 2 Benutzer und
  320 Migrationen stimmen mit der Quelle überein. Alle Testdatenbanken wurden
  anschließend entfernt; die produktiven Pods blieben gesund.
- Beide Archive sind für den Mac-SSH-Key age-verschlüsselt. Die verschlüsselten
  Zweitkopien liegen unter
  `/home/ecomex/.local/share/nix-configs-migration/hl03/source/` auf nix-ai.
  Auf dem Mac liegen sie unter
  `/Users/ecomex/.local/share/nix-configs-migration/hl03/source/`.
- Der vorab erzeugte hl03-SSH-Hostkey hat den Fingerprint
  `SHA256:EIv7sLoY+NCDVvJzke3Qec41T9XptWxgWY5IfeEj55I`; sein age-Empfänger ist
  in `.sops.yaml` eingetragen und kann `secrets/hl03.yaml` entschlüsseln.
  Hostkey, Public Key und der bestehende ecomex-Passworthash liegen mit
  korrekten Dateirechten im externen `extra-files`-Baum für nixos-anywhere.
- Die Zielkonfiguration verwendet Nextcloud `34.0.1` mit den exakten
  Calendar-/Contacts-Versionen, MariaDB auf `/srv`, PostgreSQL `18.4`,
  das gepinnte LiteLLM-OCI-Image `1.94.0`, cloudflared `2026.7.2` und
  restic-rest-server `0.14.0` im append-only-Modus. Die EXCERIA wird nur über
  UUID `bea9cd03-b112-4d84-8c7d-26d53635a9d7` nach `/srv/backup` gemountet;
  Restic schreibt ausschließlich nach `/srv/backup/restic`.
- `nix flake check --no-build`, der vollständige hl03-Systembuild
  `/nix/store/ziyvpd75p0041q0rphrs1mdj2vz06imn-nixos-system-hl03-26.05.20260719.fd14620`
  und der für den späteren Proxy-Cutover vorbereitete hl02-Build waren auf
  nix-ai erfolgreich. Es wurde noch nichts deployed.
- Der planmäßige PBS-Lauf vom 2026-07-30 um 21:00 Uhr sicherte VM 114 als
  `PBS:backup/vm/114/2026-07-30T19:00:07Z` und VM 303 als
  `PBS:backup/vm/303/2026-07-30T19:00:43Z`. Beide Sicherungen verwendeten
  Clientverschlüsselung, Guest-Agent-Freeze und endeten mit `TASK OK`.
  VM 303 wurde vollständig ohne Start unter der temporären VMID 9303
  wiederhergestellt; alle 32 GiB wurden aus PBS gelesen und verifiziert.
  VM und beide temporären LVM-Volumes wurden anschließend entfernt.
- Ein aktueller PBS-Konfigurationsexport liegt unter
  `hl03/recovery/pbs-config-20260730-211721.tar.gz.age` auf Mac und nix-ai,
  SHA-256
  `8e191090a6336158c6d0e349d880f7dff256b6d68af579506a96bfa07f4bb4f6`.
  Die Entschlüsselung mit dem externen Recovery-Key und der vollständige
  Archivtest waren erfolgreich.
- Vor dem Abbau von k3s03 wurde auf k3s01 der zusätzliche komprimierte
  etcd-Snapshot
  `pre-hl03-removal-20260730-212506-k3s01-1785439509.zip.age`
  erstellt. Die age-verschlüsselten Kopien auf Mac und nix-ai sind
  entschlüsselbar und haben beide SHA-256
  `81107365832974429a19522a8fb0030c454483b1344a97d6b035da232f61c93b`.
- Die bereits nach hl02 migrierten K8s-Deployments für SearXNG, Valkey und
  Stirling-PDF sind wie Vaultwarden gegen Flux-Reconcile gesperrt und auf
  null skaliert. Danach wurde k3s03 kontrolliert gedrained, über den
  K3s-etcd-Removal-Controller als Voter entfernt, der K3s-Dienst gestoppt
  und das Node-Objekt gelöscht. VM 303 ist heruntergefahren. etcd `3.6.12`
  enthält nur noch das gesunde Mitglied `k3s01-f20d22ac`; API-Readiness,
  VIP auf k3s01, LiteLLM samt PostgreSQL und der verbleibende
  cloudflared-Connector wurden danach erfolgreich geprüft.
- Nach Aktivierung des Nextcloud-Maintenance-Modes wurde der endgültige
  Cutover-Export
  `nextcloud-final-20260730-213541/nextcloud-final-20260730-213541.tar.zst.age`
  erstellt: 4.048.231.696 Byte, SHA-256
  `1ccc10be1a94f61948be7dacc7ab7415af9e06f1852747e41dbe3f4f447b178e`.
  Die identischen verschlüsselten Kopien liegen auf Mac und nix-ai. Das
  Archiv wurde vollständig entschlüsselt und der enthaltene Dump aller
  144 MariaDB-Tabellen gegen den Quellhash
  `3212f247b38f7793a724e7d570f4ee2c5910ca8ada24ecd762c1959a5bee664f`
  geprüft. Der temporäre Root-SSH-Key wurde entfernt und VM 114 sauber
  heruntergefahren.
- In PBS liefen keine Tasks mehr. Proxy, API und Update-Timer wurden
  gestoppt, `/mnt/datastore/usb-datastore` synchronisiert und ausgehängt
  und VM 200 heruntergefahren. Der finale Host-Preflight ordnete die
  Disko-Ziele eindeutig `/dev/sdb` (LITEON) und `/dev/sda` (Samsung) zu;
  die nicht von Disko referenzierte EXCERIA ist `/dev/sdc`, ihre erhaltene
  ext4-Partition `/dev/sdc1` mit UUID
  `bea9cd03-b112-4d84-8c7d-26d53635a9d7`. Der read-only-Lauf
  `e2fsck -fn` durchlief alle fünf Prüfphasen fehlerfrei; das Dateisystem
  meldet `clean`. VM 114, VM 200 und VM 303 sind gestoppt.

**Go/No-Go vor dem Wipe:**

- [x] Gäste, physische Datenträger, Durchreichungen, NAS-Replikation und
      k3s03-Workloads inventarisiert.
- [x] Nextcloud-Version, Datenverzeichnis, Datenmenge, Datenbanktyp und
      aktivierte Apps inventarisiert.
- [x] LiteLLM-Version, PostgreSQL-Version, Datenbankgröße, Datensatzanzahlen,
      PVC und Secrets inventarisiert.
- [x] Vorhandene PBS-/PVE-Recovery-Bundles mit dem externen age-Key
      entschlüsselt.
- [x] Verbleib des bestehenden PBS-Datastores und restic-Zielverzeichnis
      verbindlich bestätigen.
- [x] Nextcloud und LiteLLM inklusive Datenbanken konsistent exportieren,
      außerhalb pve03 sichern und Restore testen.
- [x] hl03-Hostkey und SOPS-Secrets vorbereiten; Zielkonfiguration mit
      Nextcloud, PostgreSQL, LiteLLM, cloudflared und restic vollständig bauen.
- [x] Frische PBS-Sicherungen von VM 114 und VM 303 erstellen und mindestens
      einen Restore prüfen; aktuellen PBS-Konfigurations-Export verifizieren.
- [x] NAS-Replikationsjob und HA-Regel kontrolliert von pve03 lösen, ohne
      den primären CT 210 auf pve01 zu beeinträchtigen.
- [x] k3s03 drainen und als etcd-Mitglied entfernen; k3s01, LiteLLM und der
      verbleibende cloudflared-Connector müssen danach gesund sein.
- [x] EXCERIA aus PBS sauber aushängen und VM 200 herunterfahren; By-ID,
      UUID und Nicht-Zielstatus im finalen Disko-Preflight erneut prüfen.
- [x] Erst wenn alle Punkte erfüllt sind: **Go für den Wipe von pve03**.

**Go erteilt am 2026-07-30:** Alle verbindlichen Gates sind erfüllt. Disko
darf jetzt ausschließlich LITEON und Samsung neu partitionieren; die EXCERIA
bleibt unangetastet.

**Durchführung und Abnahme:**

- nixos-anywhere hat ausschließlich LITEON und Samsung neu partitioniert.
  hl03 bootet mit dem vorbereiteten Hostkey auf `10.20.50.13`; Root liegt auf
  LITEON, `/srv` auf Samsung. Die EXCERIA blieb unverändert und ist mit
  derselben UUID unter `/srv/backup` gemountet. Der PBS-Datastore belegt
  weiterhin 422 GiB; restic verwendet nur das neue Nachbarverzeichnis
  `/srv/backup/restic`.
- Nextcloud-Daten und finaler MariaDB-Dump wurden mit
  `scripts/restore-hl03-phase3.sh` importiert. Die deklarativ von NixOS und
  SOPS verwaltete Konfiguration blieb dabei erhalten. Abnahme: Version
  `34.0.1`, 26.290 Datendateien, 144 Tabellen, 2 Benutzer, Maintenance-Modus
  aus und kein ausstehendes Datenbank-Upgrade.
- Der LiteLLM-Custom-Dump wurde mit
  `scripts/resume-hl03-phase3.sh` nach PostgreSQL 18 importiert. Abnahme:
  68 physische Tabellen, 17 Modelle, 45 Virtual Keys, 2 Benutzer und
  320 Prisma-Migrationen. Das gepinnte Image `1.94.0` meldet
  `{"status":"healthy","db":"connected"}`.
- MariaDB, PostgreSQL, Redis, Nextcloud PHP-FPM/nginx, LiteLLM, cloudflared,
  restic-rest-server und Tailscale laufen auf hl03 ohne fehlgeschlagene
  Units. Die frischen Nextcloud-Bootstrap-Daten und die Restore-Eingaben
  bleiben zunächst als lokaler Rollback erhalten:
  `/srv/nextcloud/data.pre-restore-20260730T200626Z` und
  `/home/ecomex/.local/share/nix-configs-migration/hl03/restore-input`.
- Die vorbereitete hl02-Traefik-Konfiguration wurde aktiviert. Abgenommen
  wurden `cloud.sk4i.com/status.php` und `/login` extern über Cloudflare
  sowie `litellm.hl.sk4i.com/health/readiness` und `/ui/` intern über den
  Tailnet-Einstieg, jeweils mit gültigem TLS und HTTP 200. Direkte
  Backend-Tests von hl02 nach hl03 waren ebenfalls erfolgreich. Die
  anschließende manuelle Anmeldung und Datenprüfung in Nextcloud und LiteLLM
  war erfolgreich.
- Durch das endgültige Abschalten von pve03 verlor der verbliebene
  Proxmox-Knoten pve01 erwartungsgemäß sein Quorum und wurde vom
  HA-Watchdog gefenced. pve03 wurde daraufhin aus Corosync entfernt;
  pve01 ist jetzt persistent quorate als Ein-Knoten-Cluster. NAS, Immich,
  Paperless, OpenWebUI, AVA, HAOS und docker-vm wurden wieder gestartet und
  ihre relevanten Backends geprüft. k3s01 bleibt als Rollback gestoppt und
  hat `onboot=0`, damit die alte LiteLLM-Datenbank nicht erneut schreibend
  startet.

### Phase 4 — pve01 → hl01 (der große Brocken)

**Live-Inventar vom 2026-07-30:**

- pve01 ist ein Dell OptiPlex 9020M mit 16 GiB RAM und i5-4590T. Die
  Onboard-I217-NIC ist down; produktiv ist ausschließlich der
  AX88179-USB-Adapter mit MAC `00:24:9b:49:70:91`. Der NixOS-Link auf
  `lan0` ist dafür bereits vorbereitet.
- PM871b 256 GB
  (`ata-SAMSUNG_SSD_PM871b_M.2_2280_256GB_S3U0NE1K918382`) und 860 EVO
  250 GB (`ata-Samsung_SSD_860_EVO_250GB_S3YJNX0KB91294E`) bilden aktuell
  gemeinsam den gesunden ZFS-Mirror `rpool`. Beide SMART-Tests sind
  bestanden, es gibt keine reallokierten Sektoren oder ZFS-Fehler.
  Etwa 108 GiB sind belegt. Das geplante Ziel — PM871b als Root und 860 EVO
  als `/srv` — zerstört daher zwingend den gesamten aktuellen Mirror.
- pve01 ist nach dem Entfernen von pve03 ein quorates Ein-Knoten-Cluster.
  Die verbleibenden Gäste laufen, außer k3s01: Diese VM bleibt mit
  `onboot=0` als manueller Rollback gestoppt. Der tägliche PBS-Job kann
  nicht mehr laufen, weil PBS bewusst außer Betrieb ist; sein erhaltener
  Datastore liegt auf hl03.
- Unter laufender Last sind etwa 5 GiB RAM verfügbar und kein Swap belegt.
  Das Ziel benötigt trotzdem feste Ressourcenlimits, besonders für
  Immich-ML, Open WebUI, HAOS und AVA.

| Quelle | Live-Stand und zustandsbehaftete Daten | Zielvorschlag |
|---|---|---|
| NAS-CT 210 | `/srv/data` enthält nur 133 MiB: LiteLLM-/Vaultwarden-Rollback-PVCs und eine praktisch leere Samba-Freigabe. NFS exportiert noch an die alten k3s-IP-Adressen. | Daten als Rollback archivieren. Samba wird im ersten Phase-4-Cutover nicht eingerichtet. |
| Immich-CT 102 | Immich `3.0.3`, PostgreSQL `16.11`; 240-MiB-DB, 66 Tabellen, 5.646 Assets, 2 Benutzer und 5.166 Dateien. `/opt/immich/upload` belegt 24 GiB. | Natives NixOS-Modul mit `pkgs.unstable.immich` `3.0.3`, Medien und PostgreSQL unter `/srv`. |
| Paperless-CT 104 | Paperless-ngx `2.20.15`, PostgreSQL `16.11`; 20-MiB-DB, 72 Tabellen und 169 Dokumente. Daten 7,8 MiB, Medien 408 MiB, Papierkorb 108 MiB. | Natives stabiles NixOS-Modul, exakt `2.20.15`, Daten und PostgreSQL unter `/srv`. |
| OpenWebUI-CT 105 | Open WebUI `0.11.0`; SQLite `webui.db` 3,6 MiB, `quick_check=ok`, 44 Tabellen. Gesamter `.open-webui`-State 147 MiB; der übrige Platz ist überwiegend reproduzierbarer uv-/Modellcache. | Natives NixOS-Modul mit `pkgs.unstable.open-webui` `0.10.2`. Wegen der älteren Zielversion startet die Anwendung frisch; der vollständige Quell-State wird archiviert, aber nicht rückwärts migriert. |
| AVA-CT 100 | Hermes Agent `0.19.0`/Build `2026.7.20`; `/home/hermes` 10 GiB, davon 3,4 GiB Dokumente und 2,2 GiB Hermes-State. `state.db` ist 110 MiB. | Dedizierter Benutzer und systemd-Dienst; das komplette Benutzerhome einschließlich uv-Python, venv, Git-Checkout, Dokumenten, Konfiguration und State wird verschlüsselt übernommen. Der bisherige Environment-File-Inhalt liegt in SOPS. |
| docker-vm 110 | Aktiv: Haushaltsbuch (SQLite 360 KiB, `quick_check=ok`, 14 Tabellen), Honcho (PostgreSQL 15.18, 93 MiB, 12 Tabellen), Redis und Portainer. Haushaltsbuch- und Honcho-Compose bauen lokale Images aus den Source-Trees. Weitere große Projekt-/Cache-Verzeichnisse sind nicht aktiv. | Haushaltsbuch und Honcho deklarativ als OCI-Container; DBs/Source/Compose sichern. Sonstige Projekte archivieren, aber nicht automatisch deployen. |
| HAOS-VM 101 | HAOS `18.1`, Core `2026.7.4`, Supervisor `2026.07.5`; 50-GiB-Disk mit 5,72 GiB belegt. Kein USB-Gerät ist aktuell durchgereicht. Es existiert nur ein älteres partielles 13-MiB-Backup. | Bleibt aus dem ersten Phase-4-Cutover heraus. Neue HAOS-VM und frischer vollständiger Restore folgen später als eigener, separat abgenommener Schritt. |

**Verbindliche Export-/Restore-Regeln:**

- Immich benötigt immer Datenbank **und** komplettes `UPLOAD_LOCATION`.
  Für einen konsistenten finalen Stand wird der Server gestoppt; die
  Dateidaten und der dazugehörige DB-Dump werden gemeinsam gesichert. Siehe
  [offizielle Immich-Anleitung](https://docs.immich.app/administration/backup-and-restore/).
- Paperless wird mit dem Document Exporter exportiert und nur in dieselbe
  Version `2.20.15` importiert; zusätzlich werden PostgreSQL und die
  Originalverzeichnisse gesichert. Siehe
  [Paperless-Administration](https://docs.paperless-ngx.com/administration/).
- Bei Open WebUI wird das vollständige State-Verzeichnis einschließlich
  Datenbank, Uploads und Knowledge-Base-Daten als Rückfall- und
  Exportgrundlage gesichert. Da die native Zielversion `0.10.2` älter als die
  Quelle `0.11.0` ist, wird dieser State nicht in die Zielinstanz kopiert.
  Siehe
  [Open-WebUI Backup & Restore](https://docs.openwebui.com/getting-started/updating/#backup--restore).
- AVA wird nicht auf einzelne bekannte Dateien reduziert. Gesichert werden
  das komplette `/home/hermes`, der gepinnte Git-Commit `1dfe781e`, die
  uv-Python-Laufzeit, das venv und der bisherige Environment-File-Inhalt.
  Das Archiv muss verschlüsselt außerhalb pve01 liegen und vor dem Cutover
  vollständig testentpackt werden.
- Für den späteren HAOS-Schritt bleibt ein frisches vollständiges Backup
  Pflicht. Der Restore erfolgt dann nach dem offiziellen
  [Home-Assistant-Backup-Verfahren](https://www.home-assistant.io/common-tasks/general/#backups).
- Konfigurationen mit Zugangsdaten werden nicht offen in das Repo kopiert.
  Die Quellsysteme enthalten derzeit mehrere zu weit lesbare Dateien
  (`paperless.conf`, Honcho `.env`, Hermes-Defaults); relevante Werte werden
  ausschließlich in `secrets/hl01.yaml` überführt und auf dem Ziel via
  SOPS-Credentials bereitgestellt.
- Schattenexporte werden außerhalb pve01 auf hl03 und für kritische
  Datenbanken zusätzlich extern abgelegt. Jeder Export erhält SHA-256,
  Inventarzähler und einen tatsächlichen Restore-Test. Vor dem finalen Export
  werden schreibende Dienste kontrolliert gestoppt.

**Vorbereitete Zielkonfiguration und AVA-Schattenexport:**

- Der hl01-SSH-Hostkey ist außerhalb des Repos für nixos-anywhere
  vorbereitet. Fingerprint:
  `SHA256:A7EclpYxNb6oxdnytOi7ibgrZJQjOa33V6vchYZZxTE`; sein age-Empfänger
  steht in `.sops.yaml`. Der bisherige AVA-Environment-File-Inhalt wurde ohne
  Klartext-Zwischendatei nach `secrets/hl01.yaml` übernommen.
- Die deklarative Zielkonfiguration enthält Immich `3.0.3`, Paperless-ngx
  `2.20.15`, natives Open WebUI `0.10.2`, PostgreSQL 16 auf `/srv` und den
  Hermes-Dashboard-Dienst mit Ressourcenlimits. Der vollständige
  hl01-Systembuild war erfolgreich:
  `/nix/store/5k9z8pijgqpqvcw6lb7m8mqd0yv0h8qf-nixos-system-hl01-26.05.20260719.fd14620`.
- AVA wurde ohne Dienstunterbrechung aus einem unveränderlichen ZFS-Snapshot
  vollständig gesichert. Das age-verschlüsselte Archiv
  `ava-shadow-20260730-205541/ava-home.tar.zst.age` liegt byteidentisch auf
  Mac und nix-ai; SHA-256:
  `f2bb400bad7d2200f28fc57341c84c45c0a37b29b6e384e31c456ee27dcd9f56`.
  Es enthält 220.238 Einträge einschließlich Launcher, Git-Metadaten,
  uv-Python, venv, Dokumenten und der 110.362.624 Byte großen `state.db`.
- Der Restore wurde vollständig auf nix-ai entpackt. SQLite `quick_check`
  meldete `ok`, der Checkout stand auf Commit
  `1dfe781edd5e96d09511cf27d800a03e63b09789`, und die restaurierte
  Debian-Laufzeit startete isoliert unter NixOS mit nix-ld als Hermes Agent
  `0.19.0`/Build `2026.7.20`. Die Klartext-Testkopie und der temporäre
  ZFS-Snapshot wurden danach entfernt.

**Go/No-Go vor dem Wipe:**

- [x] Zielbetriebsform für Immich, Paperless, Open WebUI und AVA bestätigt;
      HAOS und Samba aus dem ersten Cutover ausgeklammert.
- [x] hl01-Hostkey und SOPS-Empfänger vorbereiten; AVA-Environment-File
      verschlüsselt nach `secrets/hl01.yaml` übernehmen.
- [x] `/srv`-Layout für die 860 EVO in disko ergänzen; By-ID beider
      Zielplatten unmittelbar vor der Installation erneut prüfen.
- [ ] Immich-Dateien plus DB exportieren und auf Version `3.0.3`
      wiederherstellen.
- [ ] Paperless-Exporter, PostgreSQL-Dump und Verzeichnisbackup erstellen;
      Import auf Version `2.20.15` prüfen.
- [ ] Open-WebUI-State, komplettes AVA-Home, NAS-Daten, Haushaltsbuch-SQLite,
      Honcho-PostgreSQL/Redis und beide Source-Trees extern sichern und
      stichprobenartig beziehungsweise vollständig wiederherstellen.
- [ ] Zielkonfiguration vollständig evaluieren und bauen; Images beziehungsweise
      Startmechanismen für Haushaltsbuch und Honcho sowie Rollback-Befehle
      vorbereiten.
- [ ] Finales Wartungsfenster: Dienste stoppen, finale Exporte prüfen, alle
      Gäste sauber herunterfahren und Disko-Preflight wiederholen.
- [ ] Erst wenn alle Punkte erfüllt sind: **Go für den Wipe von pve01**.

### Phase 5 — Aufräumen
- homelab-kubernetes archivieren (README-Verweis hierher), SSH-Config +
  DNS-Einträge auf hl-Namen, CLAUDE.md/README aktualisieren,
  RAM/OOM-Check, Restore-Test dokumentieren.

## Stand & Übergabe (2026-07-30)

**Wo wir stehen:** Phase 1, Phase 2 und Phase 3 sind abgeschlossen und
abgenommen.
Vaultwarden, SearXNG, Stirling-PDF und Traefik laufen nativ auf hl02;
öffentlicher Tunnel und interner Wildcard-DNS zeigen auf den neuen Proxy.
Nextcloud, LiteLLM, PostgreSQL, MariaDB, cloudflared und das restic-Ziel laufen
auf dem neuen hl03. Der hl02-Proxy leitet die produktiven Nextcloud- und
LiteLLM-Routen nach hl03; öffentliche und interne Pfade sind geprüft. Die
EXCERIA samt PBS-Datastore blieb unverändert erhalten. pve01 ist nach dem
Entfernen des migrierten pve03 wieder quorate; alle noch benötigten
Phase-4-Quellgäste laufen, während k3s01 bewusst gestoppt bleibt.

**Nächster Schritt:** Die vorbereitete hl01-Zielkonfiguration bauen und
anschließend Schattenexporte samt Restore-Tests für Immich, Paperless,
OpenWebUI, AVA, NAS und docker-vm erstellen. HAOS und Samba sind aus diesem
Cutover ausgeklammert. Erst danach darf das Go/No-Go-Gate für den Wipe von
pve01 bewertet werden.

**Zugriffswege aus dieser Session:**
- SSH als root auf `pve01` sowie als ecomex auf `hl02` und `hl03`
  funktioniert; nix-ai ist für beide NixOS-Hosts deklarativ autorisiert.
- Der Kontext `pve-k3s` ist bewusst nicht erreichbar, solange k3s01 gestoppt
  ist. Die VM bleibt mit ihrer etcd-Datenbank als manueller Rollback erhalten,
  darf aber wegen des inzwischen produktiven LiteLLM auf hl03 nicht
  unkontrolliert gestartet werden.
- `gh` ist authentifiziert (Repo: ec0m3x/nix-configs, Branch homelab-migration).
- k3s01 und docker-vm (ecomex@.46) akzeptieren den Windows-Key NICHT —
  Zugriff nur vom Mac (Ansible-Key) beziehungsweise via
  `ssh pve01 "qm guest exec 110 -- …"` (Guest-Agent, funktioniert). k3s03
  existiert nach der Migration von pve03 nicht mehr.
- nix-ai (10.20.50.20) ist der Buildhost für die Homelab-Migration.

**Gotchas:**
- Flake sieht nur git-getrackte Dateien — neue Dateien immer `git add`.
- flake.lock wurde von Hand um disko/sops-nix ergänzt (Pins aus CI-Log +
  GitHub-API-Timestamps) — bei nächster Gelegenheit auf einem Nix-Host
  `nix flake lock` gegenprüfen.
- pve01 ist das einzige verbleibende Proxmox-Mitglied. pve03 wurde aus
  Corosync entfernt; erwartete Stimmen und Quorum stehen persistent auf 1.
- Claude-Session-Tasks #1–#6 bilden die Phasen ab (Task #1 = Phase 0 done).

## Offene Punkte

- SSH-Zugang docker-vm (ecomex@10.20.50.46 lehnt Standard-Key ab) — nötig
  für Datenexport haushaltsbuch/honcho. Workaround: `qm guest exec` via pve01.
- AVA: restaurierte Debian-uv-Laufzeit mit nix-ld auf dem gebauten
  NixOS-Ziel testen; vollständiges Home bleibt bis dahin unverändert erhalten.
- Home Assistant auf hl01: nach Phase 4 als separaten Schritt mit
  Virtualisierung, frischem HAOS-Backup und Restore-Test planen.
