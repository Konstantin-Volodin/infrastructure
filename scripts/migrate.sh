#!/bin/bash
# =============================================================================
# migrate.sh - move an existing install off the old layout.
#
#   before: everything under a single DATA_DIR, plus runtime state scattered
#           through services/ in the working tree
#   after:  CONFIG_DIR / MEDIA_DIR / CACHE_DIR, repo holds no state at all
#
# usage:
#   just down                     # nothing may be running
#   sudo bash scripts/migrate.sh  # or: just migrate
#   just up
#
# Run this before the first `just up` on the new layout — `up` would otherwise
# bootstrap a fresh Authelia and leave your existing password and OIDC keys
# stranded in the old location.
#
# Safe to re-run. Every move is skipped when the source is gone or the
# destination already holds something, so nothing is ever overwritten.
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

ENV_EXAMPLE=".env.example"

moved=0
skipped=0


## ===== helpers =====

# Move src onto dest, never over an existing destination.
relocate() {
    local src="$1" dest="$2"

    [ -e "$src" ] || { skipped=$((skipped+1)); return; }

    if [ -e "$dest" ] && [ -n "$(ls -A "$dest" 2>/dev/null)" ]; then
        warn "skip: ${dest} already has contents"
        skipped=$((skipped+1))
        return
    fi

    mkdir -p "$(dirname "$dest")"
    rmdir "$dest" 2>/dev/null || true   # drop the empty placeholder, if any
    mv "$src" "$dest"
    ok "${src} → ${dest}"
    moved=$((moved+1))
}

ensure_stopped() {
    local running
    # || running=0 keeps pipefail from killing the script when compose can't
    # read the project at all — that just means nothing is up.
    running=$(docker compose -f services/docker-compose.yml --env-file "$ENV_FILE" ps -q 2>/dev/null | wc -l) \
        || running=0
    [ "$running" -eq 0 ] || die "stack is still running — run 'just down' first"
}

# The three roots have to be known before env.sh has ever run, so read them
# straight from .env, falling back to the shipped defaults.
resolve_roots() {
    [ -f "$ENV_FILE" ] || cp "$ENV_EXAMPLE" "$ENV_FILE"

    local key
    for key in CONFIG_DIR MEDIA_DIR CACHE_DIR; do
        env_has_value "$key" || env_set "$key" "$(sed -n "s|^${key}=||p" "$ENV_EXAMPLE")"
    done
    resolve_env_paths CONFIG_DIR MEDIA_DIR CACHE_DIR

    set -a
    # shellcheck source=../.env
    source "$ENV_FILE"
    set +a
}


## ===== moves =====

migrate_data_dir() {
    local old="${DATA_DIR:-}"

    [ -n "$old" ] || { info "no DATA_DIR in .env — skipping old data root."; return; }
    [ -d "$old" ] || { info "DATA_DIR ${old} does not exist — skipping."; return; }

    info "moving ${old} into the storage roots..."

    local name
    for name in qbittorrent prowlarr sonarr radarr jellyfin \
                shelfmark kavita mealie budget immich-postgres; do
        relocate "${old}/${name}" "${CONFIG_DIR}/${name}"
    done

    for name in downloads tv movies books comics; do
        relocate "${old}/${name}" "${MEDIA_DIR}/${name}"
    done
    relocate "${old}/immich-uploads" "${MEDIA_DIR}/photos"

    relocate "${old}/jellyfin-cache" "${CACHE_DIR}/jellyfin"

    if rmdir "$old" 2>/dev/null; then
        ok "old data root removed."
    else
        warn "${old} is not empty — leftovers are yours to sort out."
    fi
}

migrate_repo_state() {
    info "moving runtime state out of the working tree..."

    # Authelia: the password hash and OIDC keys are irreplaceable — losing them
    # means a new admin password and every OIDC client re-consenting.
    relocate services/authelia/config/users_database.yml "${CONFIG_DIR}/authelia/users_database.yml"
    relocate services/authelia/config/db.sqlite3         "${CONFIG_DIR}/authelia/db.sqlite3"
    relocate services/authelia/secrets                   "${CONFIG_DIR}/authelia/secrets"
    relocate services/authelia/logs                      "${CONFIG_DIR}/authelia/log"

    # Caddy: keeping data/ preserves issued certs, pki/ the CA they chain to.
    relocate services/caddy/data           "${CONFIG_DIR}/caddy/data"
    relocate services/caddy/config         "${CONFIG_DIR}/caddy/config"
    relocate services/caddy/pki/internal-ca.crt "${CONFIG_DIR}/ca/internal-ca.crt"
    relocate services/caddy/pki/internal-ca.key "${CONFIG_DIR}/ca/internal-ca.key"
    relocate services/caddy/combined-ca.crt     "${CONFIG_DIR}/ca/combined-ca.crt"

    relocate services/pihole/etc-pihole     "${CONFIG_DIR}/pihole"
    relocate services/immich/data/model-cache "${CACHE_DIR}/immich-model-cache"

    # Homepage's own scaffolds. The tracked YAML is re-seeded by env.sh.
    local name
    for name in logs custom.js kubernetes.yaml proxmox.yaml; do
        relocate "services/homepage/config/${name}" "${CONFIG_DIR}/homepage/${name}"
    done

    # Rendered from a template on every run — no reason to keep the old copy.
    rm -f services/immich/config/immich.json
    rmdir services/authelia/config services/immich/config services/immich/data \
          services/caddy/pki 2>/dev/null || true
}

# users_database.yml carries the admin password hash, and it used to be a
# tracked file that env.sh edited in place — so `git pull` will have balked at
# it, and a careless `git checkout` throws the hash away. If Authelia state
# arrived without it, say so: the next `just up` would quietly mint a new
# admin password and new OIDC keys.
check_authelia_identity() {
    [ -f "${CONFIG_DIR}/authelia/users_database.yml" ] && return 0
    [ -e "${CONFIG_DIR}/authelia/db.sqlite3" ]         || return 0

    warn "Authelia state moved over, but users_database.yml did not."
    warn "the next 'just up' will mint a NEW admin password and OIDC keys."
    warn "still have the old file? drop it in ${CONFIG_DIR}/authelia/ and re-run."
}

drop_stale_vars() {
    env_has_value DATA_DIR || return 0
    sed -i '/^DATA_DIR=/d' "$ENV_FILE"
    ok "DATA_DIR removed from .env — the three roots replace it."
}


main() {
    require_root
    cd "$ROOT_DIR"

    resolve_roots
    ensure_stopped

    info "config → ${CONFIG_DIR}"
    info "media  → ${MEDIA_DIR}"
    info "cache  → ${CACHE_DIR}"
    warn "a root on a different filesystem turns these moves into full copies."

    migrate_data_dir
    migrate_repo_state
    check_authelia_identity
    drop_stale_vars

    ok "migration done — ${moved} moved, ${skipped} skipped. Run 'just up'."
}

main "$@"
