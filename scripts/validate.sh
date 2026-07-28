#!/bin/bash
# =============================================================================
# validate.sh - sanity checks for the repo.
#   - shellcheck over every shell script (bash -n as a fallback)
#   - `docker compose config` against the top-level compose file
# Both tools are optional; whatever is installed gets used.
# =============================================================================

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

failures=0
mapfile -t SH_FILES < <(find scripts -type f -name '*.sh')


## ===== shell =====

if command -v shellcheck >/dev/null 2>&1; then
    info "running shellcheck..."
    for f in "${SH_FILES[@]}"; do
        shellcheck -x "$f" || failures=$((failures+1))
    done
    [ $failures -eq 0 ] && ok "shellcheck passed (${#SH_FILES[@]} files)"
else
    warn "shellcheck not installed — falling back to bash -n"
    for f in "${SH_FILES[@]}"; do
        bash -n "$f" || failures=$((failures+1))
    done
    [ $failures -eq 0 ] && ok "shell syntax OK (${#SH_FILES[@]} files)"
fi


## ===== compose =====

# A throwaway .env lets compose interpolate on a machine that has never run
# `just env`. The keys come from the compose files themselves — that catches
# the secrets env.sh generates, which never appear in .env.example, and no
# hand-kept list can go stale.
seed_validation_env() {
    warn ".env not found — using a temporary one built from .env.example"
    cp "$ENV_EXAMPLE" "$ENV_FILE"
    trap 'rm -f "$ENV_FILE"' EXIT

    local key
    for key in $(grep -rhoE '\$\{[A-Za-z_][A-Za-z0-9_]*' services --include='*.yml' \
                 | cut -c3- | sort -u); do
        env_has_value "$key" || env_set "$key" "validation"
    done

    # These two land in fields that must parse as an address and a GID.
    env_set HOST_IP    "127.0.0.1"
    env_set RENDER_GID "109"
}

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    info "validating 'docker compose config'..."
    if [ -f "$ENV_FILE" ]; then
        ok "using existing .env"
    else
        seed_validation_env
    fi

    if docker compose -f services/docker-compose.yml --env-file "$ENV_FILE" config -q; then
        ok "docker compose config valid"
    else
        warn "docker compose config failed"
        failures=$((failures+1))
    fi
else
    warn "docker compose not available — skipping compose validation"
fi


[ $failures -eq 0 ] || die "validation failed (${failures} issue(s))"
ok "validation passed"
