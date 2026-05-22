#!/bin/bash
# Runtime helpers shared by service bootstrap/start scripts.
# Expects log.sh helpers (info/ok/warn/die) to already be sourced.

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

# Normalize git-tracked file ownership so subsequent git operations work for the real user.
# safe.directory='*' bypasses git's dubious-ownership guard when the tree has mixed ownership.
chown_git_tracked_files() {
    git -c safe.directory='*' ls-files -z \
        | xargs -0 -r chown "$REAL_USER":"$REAL_USER"
    ok "git-tracked file ownership normalized to $REAL_USER."
}

load_env_exports() {
    [ -f .env ] || die "missing .env; run scripts/env.sh first"
    set -a
    # shellcheck source=../../.env
    source .env
    set +a
}
