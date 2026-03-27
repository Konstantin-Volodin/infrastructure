# void

Reproducible, container-first homelab. Infrastructure as code.

## Quick start

```bash
# 1. provision the host
git clone git@github.com:Konstantin-Volodin/infrastructure.git
cd infrastructure
sudo bash prepare-linux.sh

# 2. start services
sudo bash start-services.sh
```

`prepare-linux.sh` handles system updates, SSH hardening, UFW firewall, fail2ban, static networking, Docker, and disabling the systemd DNS stub so Pi-hole can bind port 53. \
`start-services.sh` generates secrets, creates the `.env`, builds Authelia keys, and brings up all containers.

### Post-setup

**Tailscale DNS** — route `*.voxlab.home` queries to Pi-hole:
1. Get void's Tailscale IP: `tailscale ip -4`
2. Tailscale admin → DNS → Nameservers → add custom nameserver with the `100.x.x.x` address
3. Restrict to domain: `voxlab.home`

**Authelia first login** — get the one-time password:
```bash
sudo docker exec authelia cat /data/notification.txt
```

## Services

| Service | URL | Status |
|---------|-----|--------|
| Pi-hole | `http://<host-ip>:8080/admin` | Installed |
| Caddy | — | Installed |
| Authelia | `https://auth.voxlab.home` | Installed |
| Immich | `https://photos.voxlab.home` | Installed |
| Mealie | `https://recipes.voxlab.home` | Installed |
| Nextcloud | — | Planned |
| Jellyfin | — | Planned |
| Sonarr / Radarr | — | Planned |
| Prowlarr | — | Planned |
| qBittorrent + Gluetun | — | Planned |

### Architecture

- **Reverse proxy:** Caddy terminates TLS (internal CA), routes by hostname
- **Auth:** Authelia provides forward auth for all routes + OIDC for Immich and Mealie
- **DNS:** Pi-hole serves wildcard `*.voxlab.home` pointing to the host IP
- **Remote access:** Tailscale VPN; services reachable as long as the client uses Pi-hole for DNS
- **Containers:** Docker Compose per service, shared `proxy` network

### Key files

| File | Purpose |
|------|---------|
| [prepare-linux.sh](prepare-linux.sh) | Host bootstrap |
| [start-services.sh](start-services.sh) | Secret generation + service startup |
| [services/docker-compose.yml](services/docker-compose.yml) | Top-level compose (includes all services) |
| [services/caddy/Caddyfile](services/caddy/Caddyfile) | Routing + forward auth |

## Hardware

### `void` — homelab node

| | |
|---|---|
| Hardware | Lenovo ThinkCentre M710q |
| CPU | Intel Core i5-7500T |
| RAM | 8 GB (up to 32 GB) |
| Storage | 256 GB NVMe + optional SATA slot |
| OS | Ubuntu Server 24.04 LTS |
| Network | LAN static IPs, Tailscale for remote access |

### `core` — workstation (not part of the lab)

| | |
|---|---|
| CPU | AMD Ryzen 5 5600X |
| GPU | NVIDIA RTX 3060 Ti |
| RAM | 32 GB |
| Storage | 1 TB NVMe + 2 TB SATA |

## Constraints

- **RAM:** 8 GB covers the current stack; media services may need 16 GB+
- **Storage:** 256 GB is tight for a media library; SATA expansion available
