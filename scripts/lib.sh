#!/bin/bash
# =============================================================================
# Shared helpers, sourced by every script in this directory:
#
#     source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
#
# Sourcing this also cds to the repo root — every script wants to run from
# there, so it happens once here rather than in each of them.
# =============================================================================

## ===== logging =====

info() { echo "  [·] $*"; }
ok()   { echo "  [✓] $*"; }
warn() { echo "  [!] $*"; }
die()  { echo "  [✗] $*" >&2; exit 1; }


## ===== location =====

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
ENV_EXAMPLE="$ROOT_DIR/.env.example"
cd "$ROOT_DIR"


## ===== .env accessors =====

env_get() { grep "^$1=" "$ENV_FILE" | head -n1 | cut -d= -f2- | tr -d '\r'; }

env_has_value() { grep -q "^$1=.\+" "$ENV_FILE"; }

env_set() {
    local key="$1" value="$2"
    if grep -q "^${key}=" "$ENV_FILE"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
    else
        printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
    fi
}

# Rewrite ./relative storage paths as absolute. Compose resolves relative bind
# mounts against the compose file's directory, not the repo root — absolute
# paths remove the ambiguity.
resolve_env_paths() {
    info "resolving storage paths..."
    local key val
    for key in "$@"; do
        val=$(env_get "$key")
        [[ "$val" == ./* ]] && env_set "$key" "$(realpath -m "$val")"
    done
    ok "storage paths resolved."
}


## ===== runtime =====

require_root() {
    [[ $EUID -eq 0 ]] || die "run as root: sudo bash $0"
}

detect_real_user() {
    REAL_USER="${SUDO_USER:-$USER}"
    [[ -z "$REAL_USER" || "$REAL_USER" == "root" ]] && \
        die "could not resolve a non-root real user — run 'just up' (not 'sudo just up'); recipes invoke sudo themselves"
    REAL_UID=$(id -u "$REAL_USER")
    REAL_GID=$(id -g "$REAL_USER")
}

load_env_exports() {
    [ -f "$ENV_FILE" ] || die "missing .env; run 'just env' first"
    set -a
    # shellcheck source=../.env
    source "$ENV_FILE"
    set +a
}
