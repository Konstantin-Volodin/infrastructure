# Pi-hole on `void`

Pi-hole is the first live infrastructure service on `void`.

It provides:

- network DNS for the homelab
- ad and tracker blocking
- the initial web UI already exposed on the host

## Current container shape

This stack is defined in [docker-compose.yml](docker-compose.yml).

Key choices in the current setup:

- binds DNS on `53/tcp` and `53/udp`
- binds the web UI on `80/tcp` and `443/tcp`
- persists Pi-hole config in `./etc-pihole`
- sets `FTLCONF_dns_listeningMode=ALL`
- adds the container capabilities Pi-hole commonly needs

## Required environment

Set this in the root `.env` file:

- `PIHOLE_TIMEZONE` — example: `America/Montreal`

## Host prerequisites

The bootstrap script already accounts for the main host-side requirement:

- `systemd-resolved` stub listener must be disabled so Pi-hole can own port `53`

That behavior is documented in [services/setup/void.sh](../setup/void.sh).

## Bring-up notes

From this folder:

1. Start the stack with Docker Compose.
2. Confirm the container stays healthy.
3. Verify DNS answers from another device on the network.
4. Verify the admin UI loads on the host IP.

## Current port usage

Because Pi-hole is already using these host ports, other services should not bind them directly on `void` without a reverse-proxy plan:

- `53/tcp`
- `53/udp`
- `80/tcp`
- `443/tcp`

This matters for later services such as Caddy and any host-networked containers.

## Follow-up cleanup worth doing later

- add the admin password flow to documentation if it is not already stored elsewhere
- document the current upstream DNS choice
- record the host IP that clients should use for DNS
- decide whether Pi-hole stays on `80/443` or eventually sits behind a reverse proxy
- add backup notes for `./etc-pihole`