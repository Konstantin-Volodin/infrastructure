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
    ok ".env file created."
fi

# ===== start services =====
# info "starting pihole ..."
# cd services/pihole
# docker compose down
# docker compose --env-file ../../.env up -d
# ok "pihole done."

info "starting immich ..."
cd services/immich
docker compose --env-file ../../.env down
docker compose --env-file ../../.env up -d
ok "immich up."

info "starting mealie ..."
cd ../../services/mealie
docker compose --env-file ../../.env down
docker compose --env-file ../../.env up -d
ok "mealie up."

# info "starting authentik ..."
# cd ../../services/authentik
# docker compose --env-file ../../.env down
# docker compose --env-file ../../.env up -d
# ok "authentik up."