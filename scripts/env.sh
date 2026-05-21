#!/bin/bash
# =============================================================================
# env.sh
#   - syncs .env from .env.example and resolves DATA_DIR
#   - generates secrets and prompts for missing credentials
#   - bootstraps Authelia (admin password hash + OIDC keys)
#   - generates service configs and the internal CA bundle
#   - prepares data directories with the right ownership
#   - configures qBittorrent auth bypass
#   - creates shared Docker networks
#
# usage:
#   sudo bash scripts/env.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"
# shellcheck source=lib/env.sh
source "$SCRIPT_DIR/lib/env.sh"
# shellcheck source=lib/runtime.sh
source "$SCRIPT_DIR/lib/runtime.sh"

AUTHELIA_BOOTSTRAPPED=0
AUTHELIA_INITIAL_ADMIN_PASSWORD=""
AUTHELIA_USERS_DB="services/authelia/config/users_database.yml"
AUTHELIA_OIDC_KEY="services/authelia/secrets/oidc.jwks.key"

prepare_env() {
    info "preparing environment..."
    sync_env_from_example

    if ! env_has_value DATA_DIR; then
        env_set DATA_DIR "./data"
    fi
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

    info "checking user credentials..."
    prompt_credential PROTONVPN_OPENVPN_USER \
        "ProtonVPN OpenVPN username (from account.protonvpn.com/account#openvpn)"
    prompt_credential PROTONVPN_OPENVPN_PASSWORD \
        "ProtonVPN OpenVPN password" true
}

setup_authelia() {
    local needs_admin_password=0
    local needs_oidc_keys=0
    local authelia_container
    local admin_hash

    info "checking authelia bootstrap state..."
    [ -f "$AUTHELIA_USERS_DB" ] || die "missing $AUTHELIA_USERS_DB"

    if ! grep -Eq '^    password:[[:space:]]*[^[:space:]]+' "$AUTHELIA_USERS_DB"; then
        needs_admin_password=1
    fi
    [ ! -f "$AUTHELIA_OIDC_KEY" ] && needs_oidc_keys=1

    if [ "$needs_admin_password" = 0 ] && [ "$needs_oidc_keys" = 0 ]; then
        ok "authelia admin password and OIDC keys already exist, skipping bootstrap."
        return 0
    fi

    info "bootstrapping authelia..."
    mkdir -p services/authelia/secrets

    authelia_container="temp-authelia-$$"
    docker run -d --rm \
        -v "${PWD}/services/authelia/config/configuration.yml:/config/configuration.yml" \
        -v "${PWD}/services/authelia/secrets:/config/secrets" \
        --name "$authelia_container" \
        authelia/authelia:latest sleep infinity > /dev/null

    cleanup_authelia_container() {
        docker stop "$authelia_container" > /dev/null 2>&1 || true
    }
    trap cleanup_authelia_container EXIT

    if [ "$needs_admin_password" = 1 ]; then
        # The plaintext is held in this shell only; it never lands on disk.
        AUTHELIA_INITIAL_ADMIN_PASSWORD=$(openssl rand -hex 24)
        admin_hash=$(docker exec "$authelia_container" authelia crypto hash generate \
            --config "/config/configuration.yml" \
            --password "$AUTHELIA_INITIAL_ADMIN_PASSWORD" \
            | awk -F'Digest: ' '/Digest: / { print $2; exit }')
        [ -n "$admin_hash" ] || die "failed to generate authelia admin password hash"
        sed -i "s|^    password:.*|    password: '${admin_hash}'|" "$AUTHELIA_USERS_DB"
        ok "admin password hash written."
        AUTHELIA_BOOTSTRAPPED=1
    else
        ok "authelia admin password hash already exists."
    fi

    if [ "$needs_oidc_keys" = 1 ]; then
        docker exec "$authelia_container" authelia crypto pair rsa generate \
            --directory /config/secrets > /dev/null
        mv services/authelia/secrets/private.pem services/authelia/secrets/oidc.jwks.key
        mv services/authelia/secrets/public.pem services/authelia/secrets/oidc.jwks.pub
        ok "authelia OIDC keys generated."
    else
        ok "authelia OIDC keys already exist."
    fi

    cleanup_authelia_container
    trap - EXIT
}

generate_service_configs() {
    info "generating immich config..."
    envsubst < services/immich/config/immich.json.tmpl > services/immich/config/immich.json
    ok "immich config generated."
}

generate_ca_bundles() {
    if [ -f services/caddy/combined-ca.crt ]; then
        ok "combined CA bundle already exists."
        return 0
    fi

    info "generating internal CA cert..."
    mkdir -p services/caddy/pki
    openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
        -keyout services/caddy/pki/internal-ca.key \
        -out services/caddy/pki/internal-ca.crt \
        -subj "/CN=Void Internal CA"
    cat /etc/ssl/certs/ca-certificates.crt services/caddy/pki/internal-ca.crt \
        > services/caddy/combined-ca.crt
    ok "combined CA bundle created."
}

create_data_directories() {
    local dirs
    local dir

    info "ensuring data directories exist with correct ownership..."
    # Dirs whose contents are managed by the host user (vox).
    dirs=(
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
        "$DATA_DIR/cwa-books-ingest"
        "$DATA_DIR/shelfmark"
        "$DATA_DIR/calibre-web"
        "$DATA_DIR/immich-uploads"
        "$DATA_DIR/mealie"
    )

    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            chown "$REAL_UID:$REAL_GID" "$dir"
        fi
    done

    # Container-managed dirs: create only, never chown — the container's own
    # user (e.g. postgres UID 999) owns the contents.
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
        sed -i 's/WebUI\\LocalHostAuth=.*/WebUI\\LocalHostAuth=false/' "$qbit_conf"
    else
        sed -i '/^\[Preferences\]/a WebUI\\LocalHostAuth=false' "$qbit_conf"
    fi
    ok "qbittorrent auth bypass configured."
}

create_docker_network() {
    docker network inspect proxy >/dev/null 2>&1 || docker network create proxy
    ok "proxy network ready."
}

print_authelia_banner() {
    [ "$AUTHELIA_BOOTSTRAPPED" = 1 ] || return 0
    echo
    echo "  =============================================================="
    echo "    Authelia initial admin password (record this NOW —"
    echo "    plaintext is not stored on disk):"
    echo
    echo "      user:     vox"
    echo "      password: $AUTHELIA_INITIAL_ADMIN_PASSWORD"
    echo
    echo "    Hash applied in:"
    echo "      services/authelia/config/users_database.yml"
    echo "    Change the password from the Authelia UI after first login."
    echo "  =============================================================="
    echo
}

main() {
    require_root
    cd "$ROOT_DIR"

    detect_real_user
    prepare_env
    generate_secrets
    setup_authelia

    load_env_exports
    generate_service_configs
    generate_ca_bundles
    create_data_directories
    configure_qbittorrent
    create_docker_network
    print_authelia_banner
}

main "$@"
