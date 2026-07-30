# Homelab-Migration: Proxmox → NixOS

Migration der drei Proxmox-Mini-PCs (`pve01`–`pve03`) auf bare-metal NixOS
(`hl01`–`hl03`), zentral verwaltet über dieses Repo. Referenz für Netzplan
und bisherige Architektur: Repo `homelab-kubernetes` (wird nach Abschluss
archiviert).

## Beschlossene Architektur

- **k3s wird abgeschafft** — alle Apps werden native NixOS-Dienste.
- **Home Assistant** wird neu als `services.home-assistant` eingerichtet
  (die bisherige HAOS-VM wird nicht migriert).
- **Backups** über restic (NixOS-Module) statt PBS; Ziel: 1-TB-Platte auf hl03.
- IP-Adressen bleiben: hl01 = 10.20.50.11, hl02 = .12, hl03 = .13.
- Secrets via sops-nix (age; Admin-Key wie im homelab-kubernetes-Repo,
  Host-Keys = SSH-Hostkeys via ssh-to-age).

## Hardware

| Host | IP | RAM | Disks | NIC (MAC → `lan0`) |
|---|---|---|---|---|
| hl01 | 10.20.50.11 | 16 GiB | PM871b 256 GB (root), 860 EVO 250 GB (→ /srv) | **USB-Adapter** 00:24:9b:49:70:91 (onboard defekt/down) |
| hl02 | 10.20.50.12 | 8 GiB | 860 EVO 250 GB (root) | 64:00:6a:3e:65:e2 |
| hl03 | 10.20.50.13 | 8 GiB | LITEON 256 GB (root), 840 PRO 120 GB (→ /srv), 1 TB EXCERIA (USB?, → restic) | 98:90:96:b2:db:a5 |

Alle drei: Intel i5-4590T (4 Cores), UEFI-Boot.

## Ziel-Dienstverteilung

| Host | Dienste |
|---|---|
| hl01 (16 GiB) | immich, paperless-ngx, open-webui, Samba-NAS, Home Assistant, haushaltsbuch + honcho (oci-containers), ava |
| hl02 (8 GiB) | AdGuard Home, Tailscale-Subnet-Router, Vaultwarden, SearXNG, Stirling-PDF, Reverse-Proxy (Wildcard `*.hl.sk4i.com`, Tailnet-Einstieg) |
| hl03 (8 GiB) | Nextcloud, LiteLLM + Postgres, cloudflared (Cloudflare-Tunnel), restic-Backup-Ziel |

## Installation & Betrieb

- **Erstinstallation**: nixos-anywhere per kexec über SSH direkt aus dem
  laufenden Proxmox (root-SSH vorhanden). Disk-Layouts deklarativ via disko
  (`hosts/hl0X/disko.nix`). Vor jeder Installation per `--extra-files`
  einspielen: `/etc/nixos-secrets/ecomex` (Passwort-Hash) und die vorab
  generierten SSH-Hostkeys (damit sops-Secrets ab dem ersten Boot
  entschlüsselbar sind).
- **Updates**: `nixos-rebuild switch --flake .#hl0X --target-host ecomex@10.20.50.1X --use-remote-sudo`
  von nix-ai aus (Windows kann nicht bauen), oder lokal auf dem Host via nh.
- **Fallback**: Monitor + Tastatur bereithalten — bei kexec-/Boot-Problemen
  gibt es keine Remote-Konsole mehr (kein Proxmox).

## Phasen und Status

### Phase 0 — Repo-Scaffolding ✅ (2026-07-30)
- [x] flake-Inputs disko + sops-nix, nixosConfigurations hl01–hl03
- [x] hosts/homelab/common.nix (Basis), hosts/hl0X/ (configuration + disko)
- [x] .sops.yaml (Admin-Key; Host-Keys folgen je Phase)
- [x] Eval-Test aller Host-Configs via GitHub Actions (.github/workflows/check.yml)

### Phase 1 — pve02 → hl02 (AdGuard + Tailscale-Router)
1. AdGuard-Config (LXC 106: /opt/AdGuardHome/AdGuardHome.yaml o. ä.) und
   Tailscale-Hinweise (LXC 109) sichern; PBS-Backups von 106/109 prüfen.
2. k3s02 entfernen: `kubectl drain k3s02 …`, `kubectl delete node k3s02`,
   VM 302 stoppen (etcd läuft mit 2/3 weiter).
3. nixos-anywhere auf pve02 → hl02 (kurze DNS-Downtime: Clients nutzen
   Router/Gateway als Fallback; AdGuard-Umzug zügig durchziehen).
4. AdGuard Home nativ + Config-Restore, DNS-Test, Tailscale-Router
   (`--advertise-routes=10.20.50.0/24`) — Route-Approval im Admin-Panel.

### Phase 2 — k3s-Apps → hl02, Reverse-Proxy-Wechsel
1. Vaultwarden (SQLite + attachments aus NFS-PVC), SearXNG (Config),
   Stirling-PDF nativ auf hl02; Daten von nas01-NFS kopieren.
2. Reverse-Proxy (Caddy oder Traefik) mit Wildcard `*.hl.sk4i.com`
   (ACME DNS-01 über Cloudflare) + Tailnet-Anbindung; Routing-Tabelle aus
   homelab-kubernetes/docs/network.md übernehmen.
3. Wildcard-DNS auf die neue Tailnet-IP des Proxys umstellen.
4. cloudflared: Tunnelziele auf neuen Proxy; k3s-Apps + Traefik im Cluster
   stilllegen.

### Phase 3 — pve03 → hl03 (Nextcloud, LiteLLM, restic)
1. LiteLLM-Postgres dumpen; Nextcloud-VM: Daten + DB exportieren.
2. Letzte PBS-Vollsicherung ALLER verbleibenden Gäste; Verbleib des
   PBS-Datastores (1 TB) entscheiden, erst danach Platte neu formatieren.
3. k3s03 stoppen, nixos-anywhere → hl03.
4. services.nextcloud (+ Import), LiteLLM, cloudflared, restic-Ziel
   (rest-server o. SFTP) auf 1-TB-Platte.

### Phase 4 — pve01 → hl01 (der große Brocken)
1. Sichern/Zwischenlagern auf hl03: NAS-Daten (100 GiB), immich (~100 GB),
   paperless, open-webui, ava, docker-vm (haushaltsbuch + honcho inkl.
   pgvector-DB). SSH-Zugang zur docker-vm klären (Key fehlt aktuell).
2. k3s01 + Cluster endgültig stilllegen; HAOS-VM verabschieden.
3. nixos-anywhere → hl01 (USB-NIC beachten!), zweite SSD als /srv.
4. Dienste: immich, paperless-ngx, open-webui, Samba-NAS,
   services.home-assistant (NEU), haushaltsbuch + honcho (oci-containers),
   ava (Deployment-Weg klären — Hermes-Agent).
5. restic-Jobs auf allen drei Hosts aktivieren, Erst-Backup + Restore-Test.

### Phase 5 — Aufräumen
- homelab-kubernetes archivieren (README-Verweis hierher), SSH-Config +
  DNS-Einträge auf hl-Namen, CLAUDE.md/README aktualisieren,
  RAM/OOM-Check, Restore-Test dokumentieren.

## Stand & Übergabe (2026-07-30)

**Wo wir stehen:** Phase 0 ist fertig und CI-validiert. Der Stand liegt auf
dem Branch `homelab-migration` (gepusht); `main` enthält lokal zusätzlich
einen noch **nicht gepushten** Commit (Entfernung von nix-server +
Misterio-Referenzen). Die Live-Systeme (Proxmox, k3s) sind unverändert —
es wurde noch nichts migriert.

**Nächster Schritt (Phase 1):** pve02 → hl02. Ablauf steht oben; vorher
klären, von wo nixos-anywhere läuft (siehe Blocker).

**Zugriffswege aus dieser Session:**
- SSH als root auf `pve01`/`pve02`/`pve03` (~/.ssh/config) funktioniert.
- `kubectl` mit Kontext `pve-k3s` funktioniert.
- `gh` ist authentifiziert (Repo: ec0m3x/nix-configs, Branch homelab-migration).
- Die k3s-VMs (debian@10.20.50.3X) und docker-vm (ecomex@.46) akzeptieren den
  Windows-Key NICHT — Zugriff nur vom Mac (Ansible-Key) bzw. via
  `ssh pve01 "qm guest exec 110 -- …"` (Guest-Agent, funktioniert).
- nix-ai (10.20.50.20) war aus; MAC unbekannt, WoL daher nicht möglich.

**Blocker/Entscheidung für Phase 1 — Build-Host:** Windows kann kein NixOS
bauen. Optionen: (a) nix-ai einschalten und von dort nixos-anywhere +
`nixos-rebuild --target-host` fahren (bevorzugt), oder (b) Nix auf pve01
installieren (Wegwerf-Buildhost, wird in Phase 4 eh gewiped) — dafür braucht
es die Freigabe des Users (Auto-Mode blockt `curl | sh` auf den Live-Hosts).

**Vor der Installation von hl02 außerdem nötig:**
1. `mkpasswd -m yescrypt`-Hash für ecomex erzeugen → via
   `--extra-files` nach `/etc/nixos-secrets/ecomex`.
2. SSH-Hostkeys für hl02 vorab generieren (`ssh-keygen -t ed25519`),
   Public-Key mit ssh-to-age in `.sops.yaml` eintragen, Private-Key via
   `--extra-files` nach `/etc/ssh/` — sonst funktionieren sops-Secrets
   ab dem ersten Boot nicht.
3. AdGuard-Config aus LXC 106 sichern (`pct exec 106 -- cat …` via pve02),
   Tailscale-Auth-Key für den neuen Subnet-Router bereitlegen.

**Gotchas:**
- Flake sieht nur git-getrackte Dateien — neue Dateien immer `git add`.
- flake.lock wurde von Hand um disko/sops-nix ergänzt (Pins aus CI-Log +
  GitHub-API-Timestamps) — bei nächster Gelegenheit auf einem Nix-Host
  `nix flake lock` gegenprüfen.
- Claude-Session-Tasks #1–#6 bilden die Phasen ab (Task #1 = Phase 0 done).

## Offene Punkte

- SSH-Zugang docker-vm (ecomex@10.20.50.46 lehnt Standard-Key ab) — nötig
  für Datenexport haushaltsbuch/honcho. Workaround: `qm guest exec` via pve01.
- ava (Hermes-Agent-LXC): Deployment-Weg unter NixOS klären.
- Home Assistant neu: USB-Sticks (Zigbee/Z-Wave)? Vor Phase 4 prüfen.
- 1-TB-EXCERIA auf pve03: Anschlussart (USB?) und PBS-Datastore-Verbleib.
- Reverse-Proxy: Caddy vs. Traefik (Entscheidung in Phase 2).
