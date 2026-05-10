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

| Command              | What it does                              | Script                                                         |
|----------------------|-------------------------------------------|----------------------------------------------------------------|
| `just prepare`       | one time host setup                       | [scripts/prepare-linux.sh](scripts/prepare-linux.sh)           |
| `just env`           | sync .env from template, generate secrets | [scripts/bootstrap-services.sh](scripts/bootstrap-services.sh) |
| `just validate`      | lint, validate docker compose             | [scripts/validate-config.sh](scripts/validate.sh)              |
| `just up`            | env, secrets, starts services             | [scripts/start-services.sh](scripts/start-services.sh)         |
| `just down`          | stops services                            | [scripts/stop-services.sh](scripts/stop-services.sh)           |
| `just restart [svc]` | restart everything,  one service          |                                                                |
| `just logs [svc]`    | logs for the stack, or one service        |                                                                |
| `just ps`            | show running services                     |                                                                |
| `just pull`          | pull latest images                        |                                                                |

Run `just` with no args to list every target.

## Post-setup

**Tailscale DNS** - route `*.voxlab.home` queries to Pi-hole:
1. get tailscale IP: `tailscale ip -4`
2. tailscale admin → DNS → Nameservers → add custom nameserver with the `100.x.x.x` address
3. Restrict to domain: `voxlab.home`

**Authelia first login** - the initial admin password is printed once by `scripts/bootstrap-services.sh` during `just env` or `just up` on first run; it is not stored on disk in plaintext. After login, change it from the Authelia UI (Settings -> Account). For password resets after that, the one-time link lands in `sudo docker exec authelia cat /data/notification.txt`.

**Pihole login** - password to access pihole website `sudo docker logs pihole | grep "password"`

**Trust the internal CA** - Caddy uses a self-signed CA for TLS. Client devices need to trust it to avoid certificate warnings.
1. Download the CA cert from void: `scp vox@void:~/infrastructure/services/caddy/pki/internal-ca.crt .`
2. Firefox (PC): Settings → Privacy & Security → Certificates → View Certificates → Authorities → Import → check "Trust this CA to identify websites"
3. Android: Settings → Security → Encryption & credentials → Install a certificate → CA certificate

**Gluetun VPN** - connects via ProtonVPN (OpenVPN). Get credentials from https://account.protonvpn.com/account#openvpn and set `PROTONVPN_OPENVPN_USER` / `PROTONVPN_OPENVPN_PASSWORD` in `.env`. Verify: `sudo docker exec gluetun wget -qO- ifconfig.me` (should return a Canadian IP).

**qBittorrent login** - `sudo docker logs qbittorrent | grep "password"` for the generated password (user: `admin`). To let other Docker containers connect without credentials: Settings → Web UI → Authentication → enable "Bypass authentication for clients in whitelisted IP subnets" → add `172.0.0.0/8`.

**qBittorrent `books` category** - right-click Categories → Add → name `books`, save path `/cwa-book-ingest`; Options → Downloads → set torrent management mode to **Automatic**.

**Prowlarr indexers** - Indexers → Add. Recommended public indexers: The Pirate Bay, LimeTorrents, YTS (movies), Nyaa (anime).

**Shelfmark** -
- Settings → Prowlarr (server: `http://gluetun:9696`, API key from Prowlarr → Settings → General)
- Settings → qBittorrent (host: `gluetun`, port: `8080`, category: `books`, destination: `/cwa-book-ingest`)
- Settings → Advanced → download path: `/cwa-book-ingest` (otherwise files are lost inside the container)

**Calibre-Web-Automated** - login with `admin` / `admin123`, then:
- Admin → Basic Configuration → enable **Allow Reverse Proxy Authentication** → set header to `Remote-User`
- Create a user matching your Authelia username

## Services

| Service               | URL                              | Status    |
|-----------------------|----------------------------------|-----------|
| Caddy                 | -                                | Installed |
| Pi-hole               | `https://dns.voxlab.home/admin/` | Installed |
| Authelia              | `https://auth.voxlab.home`       | Installed |
| Immich                | `https://photos.voxlab.home`     | Installed |
| Mealie                | `https://recipes.voxlab.home`    | Installed |
| Homepage              | `https://apps.voxlab.home`       | Installed |
| Book Reader           | `https://reader.voxlab.home/`    | Installed |
| Book Downloader       | `https://books.voxlab.home/`     | Installed |
| Sonarr / Radarr       | -                                | Planned   |
| Prowlarr              | `https://indexer.voxlab.home/`   | Installed |
| qBittorrent + Gluetun | `https://downloads.voxlab.home/` | Installed |
| Diun                  | -                                | Planned   |
| Nextcloud             | -                                | Planned   |

### Architecture

- Reverse proxy: Caddy terminates TLS (internal CA), routes by hostname
- Auth: Authelia forward auth for all routes + OIDC for Immich and Mealie
- DNS: Pi-hole serves wildcard `*.voxlab.home` to host IP
- Remote access: Tailscale VPN + Pi-hole DNS
- Containers: Docker Compose per service with shared `proxy` network

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

### core
- hardware: planned laptop upgrade to ssh into stuff on the go

## Constraints

- RAM: 8 GB for current stack; media services may need 16 GB+
- Storage: 256 GB tight for media, SATA expansion available
