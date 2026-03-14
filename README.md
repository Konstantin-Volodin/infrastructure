# self-hosted lab `void`.
- reproducible
- container-first
- infrastructure as code


### services:
- Pi-hole (DNS + ad blocking)
- Immich (photo + video backup)
- Mealie (recipe manager)
- Authentik (SSO / identity) - TODO
- Caddy (reverse proxy + HTTPS) - TODO
- Nextcloud (files, docs, calendar) - TODO
- Jellyfin (media server) - TODO
- Sonarr / Radarr (media automation) - TODO
- Prowlarr (indexer management) - TODO
- qBittorrent + Gluetun (torrenting over VPN) - TODO
- book management platform (TBD)

### accessing services

| service 		| Via Tailscale 					|
|---------------|-----------------------------------|
| SSH 			| `ssh void` 						|
| Pi-hole UI 	| `http://<tailscale-ip>/admin` 	|
| Immich 		| `http://<tailscale-ip>:2283` 		|
| Mealie 		| `http://<tailscale-ip>:9925` 		|

## overview

- **nodes:** `void`
- **target OS:** Ubuntu Server 24.04 LTS
- **access model:** private remote access through Tailscale
- **service model:** Docker Compose per service
- **current state:** Pi-hole, Immich, and Mealie are installed; Authentik next

### goals
- keep the homelab reproducible from this repository
- run services in containers instead of ad-hoc host config
- access services remotely without relying on external services
- build toward a clean, public, fork-friendly self-hosted stack

### design principles:
- services should eventually sit behind consistent URLs
- authentication should be centralized where practical
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

### Next

1. **Authentik** - stand up SSO / identity provider
2. **Caddy** - add reverse proxy once service naming is settled
3. **Nextcloud** - add storage / collaboration services after auth and routing are in place

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
| 1     | Tailscale              | Private remote access  | Installed  |
| 1     | Immich                 | Photo + video backup   | Installed  |
| 1     | Mealie                 | Recipe manager         | Installed  |
| 1     | Authentik              | SSO / authentication   | Next       |
| 1     | Caddy                  | Reverse proxy + HTTPS  | Planned    |
| 2     | Nextcloud              | Files, docs, calendar  | Future     |
| 2     | Jellyfin               | Media server           | Future     |
| 2     | Sonarr / Radarr        | Media automation       | Future     |
| 2     | Prowlarr               | Indexer management     | Future     |
| 2     | qBittorrent + Gluetun  | Torrenting over VPN    | Future     |
| 2     | Book management        | TBD                    | Future     |


## Important files:
- [services/setup.sh](services/setup.sh) - base host bootstrap script for `void`
- [services/pihole/docker-compose.yml](services/pihole/docker-compose.yml) - Pi-hole stack definition
- [services/authentik/docker-compose.yml](services/authentik/docker-compose.yml) - Authentik stack definition
- [services/immich/docker-compose.yml](services/immich/docker-compose.yml) - Immich stack definition
- [services/mealie/docker-compose.yml](services/mealie/docker-compose.yml) - Mealie stack definition


## bootstrapping `void`

The base host bootstrap script is [services/setup.sh](services/setup.sh).

At a high level it handles:

- system updates
- disabling sleep / suspend
- SSH hardening
- UFW firewall defaults
- fail2ban setup
- static Ethernet and Wi-Fi configuration
- Docker installation
- disabling the systemd DNS stub listener so Pi-hole can use port `53`

This script is intended for initial host preparation before the service stack is layered on top.


## Networking notes

- **LAN setup:** xxx.xxx.x.100 for void:cable and xxx.xxx.x.101 for void:wifi.
- **Tailscale:** not setup yet but will be used for remote access, so no port forwarding or external DNS configuration is needed.


## Constraints and upgrade notes

- **RAM:** 8 GB is enough for the foundation stack, but the media stack may benefit from 16 GB or more
- **Storage:** 256 GB is fine for infrastructure services but too small for a serious media library
- **Drive expansion:** `void` has room for the current NVMe drive plus an optional SATA drive
- **No external accounts required:** Tailscale covers private remote access with no third-party dependency beyond Tailscale itself