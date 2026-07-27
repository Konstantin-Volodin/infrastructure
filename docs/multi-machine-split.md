# Plan: Split infrastructure across void and abyss

## Context

Currently all services run on a single machine (void). The goal is to split services across two machines so void handles core/security (Caddy, Authelia, Pi-hole, Homepage) and abyss handles apps/media (Immich, Mealie, and future media stack). Both machines are on Tailscale. Caddy stays on void only and reverse proxies to abyss via Tailscale IP.

## Decisions
- **Script**: Single `deploy.sh [void|abyss]` with shared `lib/` helpers
- **Secrets**: `deploy.sh push-secrets` (scp) for now, NFS in Phase 2
- **Caddy**: void only, proxies to abyss via `{$ABYSS_TAILSCALE_IP}:port`
- **Network**: Abyss services expose ports on host, no `proxy` Docker network on abyss

## File changes

### New files

1. **`deploy.sh`** - single entrypoint, replaces `start-services.sh`
   - Accepts `void`, `abyss`, or `push-secrets` as argument
   - `void`: generate secrets + CA + Authelia keys, start void.yml, configure Pi-hole DNS, fix ownership
   - `abyss`: verify .env + CA cert exist, template immich config, start abyss.yml, fix ownership
   - `push-secrets`: scp `.env` and `$CONFIG_DIR/ca/combined-ca.crt` to abyss

2. **`lib/common.sh`** - shared logging helpers (`info`, `ok`, `warn`, `die`), env loading

3. **`lib/secrets.sh`** - `.env` generation, Authelia key + password hash generation

4. **`lib/certs.sh`** - internal CA generation, combined bundle creation

5. **`services/void.yml`** - compose includes for void services only
   ```yaml
   networks:
     proxy:
       name: proxy
       external: true
   include:
     - path: caddy/docker-compose.yml
     - path: authelia/docker-compose.yml
     - path: pihole/docker-compose.yml
     - path: homepage/docker-compose.yml
   ```

6. **`services/abyss.yml`** - compose includes for abyss services only
   ```yaml
   networks:
     immich:
       name: immich
   include:
     - path: immich/docker-compose.yml
     - path: mealie/docker-compose.yml
   ```

7. ~~**`shared/`** directory~~ - no longer needed. The CA bundle already lives outside the repo at `$CONFIG_DIR/ca/combined-ca.crt`, so `push-secrets` copies it to the same path on abyss and both machines mount it identically.

### Modified files

8. **`services/caddy/Caddyfile`** - remote services use Tailscale IP instead of container names
   - `photos.{$DOMAIN}` → `reverse_proxy {$ABYSS_TAILSCALE_IP}:2283`
   - `recipes.{$DOMAIN}` → `reverse_proxy {$ABYSS_TAILSCALE_IP}:9000`
   - Local services (auth, dns, apps) unchanged

9. **`services/immich/docker-compose.yml`**
   - Remove `proxy` network from immich-server
   - Add `ports: ["2283:2283"]` to immich-server
   - Change extra_hosts: `auth.${DOMAIN}:${HOST_IP}` → `auth.${DOMAIN}:${VOID_TAILSCALE_IP}`

10. **`services/mealie/docker-compose.yml`**
    - Remove `proxy` network
    - Add `ports: ["9000:9000"]`
     - Change extra_hosts: `auth.${DOMAIN}:${HOST_IP}` → `auth.${DOMAIN}:${VOID_TAILSCALE_IP}`

11. **`.env.example`** - add new variables:
    - `VOID_TAILSCALE_IP=` (e.g., 100.x.x.x)
    - `ABYSS_TAILSCALE_IP=` (e.g., 100.x.x.x)
    - `ABYSS_SSH=` (e.g., vox@abyss, used by push-secrets)

12. ~~**`.gitignore`** - add `shared/`~~ - dropped along with `shared/`

13. **`README.md`** - update with two-machine setup instructions

14. **`start-services.sh`** - delete (replaced by deploy.sh)

15. **`services/docker-compose.yml`** - delete (replaced by void.yml / abyss.yml)

## Implementation order

1. Create `lib/common.sh`, `lib/secrets.sh`, `lib/certs.sh` by extracting from `start-services.sh`
2. Create `services/void.yml` and `services/abyss.yml`
3. Create `deploy.sh` with void/abyss/push-secrets modes
4. Update `.env.example` with new variables
5. Modify Caddyfile for remote reverse proxy
6. Modify immich and mealie compose files (ports, extra_hosts, remove proxy network)
7. Update README.md
8. Delete `start-services.sh` and `services/docker-compose.yml`

## Verification

1. On void: `sudo bash deploy.sh void` - all core services start, Pi-hole DNS configured
2. `sudo bash deploy.sh push-secrets` - .env and CA cert copied to abyss
3. On abyss: `sudo bash deploy.sh abyss` - Immich and Mealie start
4. From phone/laptop on Tailscale: verify `https://photos.voxlab.home` and `https://recipes.voxlab.home` load through Caddy on void
5. Verify Authelia OIDC login works from Immich (mobile + web)
6. Verify `https://apps.voxlab.home` shows container status for both machines
