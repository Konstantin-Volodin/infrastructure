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

**Tailscale DNS** - route `*.voxlab.home` queries to Pi-hole:
1. Get void's Tailscale IP: `tailscale ip -4`
2. Tailscale admin → DNS → Nameservers → add custom nameserver with the `100.x.x.x` address
3. Restrict to domain: `voxlab.home`

**Authelia first login** - get the one-time password: `sudo docker exec authelia cat /data/notification.txt`

**Pihole login** - password to access pihole website `sudo docker logs pihole | grep "password"`

**Trust the internal CA** - Caddy uses a self-signed CA for TLS. Client devices need to trust it to avoid certificate warnings.
1. Download the CA cert from void: `scp vox@void:~/infrastructure/services/caddy/pki/internal-ca.crt .`
2. Firefox (PC): Settings → Privacy & Security → Certificates → View Certificates → Authorities → Import → check "Trust this CA to identify websites"
3. Android: Settings → Security → Encryption & credentials → Install a certificate → CA certificate

## Services

| Service               | URL                              | Status    |
|-----------------------|----------------------------------|-----------|
| Pi-hole               | `https://dns.voxlab.home/admin/` | Installed |
| Caddy                 | -                                | Installed |
| Authelia              | `https://auth.voxlab.home`       | Installed |
| Immich                | `https://photos.voxlab.home`     | Installed |
| Mealie                | `https://recipes.voxlab.home`    | Installed |
| Homepage              | `https://apps.voxlab.home`       | Installed |
| Jellyfin              | -                                | Planned   |
| Sonarr / Radarr       | -                                | Planned   |
| Prowlarr              | -                                | Planned   |
| qBittorrent + Gluetun | -                                | Planned   |
| Diun                  | -                                | Planned   |
| Nextcloud             | -                                | Planned   |

### Architecture

- Reverse proxy: Caddy terminates TLS (internal CA), routes by hostname
- Auth: Authelia forward auth for all routes + OIDC for Immich and Mealie
- DNS: Pi-hole serves wildcard `*.voxlab.home` to host IP
- Remote access: Tailscale VPN + Pi-hole DNS
- Containers: Docker Compose per service with shared `proxy` network

## Key files

| File                                | Purpose                                       |
|-------------------------------------|-----------------------------------------------|
| prepare-linux.sh                    | Host bootstrap                                |
| start-services.sh                   | Secret generation + startup                   |
| services/docker-compose.yml         | Top-level compose (includes all services)     |
| services/caddy/Caddyfile            | Routing + forward auth                        |

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
