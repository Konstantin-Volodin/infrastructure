#!/bin/bash
# .env accessors; sourced by env.sh, migrate.sh, and validate.sh.

ENV_FILE="${ENV_FILE:-.env}"

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
# paths remove the ambiguity. Expects log.sh helpers to be sourced.
resolve_env_paths() {
    info "resolving storage paths..."
    local key val
    for key in "$@"; do
        val=$(env_get "$key")
        [[ "$val" == ./* ]] && env_set "$key" "$(realpath -m "$val")"
    done
    ok "storage paths resolved."
}
