#!/bin/bash
# =============================================================================
# env.sh
#   syncs .env, generates secrets, bootstraps authelia, prepares the host
#   for `docker compose up`.
#
# usage:
#   sudo bash scripts/env.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/log.sh"
source "$SCRIPT_DIR/lib/env.sh"
source "$SCRIPT_DIR/lib/runtime.sh"

ENV_EXAMPLE=".env.example"
AUTHELIA_USERS_DB="services/authelia/config/users_database.yml"
AUTHELIA_OIDC_KEY="services/authelia/secrets/oidc.jwks.key"
AUTHELIA_BANNER='
  ==============================================================
    Authelia initial admin password (record this NOW —
    plaintext is not stored on disk):

      user:     vox
      password: __PASSWORD__

    Hash applied in:
      services/authelia/config/users_database.yml
    Change the password from the Authelia UI after first login.
  =============================================================='


## ===== env helpers =====

env_get() { grep "^$1=" "$ENV_FILE" | head -n1 | cut -d= -f2- | tr -d '\r'; }

env_has_value() { grep -q "^$1=.\+" "$ENV_FILE" ; }

gen_secret() {
    env_has_value "$1" && return
    env_set "$1" "$(openssl rand -hex 64 | tr -d '\n')"
    ok "generated $1"
}

prompt_credential() {
    local key="$1" prompt="$2" secret="${3:-false}"
    env_has_value "$key" && return
    local value
    if [ "$secret" = true ]; then
        read -rsp "  ${prompt}: " value; echo
    else
        read -rp "  ${prompt}: " value
    fi
    env_set "$key" "$value"
    ok "$key set."
}

sync_env_from_example() {
    if [ ! -f "$ENV_FILE" ]; then
        info "creating ${ENV_FILE} from ${ENV_EXAMPLE}..."
        cp "$ENV_EXAMPLE" "$ENV_FILE"
        ok "${ENV_FILE} created."
        return
    fi
    info "syncing new variables from ${ENV_EXAMPLE}..."
    local added=0
    while IFS= read -r line; do
        local key="${line%%=*}"
        [ -z "$key" ]            && continue
        [[ "$key" == \#* ]]      && continue
        [ "$key" = "$line" ]     && continue
        grep -q "^${key}=" "$ENV_FILE" && continue
        echo "$line" >> "$ENV_FILE"
        added=$((added+1))
    done < "$ENV_EXAMPLE"
    ok "${ENV_FILE} synced (${added} new var(s))."
}

resolve_env_paths() {
    info "resolving storage paths..."
    local key val
    for key in "$@"; do
        val=$(env_get "$key")
        [[ "$val" == ./* ]] && env_set "$key" "$(realpath -m "$val")"
    done
    ok "storage paths resolved."
}


## ===== steps =====

prepare_env() {
    info "preparing environment..."
    sync_env_from_example

    env_has_value DATA_DIR || env_set DATA_DIR "./data"
    resolve_env_paths DATA_DIR

    HOST_IP=$(hostname -I | awk '{print $1}')
    env_set HOST_IP "$HOST_IP"
    ok "detected host IP: ${HOST_IP}"

    if getent group render >/dev/null 2>&1; then
        local render_gid
        render_gid=$(getent group render | cut -d: -f3)
        env_set RENDER_GID "$render_gid"
        ok "detected render group GID: ${render_gid}"
    else
        warn "no 'render' group on host — Jellyfin HW transcoding may fail"
        env_set RENDER_GID "109"
    fi
}

generate_secrets() {
    info "checking generated secrets..."
    gen_secret DB_PASSWORD
    gen_secret AUTHELIA_JWT_PASSWORD
    gen_secret AUTHELIA_SESSION_SECRET
    gen_secret AUTHELIA_STORAGE_ENCRYPTION_KEY
    gen_secret AUTHELIA_OIDC_HMAC_SECRET
    gen_secret IMMICH_OIDC_SECRET
    gen_secret MEALIE_OIDC_SECRET
    gen_secret ACTUAL_OIDC_SECRET

    info "checking user credentials..."
    prompt_credential PROTONVPN_OPENVPN_USER "ProtonVPN OpenVPN username (from account.protonvpn.com/account#openvpn)"
    prompt_credential PROTONVPN_OPENVPN_PASSWORD "ProtonVPN OpenVPN password" true
}

ensure_admin_password() {
    local container="$1"
    grep -Eq '^    password:[[:space:]]*[^[:space:]]+' "$AUTHELIA_USERS_DB" && {
        ok "authelia admin password hash already exists."
        return
    }

    # Plaintext is held in this shell only; it never lands on disk.
    local password hash
    password=$(openssl rand -hex 24)
    hash=$(docker exec "$container" authelia crypto hash generate \
            --config /config/configuration.yml --password "$password" \
        | grep '^Digest:' | sed 's/^Digest: //')
    [ -n "$hash" ] || die "failed to generate authelia admin password hash"

    sed -i "s|^    password:.*|    password: '${hash}'|" "$AUTHELIA_USERS_DB"
    ok "admin password hash written."

    printf '%s\n' "${AUTHELIA_BANNER//__PASSWORD__/$password}"
}

ensure_oidc_keys() {
    local container="$1"
    [ -f "$AUTHELIA_OIDC_KEY" ] && {
        ok "authelia OIDC keys already exist."
        return
    }

    docker exec "$container" authelia crypto pair rsa generate --directory /config/secrets > /dev/null
    mv services/authelia/secrets/private.pem services/authelia/secrets/oidc.jwks.key
    mv services/authelia/secrets/public.pem  services/authelia/secrets/oidc.jwks.pub
    ok "authelia OIDC keys generated."
}

setup_authelia() {
    [ -f "$AUTHELIA_USERS_DB" ] || die "missing $AUTHELIA_USERS_DB"

    if grep -Eq '^    password:[[:space:]]*[^[:space:]]+' "$AUTHELIA_USERS_DB" && [ -f "$AUTHELIA_OIDC_KEY" ]; then
        ok "authelia already bootstrapped."
        return
    fi

    info "bootstrapping authelia..."
    mkdir -p services/authelia/secrets

    local container="temp-authelia-$$"
    docker run -d --rm \
        -v "${PWD}/services/authelia/config/configuration.yml:/config/configuration.yml" \
        -v "${PWD}/services/authelia/secrets:/config/secrets" \
        --name "$container" \
        authelia/authelia:latest sleep infinity > /dev/null
    trap "docker stop $container >/dev/null 2>&1 || true" EXIT

    ensure_admin_password "$container"
    ensure_oidc_keys     "$container"
}

generate_immich_config() {
    info "generating immich config..."
    envsubst < services/immich/config/immich.json.tmpl > services/immich/config/immich.json
    ok "immich config generated."
}

generate_ca_bundle() {
    if [ -f services/caddy/combined-ca.crt ]; then
        ok "combined CA bundle already exists."
        return
    fi

    info "generating internal CA cert..."
    mkdir -p services/caddy/pki
    openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
        -keyout services/caddy/pki/internal-ca.key \
        -out    services/caddy/pki/internal-ca.crt \
        -subj "/CN=Void Internal CA"
    cat /etc/ssl/certs/ca-certificates.crt services/caddy/pki/internal-ca.crt \
        > services/caddy/combined-ca.crt
    ok "combined CA bundle created."
}

create_data_directories() {
    info "ensuring data directories exist with correct ownership..."
    local dirs=(
        "$DATA_DIR/downloads"
        "$DATA_DIR/qbittorrent"
        "$DATA_DIR/prowlarr"
        "$DATA_DIR/sonarr"
        "$DATA_DIR/radarr"
        "$DATA_DIR/tv"
        "$DATA_DIR/movies"
        "$DATA_DIR/jellyfin"
        "$DATA_DIR/jellyfin-cache"
        "$DATA_DIR/books"
        "$DATA_DIR/comics"
        "$DATA_DIR/shelfmark"
        "$DATA_DIR/kavita"
        "$DATA_DIR/immich-uploads"
        "$DATA_DIR/mealie"
        "$DATA_DIR/budget"
    )
    local dir
    for dir in "${dirs[@]}"; do
        [ -d "$dir" ] && continue
        mkdir -p "$dir"
        chown "$REAL_UID:$REAL_GID" "$dir"
    done

    # Container-managed: postgres owns the contents as UID 999 — never chown.
    mkdir -p "$DATA_DIR/immich-postgres"

    ok "data directories ready."
}

configure_qbittorrent() {
    local qbit_conf_dir="${DATA_DIR}/qbittorrent/qBittorrent"
    local qbit_conf="${qbit_conf_dir}/qBittorrent.conf"

    info "configuring qbittorrent auth bypass..."
    mkdir -p "$qbit_conf_dir"
    chown -R "$REAL_UID:$REAL_GID" "$qbit_conf_dir"

    if [ ! -f "$qbit_conf" ]; then
        printf '[Preferences]\nWebUI\\LocalHostAuth=false\n' > "$qbit_conf"
        chown "$REAL_UID:$REAL_GID" "$qbit_conf"
    elif grep -q 'WebUI\\LocalHostAuth=' "$qbit_conf"; then
        sed -i 's|WebUI\\LocalHostAuth=.*|WebUI\\LocalHostAuth=false|' "$qbit_conf"
    else
        sed -i '/^\[Preferences\]/a WebUI\\LocalHostAuth=false' "$qbit_conf"
    fi
    ok "qbittorrent auth bypass configured."
}

create_docker_network() {
    docker network inspect proxy >/dev/null 2>&1 || docker network create proxy
    ok "proxy network ready."
}

install_update_cron() {
    # SUDO_USER is baked in so detect_real_user resolves the same user
    # cron runs as root with no sudo context.
    cat > /etc/cron.d/void-update << EOF
# managed by scripts/env.sh - nightly image pull + full stack restart
0 4 * * * root cd ${ROOT_DIR} && SUDO_USER=${REAL_USER} bash scripts/update.sh >> /var/log/void-update.log 2>&1
EOF
    chmod 644 /etc/cron.d/void-update
    ok "nightly update scheduled (04:00, log: /var/log/void-update.log)."
}


main() {
    require_root
    cd "$ROOT_DIR"

    # ===== identity =====
    detect_real_user

    # ===== env + secrets =====
    prepare_env
    generate_secrets
    setup_authelia
    load_env_exports

    # ===== configs =====
    generate_immich_config
    generate_ca_bundle

    # ===== filesystem =====
    create_data_directories
    configure_qbittorrent

    # ===== networking =====
    create_docker_network

    # ===== maintenance =====
    install_update_cron
}

main "$@"
