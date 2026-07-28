#!/bin/bash
# =============================================================================
# permissions.sh - hand the storage tree back to the container user.
#
# usage:
#   sudo bash scripts/permissions.sh   # or: just permissions
#
# Deleting a file needs write permission on the directory holding it, not on
# the file — so a library that reads and plays fine can still refuse every
# delete. That is the shape of the bug this repairs: Sonarr, Radarr, and
# Jellyfin all go quiet on delete while everything else keeps working.
#
# `just up` only chowns the top of the tree, because walking a whole library on
# every start is not free. This walks all of it. Run it after a migration, a
# restore from backup, or any time files arrive owned by someone else.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"
# shellcheck source=lib/runtime.sh
source "$SCRIPT_DIR/lib/runtime.sh"


# Config dirs for the PUID/PGID containers, and the media they read and write.
# Everything absent from this list is deliberately left alone — Postgres owns
# its data as 999, and Authelia, Caddy, and Pi-hole run as root.
owned_paths() {
    local name
    for name in qbittorrent prowlarr sonarr radarr jellyfin \
                shelfmark kavita mealie budget; do
        printf '%s\n' "${CONFIG_DIR}/${name}"
    done

    for name in downloads tv movies books comics photos; do
        printf '%s\n' "${MEDIA_DIR}/${name}"
    done

    printf '%s\n' "${CACHE_DIR}/jellyfin"
}

repair() {
    local target="$1"
    [ -d "$target" ] || return 0

    # -R for the contents, since it is a season folder deep down that has to be
    # writable. u+rwX only adds: files get read/write, directories additionally
    # get the traverse bit, and nothing already granted is taken away.
    chown -R "${uid}:${gid}" "$target"
    chmod -R u+rwX "$target"
    ok "$target"
}


main() {
    require_root
    cd "$ROOT_DIR"

    detect_real_user
    load_env_exports

    # .env is what compose hands the containers, so it wins. It is only unset
    # on a tree that has never seen `just up`.
    local uid="${PUID:-$REAL_UID}" gid="${PGID:-$REAL_GID}"

    info "handing the storage tree to ${uid}:${gid}..."
    warn "a large library makes this slow — it walks every file."

    local path
    while IFS= read -r path; do
        repair "$path"
    done < <(owned_paths)

    ok "permissions repaired. deletes from the app UIs should land now."
}

main "$@"
