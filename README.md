# void

Reproducible, container-first homelab. Infrastructure as code.

## Prerequisites

- Ubuntu Server 24.04 LTS host (any Linux distro, but scripts are written for Ubuntu)
- required: `git`, `openssl`, `tailscale`, `just`
- optional: `shellcheck`

## Quick start

```bash
git clone git@github.com:Konstantin-Volodin/infrastructure.git
cd infrastructure

just prepare    # one-time host setup
just env        # sync .env, generate secrets, safe to rerun
just up         # start services
```

### Common targets

| Command                  | What it does                              | Script                                                         |
|--------------------------|-------------------------------------------|----------------------------------------------------------------|
| `just`                   | show all available commands               | [justfile](justfile)                                           |
| `just prepare`           | linux setup                               | [scripts/prepare.sh](scripts/prepare.sh)                       |
| `just env`               | sync .env file                            | [scripts/env.sh](scripts/env.sh)                               |
| `just media`             | wire up media stack mesh                  | [scripts/media.sh](scripts/media.sh)                           |
| `just validate`          | validate docker compose files             | [scripts/validate.sh](scripts/validate.sh)                     |
| `just up/down/restart`   | service management                        |                                                                |
| `just update`            | pull latest images + full restart         | [scripts/update.sh](scripts/update.sh)                         |
| `just logs [svc]`        | logs for the stack, or one service        |                                                                |
| `just ps`                | show running services                     |                                                                |
| `just pull`              | pull latest images                        |                                                                |

## Post-setup

**Tailscale**: (1) get IP (`tailscale ip -4`), (2) tailscale admin → DNS → Nameservers → add a custom nameserver restricted to `voxlab.home`.

**Authelia** (`https://auth.voxlab.home`): (1) login `admin` + printed password, (2) change under settings → account (`docker exec authelia cat /data/notification.txt` for the reset OTP).

**Certificates**: clients must trust it to avoid cert warnings. Fetch with `scp vox@void:infrastructure/services/caddy/pki/internal-ca.crt ./internal-ca.crt`
- in Firefox: Settings → Privacy & Security → Certificates → View Certificates → Authorities → Import, check "Trust this CA to identify websites"
- in Android: Settings → Security → Encryption & credentials → Install a certificate → CA certificate

**Prowlarr** (`https://indexer.voxlab.home`): Indexers → Add. Suggested public: The Pirate Bay, LimeTorrents, YTS (movies), Nyaa (anime).

**Shelfmark**: Settings → Prowlarr (`http://gluetun:9696`, key from Prowlarr → Settings → General); qBittorrent (host `gluetun`, port `8080`, category `books`); Advanced → download path `/books`.

**Kavita** (`https://reader.voxlab.home`): first-run wizard creates the admin account, then Server Settings → Libraries → add **Books** (`/books`) and **Comics** (`/comics`). Shelfmark and qBittorrent's `books` category both download straight into `/books`, so new books appear after a library scan.

**Jellyfin** (`https://watch.voxlab.home`): run the setup wizard (creates admin user), add libraries `/data/tv` and `/data/movies`, then Dashboard → Playback → Transcoding → enable **Intel QuickSync (QSV)** (confirm `/dev/dri/renderD128`). Verify HW transcoding: `sudo docker exec jellyfin /usr/lib/jellyfin-ffmpeg/vainfo` should list the iHD driver + H.264/HEVC profiles. The route is intentionally **not** behind Authelia - Jellyfin's mobile/TV apps and Chromecast can't do the Authelia web flow, so it uses its own accounts.

### Accessing some services

**Pi-hole**: admin password: `sudo docker logs pihole | grep "password"`.

## Services

| Service                  | URL                              | Status    |
|--------------------------|----------------------------------|-----------|
| Caddy                    | -                                | Installed |
| Pi-hole                  | `https://dns.voxlab.home/admin/` | Installed |
| Authelia                 | `https://auth.voxlab.home`       | Installed |
| Immich                   | `https://photos.voxlab.home`     | Installed |
| Mealie                   | `https://recipes.voxlab.home`    | Installed |
| Homepage                 | `https://apps.voxlab.home`       | Installed |
| Book Reader              | `https://reader.voxlab.home/`    | Kavita    |
| Book Downloader          | `https://books.voxlab.home/`     | Shelfmark |
| Sonarr                   | `https://shows.voxlab.home/`     | Installed |
| Radarr                   | `https://movies.voxlab.home/`    | Installed |
| Jellyfin                 | `https://watch.voxlab.home/`     | Installed |
| Prowlarr                 | `https://indexer.voxlab.home/`   | Installed |
| qBittorrent + Gluetun    | `https://downloads.voxlab.home/` | Installed |
| Actual Budget            | `https://budget.voxlab.home`     | Installed |

### Custom services

Apps with their own repo + compose stack, proxied in here (not started by `just up`).

| Service        | URL                         | Status    | Description                                                          |
|----------------|-----------------------------|-----------|---------------------------------------------------------------------|
| [Montreal Pulse](https://github.com/Konstantin-Volodin/montreal-pulse) | `https://pulse.voxlab.home` | Installed | streaming stock trades dashboard |

### Architecture

- Reverse proxy: Caddy terminates TLS (internal CA), routes by hostname
- Auth: Authelia forward auth for all routes + OIDC for Immich, Mealie, and Actual Budget
- DNS: Pi-hole serves wildcard `*.voxlab.home` to host IP
- Remote access: Tailscale VPN + Pi-hole DNS
- Containers: Docker Compose per service with shared `proxy` network
- Updates: images track `:latest`; a nightly cron (04:00, installed by `just env`) pulls, restarts the stack, and prunes old images

## Future plans

**Services to add**
- Google Drive alternative: Nextcloud?
- Note taking: Joplin Server?
- Code hosting: Gitea?
- Password manager: Vaultwarden
- Notifications: (tool TBD - ntfy / Gotify?)

**Platform & ops**
- User management: unify accounts across services (Authelia + service-specific)
- Monitoring: Grafana + Prometheus (resource usage, service health)
- Backup: restic → external drive or cloud
- Branding: coherent design across services (custom Caddy error pages, unified UI theme) - _in progress_
- Documentation

**Hardware / topology**
- Media node: abyss NAS dedicated to media services (Jellyfin, Sonarr/Radarr, qBittorrent)
- AI node: convert core → synapse for AI services
- Home automation: Home Assistant (needs Zigbee/Z-Wave USB stick - need to buy a house first ;| )


## Hardware

### void (homelab node)
- hardware: Lenovo ThinkCentre M710q
- CPU: Intel Core i5 7500T
- RAM: 8 GB (max 32 GB)
- storage: 256 GB NVMe (SATA expansion available)
- OS: Ubuntu Server 24.04 LTS

### abyss (media node)
- hardware: planned NAS build

### core (workstation) (to convert to 'synapse' node)
- hardware: Custom desktop build
- CPU: AMD Ryzen 5 5600X
- RAM: 32 GB
- storage: 1 TB NVMe + 2 TB SATA (4xSATA + 2x3.5" bays total)
- GPU: NVIDIA RTX 3060 Ti
- OS: Windows 11
- planned: convert to synapse node and upgrade to core becomes a laptop to SSH anywhere

## Constraints

- RAM: 8 GB for current stack; media services may need 16 GB+
- Storage: 256 GB tight for media, SATA expansion available

## 🤖 Code style

### Mindset

- **Read it before you ship it.** Correctness is the floor - does the eye glide or stumble?
- **Prefer deletion.** Every change should leave the file easier to read; if a refactor grows it, question the approach.
- **Trust the system.** No defensive guards for cases that won't fire - calm code, not anxious code.
- **Compact over conventional.** Style guides describe defaults - choose better when the result reads better.

### Shape

- **Separate data from logic.** Declare named values at the top; operate on them below.
- **Mirror the shape of the work.** Two operations doing the same thing should *look* the same - matching prefixes, aligned call sites, parallel structure.
- **Templates over inline soup.** Multi-line JSON, SQL, anything with quoting - extract to a top-level constant with placeholders.
- **Comments only when the code can't speak.** - the signature lives in the destructure, not a drifting comment.
- **Breathing room.** Blank lines between conceptual sections - the eye uses whitespace to navigate.