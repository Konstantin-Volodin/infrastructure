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
    echo "DB_PASSWORD=$(openssl rand -hex 128 | tr -d '\n')" >> .env

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

    # generate admin password hash and write it to users_database.yml
    ADMIN_HASH=$(docker exec temp-authelia authelia crypto hash generate --config "/config/configuration.yml" --password "authelia" | grep -oP '(?<=Digest: ).*')
    sed -i "s|^    password:.*|    password: '$ADMIN_HASH'|" services/authelia/config/users_database.yml
    ok "admin password hash written."

    # generate OIDC RSA keypair
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



# ===== create docker network =====
docker network inspect proxy >/dev/null 2>&1 || docker network create proxy
ok "proxy network ready."

# ===== fix ownership of git-tracked files =====
# Docker runs as root and may write to mounted config dirs, making git pull fail.
REAL_USER="${SUDO_USER:-$USER}"
git ls-files -z | xargs -0 chown "$REAL_USER":"$REAL_USER"
ok "git-tracked file ownership fixed for $REAL_USER."

# ===== start all services =====
info "starting all services..."
cd ${PWD}/services
set -a; source ../.env; set +a
docker compose down
docker compose up -d
ok "all services up."

# ===== configure pihole wildcard DNS =====
info "waiting for pihole to be ready..."
until docker exec pihole pihole status 2>/dev/null | grep -q "blocking is enabled"; do sleep 2; done
ok "pihole is ready."

info "configuring pihole wildcard DNS for *.${DOMAIN}..."
docker exec pihole pihole-FTL --config misc.dnsmasq_lines "[\"address=/.${DOMAIN}/${HOST_IP}\"]"
ok "pihole DNS configured."
