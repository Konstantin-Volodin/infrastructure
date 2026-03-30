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

# ===== create or update .env file =====
if [ -f .env ]; then
    info "syncing new variables from .env.example..."
    while IFS= read -r line; do
        key="${line%%=*}"
        [[ -z "$key" || "$key" == \#* || "$key" == "$line" ]] && continue
        grep -q "^${key}=" .env || echo "$line" >> .env
    done < .env.example
    ok ".env synced."
else
    info "creating .env from .env.example..."
    cp .env.example .env
    ok ".env created."
fi

# ===== resolve relative paths to absolute =====
info "resolving storage paths..."
for key in DOWNLOADS_PATH QBITTORRENT_CONFIG PROWLARR_CONFIG BOOKS_PATH BOOKS_INGEST SHELFMARK_CONFIG CALIBREWEB_CONFIG IMMICH_UPLOADS IMMICH_DB_DATA MEALIE_DATA; do
    val=$(grep "^${key}=" .env | cut -d= -f2- | tr -d '\r')
    if [[ "$val" == ./* ]]; then
        abs="${PWD}/${val#./}"
        sed -i "s|^${key}=.*|${key}=${abs}|" .env
    fi
done
ok "storage paths resolved."

# ===== populate auto-generated secrets (only if missing) =====
gen_secret() {
    local key="$1"
    if ! grep -q "^${key}=.\+" .env; then
        sed -i "s/^${key}=.*/${key}=$(openssl rand -hex 128 | tr -d '\n')/" .env
        ok "generated ${key}"
    fi
}

# detect host IP
HOST_IP=$(hostname -I | awk '{print $1}')
sed -i "s/^HOST_IP=.*/HOST_IP=${HOST_IP}/" .env
ok "detected host IP: ${HOST_IP}"

gen_secret DB_PASSWORD
gen_secret AUTHELIA_JWT_PASSWORD
gen_secret AUTHELIA_SESSION_SECRET
gen_secret AUTHELIA_STORAGE_ENCRYPTION_KEY
gen_secret AUTHELIA_OIDC_HMAC_SECRET
gen_secret IMMICH_OIDC_SECRET
gen_secret MEALIE_OIDC_SECRET

# ===== prompt for user-provided credentials (only if missing) =====
prompt_credential() {
    local key="$1" prompt="$2" secret="${3:-false}"
    if ! grep -q "^${key}=.\+" .env; then
        if [ "$secret" = true ]; then
            read -rsp "  ${prompt}: " value; echo
        else
            read -rp "  ${prompt}: " value
        fi
        sed -i "s/^${key}=.*/${key}=${value}/" .env
        ok "${key} set."
    fi
}

info "checking user credentials..."
prompt_credential PROTONVPN_OPENVPN_USER "ProtonVPN OpenVPN username (from account.protonvpn.com/account#openvpn)"
prompt_credential PROTONVPN_OPENVPN_PASSWORD "ProtonVPN OpenVPN password" true

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



# ===== generate combined CA bundle (system CAs + caddy internal CA) =====
if [ -f services/caddy/combined-ca.crt ]; then
    ok "combined CA bundle already exists."
else
    info "generating internal CA cert..."
    mkdir -p services/caddy/pki
    openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
        -keyout services/caddy/pki/internal-ca.key \
        -out services/caddy/pki/internal-ca.crt \
        -subj "/CN=Void Internal CA"
    cat /etc/ssl/certs/ca-certificates.crt services/caddy/pki/internal-ca.crt > services/caddy/combined-ca.crt
    ok "combined CA bundle created."
fi

# ===== create data directories with correct ownership =====
info "ensuring data directories exist with correct ownership..."
REAL_USER="${SUDO_USER:-$USER}"
REAL_UID=$(id -u "$REAL_USER")
REAL_GID=$(id -g "$REAL_USER")

dirs=(
    data/downloads
    data/qbittorrent
    data/prowlarr
    data/books
    data/books-ingest
    data/shelfmark
    data/calibre-web
    data/immich-uploads
    data/immich-postgres
    data/mealie
)
for dir in "${dirs[@]}"; do
    mkdir -p "$dir"
    chown -R "$REAL_UID:$REAL_GID" "$dir"
done
ok "data directories ready."

# ===== create docker network =====
docker network inspect proxy >/dev/null 2>&1 || docker network create proxy
ok "proxy network ready."

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
TAILSCALE_IP=$(tailscale ip -4)
docker exec pihole pihole-FTL --config misc.dnsmasq_lines "[\"address=/.${DOMAIN}/${TAILSCALE_IP}\"]"
ok "pihole DNS configured."

# ===== fix ownership for git pull =====
# only fix git-tracked files so pull works; leave secrets/data root-owned.
git ls-files -z | xargs -0 chown "$REAL_USER":"$REAL_USER"
ok "git-tracked file ownership fixed for $REAL_USER."
