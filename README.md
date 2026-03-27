# self-hosted lab `void`.
- reproducible
- container-first
- infrastructure as code


### services:
- Pi-hole (DNS + ad blocking)
- Immich (photo + video backup)
- Mealie (recipe manager)
- Authelia (SSO / identity)
- Caddy (reverse proxy + forward auth)
- Nextcloud (files, docs, calendar) - TODO
- Jellyfin (media server) - TODO
- Sonarr / Radarr (media automation) - TODO
- Prowlarr (indexer management) - TODO
- qBittorrent + Gluetun (torrenting over VPN) - TODO
- book management platform (TBD)

### accessing services

| service 		| URL 									|
|---------------|-------------------------------------------|
| SSH 			| `ssh void` 								|
| Pi-hole UI 	| `http://<host-ip>:8080/admin` 			|
| Authelia 		| `https://auth.voxlab.home` 				|
| Immich 		| `https://photos.voxlab.home` 				|
| Mealie 		| `https://recipes.voxlab.home` 			|

## overview

- **nodes:** `void`
- **target OS:** Ubuntu Server 24.04 LTS
- **access model:** private remote access through Tailscale
- **networking model:** Caddy reverse proxy with Authelia forward auth. Pi-hole provides local DNS for `*.voxlab.home` subdomains.
- **service model:** Docker Compose per service
- **current state:** Pi-hole, Immich, Mealie, Authelia, and Caddy are installed

### goals
- keep the homelab reproducible from this repository
- run services in containers instead of ad-hoc host config
- access services remotely without relying on external services
- build toward a clean, public, fork-friendly self-hosted stack

### design principles:
- all services sit behind Caddy as reverse proxy with Authelia forward auth
- authentication is centralized through Authelia (forward auth + OIDC for supported services)
- Pi-hole provides DNS resolution for `*.voxlab.home` subdomains
- repo state should reflect real infrastructure state

## infrastructure

### `void` - active homelab node

| Item           | Value                                   |
|----------------|-----------------------------------------|
| name           | `void`                                  |
| role           | primary homelab node                    |
| hardware       | Lenovo ThinkCentre M710q                |
| CPU            | Intel Core i5-7500T                     |
| RAM            | 8 GB installed, upgradeable up to 32 GB |
| storage        | 256 GB total                            |
| drive layout   | 1x NVMe installed, optional 1x SATA slot|
| OS             | Ubuntu Server 24.04 LTS                 |


### `core` - workstation
`core` is not part of the homelab service stack. It is a separate workstation machine that may be used to manage the lab.

| Item    | Value                            |
|---------|----------------------------------|
| role    | External workstation             |
| CPU     | AMD Ryzen 5 5600X                |
| GPU     | NVIDIA RTX 3060 Ti *(upgrade?)*  |
| RAM     | 32 GB                            |
| storage | 1 TB NVMe + 2 TB SATA            |

> **Note:** Considering a GPU upgrade for `core`? :)

## Current status

### Completed

- Ubuntu Server installed on `void`
- Base bootstrap script created for host setup
- Docker installed on `void`
- Tailscale installed on `void`
- Pi-hole installed on `void`
- Immich installed on `void`
- Mealie installed on `void`
- Authelia installed on `void`
- Caddy reverse proxy + Authelia forward auth

### Next

1. **Nextcloud** - add storage / collaboration services

### Planned later

- books
- Jellyfin
- Sonarr / Radarr
- Prowlarr
- qBittorrent + Gluetun
- Other optional self-hosted services such as Uptime Kuma, Vaultwarden, Gitea, Home Assistant

## Service roadmap

| Phase | Service                | Purpose                | Status     |
|-------|------------------------|------------------------|------------|
| 1     | Pi-hole                | DNS + ad blocking      | Installed  |
| 1     | Caddy                  | Reverse proxy + TLS    | Installed  |
| 1     | Authelia               | SSO / authentication   | Installed  |
| 1     | Immich                 | Photo + video backup   | Installed  |
| 1     | Mealie                 | Recipe manager         | Installed  |
| 2     | Book management        | TBD                    | Future     |
| 2     | Jellyfin               | Media server           | Future     |
| 2     | Sonarr / Radarr        | Media automation       | Future     |
| 2     | Prowlarr               | Indexer management     | Future     |
| 2     | qBittorrent + Gluetun  | Torrenting over VPN    | Future     |
| 2     | Nextcloud              | Files, docs, calendar  | Future     |


## Important files:
- [prepare-linux.sh](prepare-linux.sh) - base host bootstrap script for `void`
- [services/caddy/docker-compose.yml](services/caddy/docker-compose.yml) - Caddy reverse proxy
- [services/caddy/Caddyfile](services/caddy/Caddyfile) - Caddy routing + forward auth config
- [services/pihole/docker-compose.yml](services/pihole/docker-compose.yml) - Pi-hole stack definition
- [services/authelia/docker-compose.yml](services/authelia/docker-compose.yml) - Authelia stack definition
- [services/immich/docker-compose.yml](services/immich/docker-compose.yml) - Immich stack definition
- [services/mealie/docker-compose.yml](services/mealie/docker-compose.yml) - Mealie stack definition


## bootstrapping `void`

git clone git@github.com:Konstantin-Volodin/infrastructure.git

The base host bootstrap script is [prepare-linux.sh](prepare-linux.sh).

At a high level it handles:

- system updates
- disabling sleep / suspend
- SSH hardening (pubkey only, no root login)
- UFW firewall defaults (deny all except SSH, DNS, HTTP, HTTPS)
- fail2ban setup (5 failed SSH attempts = 24h ban)
- static Ethernet and Wi-Fi configuration via Netplan
- Docker installation
- disabling the systemd DNS stub listener so Pi-hole can use port `53`

This script is intended for initial host preparation before the service stack is layered on top.

## Starting Services
run `sudo bash start-services.sh` in root of this git repo

## Post-setup: Tailscale DNS
After `start-services.sh` completes, configure Tailscale to use Pi-hole for DNS so all devices on the tailnet can resolve `*.voxlab.home`:

1. Get void's Tailscale IP: `tailscale ip -4`
2. Go to **Tailscale admin console → DNS → Nameservers**
3. Add a **custom nameserver** with void's Tailscale IP (the `100.x.x.x` address)
4. Check **"Restrict to domain"** and enter `voxlab.home`

This routes only `*.voxlab.home` queries to Pi-hole. All other DNS works normally.

## Post-setup: Authelia first login
To setup Authelia for the first time, use the one-time password.

To access the one-time password generated, run:
```bash
sudo docker exec authelia cat /data/notification.txt
```



## Networking notes

- **LAN setup:** xxx.xxx.x.100 for void:cable and xxx.xxx.x.101 for void:wifi.
- **DNS:** Pi-hole provides a wildcard `*.voxlab.home` record pointing to the host IP. All services are accessed via `<service>.voxlab.home` subdomains.
- **Reverse proxy:** Caddy terminates TLS (internal CA) and routes traffic to services by hostname. Authelia forward auth protects all routes.
- **Remote access:** Tailscale provides private VPN access to the host. Services are reachable over Tailscale as long as the client uses Pi-hole for DNS.


## Constraints and upgrade notes

- **RAM:** 8 GB is enough for the foundation stack, but the media stack may benefit from 16 GB or more
- **Storage:** 256 GB is fine for infrastructure services but too small for a serious media library
- **Drive expansion:** `void` has room for the current NVMe drive plus an optional SATA drive
