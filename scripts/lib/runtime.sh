#!/bin/bash
# Runtime helpers shared by service bootstrap/start scripts.
# Expects log.sh helpers (info/ok/warn/die) to already be sourced.

require_root() {
    [[ $EUID -eq 0 ]] || die "run as root: sudo bash $0"
}

detect_real_user() {
    REAL_USER="${SUDO_USER:-$USER}"
    REAL_UID=$(id -u "$REAL_USER")
    REAL_GID=$(id -g "$REAL_USER")
}

load_env_exports() {
    [ -f .env ] || die "missing .env; run scripts/bootstrap-services.sh first"
    set -a
    # shellcheck source=../../.env
    source .env
    set +a
}
