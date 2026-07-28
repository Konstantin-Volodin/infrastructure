#!/bin/bash
# Post-start host configuration: Pi-hole wildcard DNS, then the media mesh.
# Runs after `just up` has brought the stack online.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_root
load_env_exports

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

bash scripts/media.sh \
    || warn "media mesh configuration incomplete — see log above; re-run 'just media'."
