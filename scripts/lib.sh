#!/bin/bash
# Shared helpers. Sourcing this also cds to the repo root.

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

env_has_value() { grep -q "^$1=.\+" "$ENV_FILE"; }

env_set() {
    local key="$1" value="$2"
    if grep -q "^${key}=" "$ENV_FILE"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
    else
        printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
    fi
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
