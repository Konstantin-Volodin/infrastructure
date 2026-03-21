#!/bin/bash
# =============================================================================
# build.sh 
# 	- starts all services in the infrastructure stack. 
# 	- run after cloning the repo and running setup.sh to provision the infrastructure. 
# 	- creates an .env file with random secrets and start the services.
# =============================================================================

REMOTE="void"

info() { echo "  [·] $*"; }
ok()   { echo "  [✓] $*"; }
warn() { echo "  [!] $*"; }
die()  { echo "  [✗] $*" >&2; exit 1; }

set -euo pipefail
[[ $EUID -ne 0 ]] && die "run as root: sudo bash setup.sh"

# ===== create .env file =====
info "creating .env file with random secrets..."
if [ -f .env ]; then
    ok ".env file already exists."
else
    cp .env.example .env
    read -rp "  [?] Tailscale OAuth client secret: " ts_authkey
    echo "TS_AUTHKEY=${ts_authkey}?ephemeral=false" >> .env
    echo "IMMICH_DB_PASSWORD=$(openssl rand -hex 128 | tr -d '\n')" >> .env
    echo "AUTHENTIK_DB_PASSWORD=$(openssl rand -hex 128 | tr -d '\n')" >> .env
    echo "AUTHENTIK_SECRET_KEY=$(openssl rand -hex 128 | tr -d '\n')" >> .env
    echo "AUTHELIA_SESSION_SECRET=$(openssl rand -hex 64 | tr -d '\n')" >> .env
    echo "AUTHELIA_STORAGE_ENCRYPTION_KEY=$(openssl rand -hex 64 | tr -d '\n')" >> .env
    echo "AUTHELIA_OIDC_HMAC_SECRET=$(openssl rand -hex 64 | tr -d '\n')" >> .env
    echo "IMMICH_OIDC_SECRET=$(openssl rand -hex 32 | tr -d '\n')" >> .env
    echo "MEALIE_OIDC_SECRET=$(openssl rand -hex 32 | tr -d '\n')" >> .env
    ok ".env file created."
fi

# ===== generate authelia secret =====
mkdir -p services/authelia/secrets
docker run -d --rm -v "${PWD}/services/authelia/configuration.yml:/config/configuration.yml" -v "${PWD}/services/authelia/secrets:/config/secrets" --name authelia-secret authelia/authelia:latest generate-secret > /

# # ===== generate authelia oidc private key =====
# if [ ! -f services/authelia/config/oidc.pem ]; then
#     info "generating Authelia OIDC private key..."
#     openssl genrsa -out services/authelia/config/oidc.pem 2048
#     ok "OIDC private key generated."
# fi

# ===== start services =====
# info "starting pihole ..."
# cd services/pihole
# docker compose down
# docker compose --env-file ../../.env up -d
# ok "pihole done."

info "generating immich config..."
set -a; source .env; set +a
envsubst < services/immich/config/immich.json.tmpl > services/immich/config/immich.json
ok "immich config generated."

info "starting immich ..."
cd ${PWD}/services/immich
docker compose --env-file ../../.env down
docker compose --env-file ../../.env up -d
ok "immich up."

info "starting mealie ..."
cd ${PWD}/services/mealie
docker compose --env-file ../../.env down
docker compose --env-file ../../.env up -d
ok "mealie up."

info "starting authelia ..."
cd ${PWD}/services/authelia
docker compose --env-file ../../.env down
docker compose --env-file ../../.env up -d
ok "authelia up."

# info "starting authentik ..."
# cd ${PWD}/services/authentik
# docker compose --env-file ../../.env down
# docker compose --env-file ../../.env up -d
# ok "authentik up."