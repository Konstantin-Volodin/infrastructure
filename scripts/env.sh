#!/bin/bash
# Syncs .env, generates secrets, bootstraps authelia, prepares the host.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

AUTHELIA_CONFIG="services/authelia/configuration.yml"
AUTHELIA_USERS_TMPL="services/authelia/users_database.yml.tmpl"


## ===== env helpers =====

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


## ===== steps =====

prepare_env() {
    info "preparing environment..."
    sync_env_from_example

    HOST_IP=$(hostname -I | awk '{print $1}')
    env_set HOST_IP "$HOST_IP"
    ok "detected host IP: ${HOST_IP}"

    # The compose files read these; create_storage_tree chowns to them. One
    # source of truth, so "runs as" and "owns the files" cannot drift apart.
    env_set PUID "$REAL_UID"
    env_set PGID "$REAL_GID"
    ok "containers will run as ${REAL_USER} (${REAL_UID}:${REAL_GID})"

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

seed_users_database() {
    [ -f "$AUTHELIA_USERS_DB" ] && return
    cp "$AUTHELIA_USERS_TMPL" "$AUTHELIA_USERS_DB"
    ok "users database seeded from template."
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

    warn "authelia admin — record this now, the plaintext is not stored:"
    warn "  vox / ${password}"
}

ensure_oidc_keys() {
    local container="$1"
    [ -f "$AUTHELIA_OIDC_KEY" ] && {
        ok "authelia OIDC keys already exist."
        return
    }

    docker exec "$container" authelia crypto pair rsa generate --directory /data/secrets > /dev/null
    mv "${AUTHELIA_STATE}/secrets/private.pem" "$AUTHELIA_OIDC_KEY"
    mv "${AUTHELIA_STATE}/secrets/public.pem"  "${AUTHELIA_STATE}/secrets/oidc.jwks.pub"
    ok "authelia OIDC keys generated."
}

setup_authelia() {
    # State paths depend on CONFIG_DIR, so they resolve here rather than at load.
    AUTHELIA_STATE="${CONFIG_DIR}/authelia"
    AUTHELIA_USERS_DB="${AUTHELIA_STATE}/users_database.yml"
    AUTHELIA_OIDC_KEY="${AUTHELIA_STATE}/secrets/oidc.jwks.key"

    [ -f "$AUTHELIA_USERS_TMPL" ] || die "missing $AUTHELIA_USERS_TMPL"
    seed_users_database

    if grep -Eq '^    password:[[:space:]]*[^[:space:]]+' "$AUTHELIA_USERS_DB" && [ -f "$AUTHELIA_OIDC_KEY" ]; then
        ok "authelia already bootstrapped."
        return
    fi

    info "bootstrapping authelia..."

    local container="temp-authelia-$$"
    docker run -d --rm \
        -v "${PWD}/${AUTHELIA_CONFIG}:/config/configuration.yml:ro" \
        -v "${AUTHELIA_STATE}:/data" \
        --name "$container" \
        authelia/authelia:latest sleep infinity > /dev/null
    trap "docker stop $container >/dev/null 2>&1 || true" EXIT

    ensure_admin_password "$container"
    ensure_oidc_keys     "$container"
}

generate_immich_config() {
    info "generating immich config..."
    envsubst < services/immich/immich.json.tmpl > "${CONFIG_DIR}/immich/immich.json"
    ok "immich config generated."
}

# Homepage needs a writable config dir, so the YAML is copied in, not mounted.
seed_homepage_config() {
    info "seeding homepage config..."
    local src dest
    while IFS= read -r -d '' src; do
        dest="${CONFIG_DIR}/homepage/${src#services/homepage/config/}"
        install -D -m 644 "$src" "$dest"
    done < <(git -c safe.directory='*' ls-files -z services/homepage/config)
    ok "homepage config seeded."
}

generate_ca_bundle() {
    local ca_dir="${CONFIG_DIR}/ca"
    if [ -f "${ca_dir}/combined-ca.crt" ]; then
        ok "combined CA bundle already exists."
        return
    fi

    info "generating internal CA cert..."
    openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
        -keyout "${ca_dir}/internal-ca.key" \
        -out    "${ca_dir}/internal-ca.crt" \
        -subj "/CN=Void Internal CA"
    cat /etc/ssl/certs/ca-certificates.crt "${ca_dir}/internal-ca.crt" \
        > "${ca_dir}/combined-ca.crt"
    ok "combined CA bundle created."
}

create_storage_tree() {
    info "ensuring storage tree exists with correct ownership..."

    # Handed to the real user — these are the dirs the PUID/PGID containers
    # write into.
    local user_dirs=(
        "$CONFIG_DIR/qbittorrent"
        "$CONFIG_DIR/qbit-manage"
        "$CONFIG_DIR/prowlarr"
        "$CONFIG_DIR/sonarr"
        "$CONFIG_DIR/radarr"
        "$CONFIG_DIR/jellyfin"
        "$CONFIG_DIR/shelfmark"
        "$CONFIG_DIR/kavita"
        "$CONFIG_DIR/mealie"
        "$CONFIG_DIR/budget"

        "$MEDIA_DIR/downloads"
        "$MEDIA_DIR/tv"
        "$MEDIA_DIR/movies"
        "$MEDIA_DIR/books"
        "$MEDIA_DIR/comics"
        "$MEDIA_DIR/photos"

        "$CACHE_DIR/jellyfin"
    )

    # Left root-owned — these run as root or their own baked-in UID (postgres
    # is 999); chowning them breaks startup.
    local root_dirs=(
        "$CONFIG_DIR/authelia/secrets"
        "$CONFIG_DIR/authelia/log"
        "$CONFIG_DIR/authelia-redis"
        "$CONFIG_DIR/caddy/data"
        "$CONFIG_DIR/caddy/config"
        "$CONFIG_DIR/ca"
        "$CONFIG_DIR/pihole"
        "$CONFIG_DIR/homepage"
        "$CONFIG_DIR/immich"
        "$CONFIG_DIR/immich-postgres"

        "$CACHE_DIR/immich-model-cache"
    )

    # Chown every run — a dir that arrived some other way keeps its old owner
    # and leaves the tree unwritable. Top level only; `just permissions` walks
    # the whole library.
    local dir
    for dir in "${user_dirs[@]}"; do
        mkdir -p "$dir"
        chown "$REAL_UID:$REAL_GID" "$dir"
    done
    mkdir -p "${root_dirs[@]}"

    ok "storage tree ready."
}

configure_qbittorrent() {
    local qbit_conf_dir="${CONFIG_DIR}/qbittorrent/qBittorrent"
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
    # Absolute path — cron's PATH is minimal.
    cat > /etc/cron.d/void-update << EOF
# managed by scripts/env.sh - nightly image pull + reconcile
0 4 * * * root cd ${ROOT_DIR} && /usr/bin/just update >> /var/log/void-update.log 2>&1
EOF
    chmod 644 /etc/cron.d/void-update
    ok "nightly update scheduled (04:00, log: /var/log/void-update.log)."
}

# The qbit-manage container schedules its own reaping now.
remove_reap_cron() {
    [ -e /etc/cron.d/void-reap ] || return 0
    rm -f /etc/cron.d/void-reap
    ok "removed the old host reap cron — qbit-manage schedules itself."
}


main() {
    require_root
    detect_real_user

    prepare_env
    generate_secrets
    load_env_exports

    # everything below writes into the storage roots
    create_storage_tree
    setup_authelia
    generate_immich_config
    seed_homepage_config
    generate_ca_bundle
    configure_qbittorrent

    create_docker_network
    install_update_cron
    remove_reap_cron
}

main "$@"
