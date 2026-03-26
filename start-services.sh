#!/bin/bash
# =============================================================================
# start-services.sh
# 	- starts all services in the infrastructure stack.
# 	- run after cloning the repo and running prepare-linux.sh to provision the host.
# 	- creates an .env file with random secrets and start the services.
# =============================================================================

REMOTE="void"

info() { echo "  [·] $*"; }
ok()   { echo "  [✓] $*"; }
warn() { echo "  [!] $*"; }
die()  { echo "  [✗] $*" >&2; exit 1; }

set -euo pipefail
[[ $EUID -ne 0 ]] && die "run as root: sudo bash start-services.sh"

# ===== create .env file =====
info "creating .env file with random secrets..."
if [ -f .env ]; then
    ok ".env file already exists."
else
    cp .env.example .env

    # immich database password
    echo "IMMICH_DB_PASSWORD=$(openssl rand -hex 128 | tr -d '\n')" >> .env

    # authelia secrets
    echo "AUTHELIA_JWT_PASSWORD=$(openssl rand -hex 128 | tr -d '\n')" >> .env
    echo "AUTHELIA_SESSION_SECRET=$(openssl rand -hex 128 | tr -d '\n')" >> .env
    echo "AUTHELIA_STORAGE_ENCRYPTION_KEY=$(openssl rand -hex 128 | tr -d '\n')" >> .env
    echo "AUTHELIA_OIDC_HMAC_SECRET=$(openssl rand -hex 128 | tr -d '\n')" >> .env

    # oidc client secrets (must match authelia identity provider config)
    echo "IMMICH_OIDC_SECRET=$(openssl rand -hex 128 | tr -d '\n')" >> .env
    echo "MEALIE_OIDC_SECRET=$(openssl rand -hex 128 | tr -d '\n')" >> .env

    # done
    ok ".env file created."
fi

# ===== generate authelia admin =====
if [ -f services/authelia/secrets/oidc.jwks.key ]; then
    ok "authelia keys already exist, skipping generation."
else
    info "generating authelia admin + OIDC keys..."
    mkdir -p services/authelia/secrets
    docker run -d --rm -v "${PWD}/services/authelia/config/configuration.yml:/config/configuration.yml" -v "${PWD}/services/authelia/secrets:/config/secrets" --name "temp-authelia" authelia/authelia:latest sleep infinity
    docker exec temp-authelia authelia crypto hash generate --config "/config/configuration.yml" --password "authelia" | grep -oP '(?<=Digest: ).*'
    docker exec temp-authelia authelia crypto pair rsa generate --directory /config/secrets
    mv services/authelia/secrets/private.pem services/authelia/secrets/oidc.jwks.key
    mv services/authelia/secrets/public.pem services/authelia/secrets/oidc.jwks.pub
    docker stop temp-authelia
    ok "authelia keys generated."
fi

# ===== generate configs from templates =====
set -a; source .env; set +a

info "generating immich config..."
envsubst < services/immich/config/immich.json.tmpl > services/immich/config/immich.json
ok "immich config generated."

info "generating pihole DNS config..."
envsubst < services/pihole/config/05-void-dns.conf.tmpl > services/pihole/config/05-void-dns.conf
ok "pihole DNS config generated."

# ===== create docker network =====
docker network inspect proxy >/dev/null 2>&1 || docker network create proxy
ok "proxy network ready."

# ===== start all services =====
info "starting all services..."
cd ${PWD}/services
docker compose --env-file ../.env down
docker compose --env-file ../.env up -d
ok "all services up."
