#!/bin/bash
# Hand the storage tree back to the container user. Deletes need write
# permission on the directory, not the file — that's the bug this repairs.
# `just up` only chowns the top of the tree; this walks all of it.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"


# Anything absent here is deliberate — postgres owns its data as 999, and
# authelia, caddy and pi-hole run as root.
owned_paths() {
    local name
    for name in qbittorrent qbit-manage prowlarr sonarr radarr jellyfin \
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

    # u+rwX only adds, and gives directories the traverse bit files don't need.
    chown -R "${uid}:${gid}" "$target"
    chmod -R u+rwX "$target"
    ok "$target"
}


main() {
    require_root
    detect_real_user
    load_env_exports

    # .env is what compose hands the containers, so it wins.
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
