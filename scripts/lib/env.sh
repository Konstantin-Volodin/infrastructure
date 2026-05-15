#!/bin/bash
# .env helpers, sourced by service bootstrap scripts.
# expects log.sh helpers (info/ok/warn/die) to already be sourced.

ENV_FILE="${ENV_FILE:-.env}"
ENV_EXAMPLE="${ENV_EXAMPLE:-.env.example}"

# upsert a KEY=VALUE pair in ENV_FILE.
# replaces the existing line if present, otherwise appends.
env_set() {
    local key="$1" value="$2"
    if grep -q "^${key}=" "$ENV_FILE"; then
        local tmp
        tmp=$(mktemp)
        awk -v k="$key" -v v="$value" '
            BEGIN { replaced = 0 }
            { line = $0 }
            line ~ "^"k"=" && !replaced { print k"="v; replaced = 1; next }
            { print line }
        ' "$ENV_FILE" > "$tmp" && mv "$tmp" "$ENV_FILE"
    else
        printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
    fi
}

env_get() {
    local key="$1"
    grep "^${key}=" "$ENV_FILE" | head -n1 | cut -d= -f2- | tr -d '\r'
}

# returns 0 if the key exists with a non-empty value.
env_has_value() {
    local key="$1"
    grep -q "^${key}=.\+" "$ENV_FILE"
}

# generate a hex secret if the key is missing or empty.
gen_secret() {
    local key="$1"
    if env_has_value "$key"; then
        return 0
    fi
    env_set "$key" "$(openssl rand -hex 64 | tr -d '\n')"
    ok "generated ${key}"
}

# prompt the user for a value if the key is missing or empty.
# usage: prompt_credential KEY "prompt text" [secret=true|false]
prompt_credential() {
    local key="$1" prompt="$2" secret="${3:-false}"
    if env_has_value "$key"; then
        return 0
    fi
    local value
    if [ "$secret" = true ]; then
        read -rsp "  ${prompt}: " value; echo
    else
        read -rp "  ${prompt}: " value
    fi
    env_set "$key" "$value"
    ok "${key} set."
}

# create .env from .env.example, or append any new keys from the example.
sync_env_from_example() {
    if [ ! -f "$ENV_FILE" ]; then
        info "creating ${ENV_FILE} from ${ENV_EXAMPLE}..."
        cp "$ENV_EXAMPLE" "$ENV_FILE"
        ok "${ENV_FILE} created."
        return
    fi
    info "syncing new variables from ${ENV_EXAMPLE}..."
    local added=0
    while IFS= read -r line; do
        local key="${line%%=*}"
        [[ -z "$key" || "$key" == \#* || "$key" == "$line" ]] && continue
        if ! grep -q "^${key}=" "$ENV_FILE"; then
            echo "$line" >> "$ENV_FILE"
            added=$((added+1))
        fi
    done < "$ENV_EXAMPLE"
    ok "${ENV_FILE} synced (${added} new var(s))."
}

# resolve any ./relative path values to absolute, for the given keys.
resolve_env_paths() {
    info "resolving storage paths..."
    local key val
    for key in "$@"; do
        val=$(env_get "$key")
        if [[ "$val" == ./* ]]; then
            env_set "$key" "$(realpath -m "$val")"
        fi
    done
    ok "storage paths resolved."
}
