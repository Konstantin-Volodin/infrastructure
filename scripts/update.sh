#!/bin/bash
# Pull latest images, restart the stack, prune what's left behind.
# Runs nightly at 04:00 via /etc/cron.d/void-update (installed by env.sh).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"
# shellcheck source=lib/runtime.sh
source "$SCRIPT_DIR/lib/runtime.sh"

require_root
cd "$ROOT_DIR"

info "===== update run: $(date -Is) ====="

info "pulling latest images..."
( cd services && set -a && source ../.env && set +a && docker compose pull --quiet )
ok "images pulled."

bash "$SCRIPT_DIR/down.sh"
bash "$SCRIPT_DIR/up.sh"

info "pruning unused images..."
docker image prune -f > /dev/null
ok "unused images pruned."
