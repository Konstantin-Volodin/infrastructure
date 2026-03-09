# void infrastructure

Canonical overview for a small self-hosted homelab running on `void`.

This repo is meant to stay reproducible, container-first, and easy to fork for someone building a similar setup at home.

## Overview

- **Primary node:** `void`
- **Network / Wi-Fi:** `nexus`
- **Target OS:** Ubuntu Server 24.04 LTS
- **Access model:** private remote access through Tailscale
- **Service model:** Docker Compose per service
- **Current state:** Pi-hole is installed; Tailscale and Authentik are next

## Goals

- Keep the homelab reproducible from this repository
- Run services in containers instead of ad-hoc host config
- Access services remotely without opening router ports
- Build toward a clean, public, fork-friendly self-hosted stack

## Infrastructure

### `void` — active homelab node

| Item | Value |
|---|---|
| Hostname | `void` |
| Role | Initial / primary homelab node |
| Hardware | Lenovo ThinkCentre M710q |
| CPU | Intel Core i5-7500T |
| RAM | 8 GB installed, upgradeable up to 32 GB |
| Storage | 256 GB total |
| Drive layout | 1x NVMe installed, optional 1x SATA slot |
| OS | Ubuntu Server 24.04 LTS |

### `core` — side-note workstation

`core` is not part of the homelab service stack. It is a separate gaming/workstation machine that may be used to manage the lab.

| Item | Value |
|---|---|
| Role | External workstation, not a node |
| CPU | AMD Ryzen 5 5600X |
| GPU | NVIDIA RTX 3060 Ti |
| RAM | 32 GB |
| Storage | 1 TB NVMe + 2 TB SATA |

## Architecture

The intended Phase 1 flow is:

```text
Remote device
	|
	v
Tailscale
	|
	v
void
├── Pi-hole     (DNS + ad blocking)
├── Authentik   (SSO / identity)
├── Caddy       (reverse proxy + HTTPS)
└── Nextcloud   (files, docs, calendar)
```

Design principles:

- No router port forwarding required for normal remote access
- Services should eventually sit behind consistent URLs
- Authentication should be centralized where practical
- Repo state should reflect real infrastructure state

## Current status

### Completed

- Ubuntu Server installed on `void`
- Base bootstrap script created for host setup
- Docker installed on the node
- Pi-hole installed on `void`

### Next

1. **Tailscale** — establish stable private remote access to `void`
2. **Authentik** — stand up SSO / identity provider
3. **Caddy** — add reverse proxy once service naming is settled
4. **Nextcloud** — add storage / collaboration services after auth and routing are in place

### Planned later

- Jellyfin
- Sonarr / Radarr
- Prowlarr
- qBittorrent + Gluetun
- Other optional self-hosted services such as Uptime Kuma, Vaultwarden, Gitea, Home Assistant, or Immich

## Service roadmap

| Phase | Service | Purpose | Status |
|---|---|---|---|
| 1 | Pi-hole | DNS + ad blocking | Installed |
| 1 | Tailscale | Private remote access | Next |
| 1 | Authentik | SSO / authentication | Next |
| 1 | Caddy | Reverse proxy + HTTPS | Planned |
| 1 | Nextcloud | Files, docs, calendar | Planned |
| 2 | Jellyfin | Media server | Future |
| 2 | Sonarr / Radarr | Media automation | Future |
| 2 | Prowlarr | Indexer management | Future |
| 2 | qBittorrent + Gluetun | Torrenting over VPN | Future |

## Repository layout

This is the current repo structure, based on what is actually checked in today:

```text
infrastructure/
├── README.md
├── .env.example
├── docs/
│   ├── setup.md
│   └── networking.md
└── services/
	├── authentik/
	│   └── docker-compose.yml
	└── setup/
		└── void.sh
```

Important files:

- [README.md](README.md) — canonical repo overview
- [docs/setup.md](docs/setup.md) — setup notes in progress
- [docs/networking.md](docs/networking.md) — networking notes and placeholders
- [services/setup/void.sh](services/setup/void.sh) — base host bootstrap script for `void`
- [services/authentik/docker-compose.yml](services/authentik/docker-compose.yml) — Authentik stack definition

## Bootstrapping `void`

The base host bootstrap script is [services/setup/void.sh](services/setup/void.sh).

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

Current known facts:

- network name / SSID: `nexus`
- Pi-hole is already installed on `void`
- Tailscale is not yet configured
- final service URLs are not assigned yet

Known placeholders still to fill in:

- Tailscale IP for `void`
- tailnet domain / hostname
- DNS naming convention for internal services
- public-facing or tailnet-facing service URLs
- final reverse-proxy routing rules

## Environment variables

The current [.env.example](.env.example) is minimal and will need expansion as more services are added.

Known values referenced by the repo today include:

- `PIHOLE_TIMEZONE`
- `AUTHENTIK_POSTGRES_PASSWORD`
- `AUTHENTIK_SECRET_KEY`

## Constraints and upgrade notes

- **RAM:** 8 GB is enough for the foundation stack, but the media stack may benefit from 16 GB or more
- **Storage:** 256 GB is fine for infrastructure services but too small for a serious media library
- **Drive expansion:** `void` has room for the current NVMe drive plus an optional SATA drive
- **No public domain required:** Tailscale should cover private remote access without open ports

## Priority order from here

1. Finish documenting the current Pi-hole setup
2. Install and verify Tailscale on `void`
3. Record the Tailscale IP and hostname
4. Bring up Authentik from [services/authentik/docker-compose.yml](services/authentik/docker-compose.yml)
5. Expand `.env.example` as service requirements become real
6. Add Caddy and settle service URL conventions
7. Add Nextcloud

## Notes

This README is the main summary of the repo.

Some supporting docs still contain older planning notes and placeholders, so they should be treated as secondary until they are cleaned up.