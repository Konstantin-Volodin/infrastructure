#!/bin/bash
# =============================================================================
# validate.sh - sanity checks for the repo.
#   - bash syntax check on all shell scripts
#   - shellcheck (if available)
#   - `docker compose config` against the top-level compose file (if available)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"
ENV_FILE="$ROOT_DIR/.env"
ENV_EXAMPLE="$ROOT_DIR/.env.example"
# shellcheck source=lib/env.sh
source "$SCRIPT_DIR/lib/env.sh"

cd "$ROOT_DIR"

failures=0
VALIDATION_ENV_CREATED=0

cleanup_validation_env() {
    if [ "$VALIDATION_ENV_CREATED" = 1 ]; then
        rm -f "$ROOT_DIR/.env"
    fi
}
trap cleanup_validation_env EXIT

# collect all .sh files: scripts/ tree + root-level wrappers
mapfile -t SH_FILES < <(find scripts -type f -name '*.sh'; find . -maxdepth 1 -type f -name '*.sh')

info "checking shell script syntax (bash -n)..."
for f in "${SH_FILES[@]}"; do
    if ! bash -n "$f"; then
        warn "syntax error in $f"
        failures=$((failures+1))
    fi
done
[ $failures -eq 0 ] && ok "shell syntax OK (${#SH_FILES[@]} files)"

if command -v shellcheck >/dev/null 2>&1; then
    info "running shellcheck..."
    sc_failures=0
    for f in "${SH_FILES[@]}"; do
        if ! shellcheck -x "$f"; then
            sc_failures=$((sc_failures+1))
        fi
    done
    if [ $sc_failures -gt 0 ]; then
        warn "shellcheck reported issues in ${sc_failures} file(s)"
        failures=$((failures+sc_failures))
    else
        ok "shellcheck passed"
    fi
else
    warn "shellcheck not installed - skipping"
fi

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    info "validating 'docker compose config'..."
    if [ -f .env ]; then
        ok "using existing .env for compose validation"
    else
        warn ".env not found - creating temporary validation .env from .env.example"
        cp .env.example .env
        VALIDATION_ENV_CREATED=1
        env_set HOST_IP "127.0.0.1"
        env_set PROTONVPN_OPENVPN_USER "validation"
        env_set PROTONVPN_OPENVPN_PASSWORD "validation"
        env_set DB_PASSWORD "validation"
        env_set AUTHELIA_JWT_PASSWORD "validation"
        env_set AUTHELIA_SESSION_SECRET "validation"
        env_set AUTHELIA_STORAGE_ENCRYPTION_KEY "validation"
        env_set AUTHELIA_OIDC_HMAC_SECRET "validation"
        env_set IMMICH_OIDC_SECRET "validation"
        env_set MEALIE_OIDC_SECRET "validation"
    fi
    if ! docker compose -f services/docker-compose.yml --env-file "$ROOT_DIR/.env" config -q; then
        warn "docker compose config failed"
        failures=$((failures+1))
    else
        ok "docker compose config valid"
    fi
else
    warn "docker compose not available - skipping compose validation"
fi

if [ $failures -gt 0 ]; then
    die "validation failed (${failures} issue(s))"
fi
ok "validation passed"
