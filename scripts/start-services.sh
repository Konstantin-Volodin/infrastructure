#!/bin/bash
# Bring the stack up and run post-start service configuration.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"
# shellcheck source=lib/runtime.sh
source "$SCRIPT_DIR/lib/runtime.sh"

require_root
cd "$ROOT_DIR"
detect_real_user
load_env_exports

info "starting all services..."
( cd services && set -a && source ../.env && set +a && docker compose up -d --remove-orphans )
ok "all services up."

if command -v tailscale >/dev/null 2>&1; then
    info "waiting for pihole to be ready..."
    until docker exec pihole pihole status 2>/dev/null | grep -q "blocking is enabled"; do
        sleep 2
    done
    ok "pihole is ready."

    info "configuring pihole wildcard DNS for *.${DOMAIN}..."
    TAILSCALE_IP=$(tailscale ip -4)
    docker exec pihole pihole-FTL --config misc.dnsmasq_lines "[\"address=/.${DOMAIN}/${TAILSCALE_IP}\"]"
    ok "pihole DNS configured."
else
    warn "tailscale not installed — skipping pihole wildcard DNS configuration."
    warn "install tailscale and re-run 'just up' (or set dnsmasq_lines manually) when ready."
fi

info "configuring media stack mesh..."
bash "$SCRIPT_DIR/configure-media.sh" \
    || warn "media mesh configuration incomplete — see log above; re-run 'just media'."

# Only fix git-tracked files so pull works; leave secrets/data root-owned.
chown_git_tracked_files
