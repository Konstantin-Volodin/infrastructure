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

Upgrading an install that predates the storage split? Run `just down && just migrate`
once before `just up` — see [Storage](#storage).

### Common targets

| Command                  | What it does                              | Script                                                         |
|--------------------------|-------------------------------------------|----------------------------------------------------------------|
| `just`                   | show all available commands               | [justfile](justfile)                                           |
| `just prepare`           | linux setup                               | [scripts/prepare.sh](scripts/prepare.sh)                       |
| `just env`               | sync .env file                            | [scripts/env.sh](scripts/env.sh)                               |
| `just media`             | wire up media stack mesh                  | [scripts/media.sh](scripts/media.sh)                           |
| `just migrate`           | one-time move onto the storage roots      | [scripts/migrate.sh](scripts/migrate.sh)                       |
| `just permissions`       | repair storage tree ownership             | [scripts/permissions.sh](scripts/permissions.sh)               |
| `just validate`          | validate docker compose files             | [scripts/validate.sh](scripts/validate.sh)                     |
| `just up/down/restart`   | service management                        |                                                                |
| `just update`            | pull images, recreate only what changed   | [scripts/update.sh](scripts/update.sh)                         |
| `just logs [svc]`        | logs for the stack, or one service        |                                                                |
| `just ps`                | show running services                     |                                                                |
| `just pull`              | pull latest images                        |                                                                |

## Post-setup

**Tailscale**: (1) get IP (`tailscale ip -4`), (2) tailscale admin → DNS → Nameservers → add a custom nameserver restricted to `voxlab.home`.

**Authelia** (`https://auth.voxlab.home`): (1) login `admin` + printed password, (2) change under settings → account (`docker exec authelia cat /data/notification.txt` for the reset OTP).

**Certificates**: clients must trust it to avoid cert warnings. Fetch with `scp vox@void:/srv/void/config/ca/internal-ca.crt ./internal-ca.crt`
- in Firefox: Settings → Privacy & Security → Certificates → View Certificates → Authorities → Import, check "Trust this CA to identify websites"
- in Android: Settings → Security → Encryption & credentials → Install a certificate → CA certificate

**Prowlarr** (`https://indexer.voxlab.home`): Indexers → Add. Suggested public: The Pirate Bay, LimeTorrents, YTS (movies), Nyaa (anime).

**Shelfmark**: Settings → Prowlarr (`http://gluetun:9696`, key from Prowlarr → Settings → General); qBittorrent (host `gluetun`, port `8080`, category `books`); Advanced → download path `/books`.

**Kavita** (`https://reader.voxlab.home`): first-run wizard creates the admin account, then Server Settings → Libraries → add **Books** (`/books`) and **Comics** (`/comics`). Shelfmark and qBittorrent's `books` category both download straight into `/books`, so new books appear after a library scan.

**Jellyfin** (`https://watch.voxlab.home`): run the setup wizard (creates admin user), add libraries `/data/tv` and `/data/movies`, then Dashboard → Playback → Transcoding → enable **Intel QuickSync (QSV)** (confirm `/dev/dri/renderD128`). Verify HW transcoding: `sudo docker exec jellyfin /usr/lib/jellyfin-ffmpeg/vainfo` should list the iHD driver + H.264/HEVC profiles. The route is intentionally **not** behind Authelia - Jellyfin's mobile/TV apps and Chromecast can't do the Authelia web flow, so it uses its own accounts.

**Odysseus** (`https://ai.voxlab.home`): clone [the repo](https://github.com/pewdiepie-archdaemon/odysseus) next to `infrastructure/`, `cp .env.example .env`, then set `ALLOWED_ORIGINS=https://ai.voxlab.home` and `SECURE_COOKIES=true` in `.env`. Join it to the proxy net with a `docker-compose.override.yml`:

```yaml
services:
  odysseus:
    networks: [default, proxy]
networks:
  proxy:
    external: true
```

`docker compose up -d --build`, grab the admin password from `docker compose logs odysseus`, then Settings → Models → add the Anthropic API key (model `claude-opus-4-8`). void's 8 GB RAM means API models only — skip Cookbook local model serving until synapse exists.

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
| [Odysseus](https://github.com/pewdiepie-archdaemon/odysseus) | `https://ai.voxlab.home` | Pending | self-hosted AI workspace (chat + agents + research) |

### Architecture

- Reverse proxy: Caddy terminates TLS (internal CA), routes by hostname
- Auth: Authelia forward auth for all routes + OIDC for Immich, Mealie, and Actual Budget
- DNS: Pi-hole serves wildcard `*.voxlab.home` to host IP
- Remote access: Tailscale VPN + Pi-hole DNS
- Containers: Docker Compose per service with shared `proxy` network
- Updates: images track `:latest`; a nightly cron (04:00, installed by `just env`) pulls and reconciles — only containers whose image changed are recreated, so an unchanged night stops nothing

## Storage

The repo is declarative only — no container writes into the working tree, so
`git pull` never fights file ownership and `git clean -xfd` is harmless. State
lives in three roots, set in `.env` and split by lifetime:

| Root         | Default             | Holds                                               | Lose it and…                        |
|--------------|---------------------|-----------------------------------------------------|-------------------------------------|
| `CONFIG_DIR` | `/srv/void/config`  | databases, credentials, certs, per-app settings     | everything resets — **back this up** |
| `MEDIA_DIR`  | `/srv/void/media`   | tv, movies, books, comics, photos, downloads        | the library is gone                  |
| `CACHE_DIR`  | `/srv/void/cache`   | transcodes, artwork, ML models                      | it rebuilds itself                   |

Two constraints the split exists to respect:

- **`CONFIG_DIR` must be a local disk.** SQLite and Postgres locking is
  unreliable over NFS/SMB, so Immich's database and the `*arr` configs can't
  follow the media to a NAS. `MEDIA_DIR` is the only root meant to move.
- **Downloads live under `MEDIA_DIR` on purpose.** Sonarr, Radarr, and
  qBittorrent mount it as a single tree so imports stay hardlinks. Split
  downloads onto another filesystem and every import becomes a full copy.

Moving to a NAS is then one line in `.env` plus a `mv` of `MEDIA_DIR`.

### Ownership

The media apps run as `PUID`/`PGID`, detected by `just up` from whoever invoked
it and written to `.env`. Everything under the roots is owned by that same
user — the two have to agree, because a container that can read the library but
not write to the directories holding it will fail every delete while looking
otherwise healthy.

`just up` only chowns the top of the tree, since walking a full library on every
start is not free. When files arrive owned by someone else — a migration, a
restore, a manual `cp` as root — repair the whole tree:

```bash
just permissions
```

The symptom worth recognising: Sonarr, Radarr, and Jellyfin all stop deleting at
once, and nothing else misbehaves. Deleting a file needs write permission on the
directory holding it, not on the file, so playback and scanning keep working.

### Starting over

Deleting the two rebuildable roots resets every service to first-run state.
`just up` regenerates the CA, Authelia's admin password and OIDC keys, and all
per-app config — so clients have to re-trust the new cert.

```bash
just down
sudo rm -rf /srv/void/config /srv/void/cache    # your CONFIG_DIR and CACHE_DIR
just up
```

Check the paths before you hit enter — `MEDIA_DIR` sits next to them under the
default layout, and one dropped path segment takes the library with it.

### Migrating an existing install

`services/authelia/config/users_database.yml` used to be a tracked file that
`just env` wrote the admin password hash into, so `git pull` refuses to move
it and discarding it costs you the admin login. Rescue it first, then migrate:

```bash
just down

sudo mkdir -p /srv/void/config/authelia                        # or your CONFIG_DIR
sudo cp services/authelia/config/users_database.yml /srv/void/config/authelia/
git checkout -- services/authelia/config/users_database.yml    # unblock the pull

git pull
just migrate    # moves everything else; skips whatever is already in place
just up
```

`just migrate` has to run before the first `just up` on this layout — otherwise
Authelia bootstraps fresh and mints a new admin password and OIDC keys. It
never overwrites, warns if the Authelia hand-off looks incomplete, and is safe
to re-run.

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
- AI node: convert core → synapse for AI services (Odysseus local model serving moves there)
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