#!/bin/bash
# Tear the stack down. State lives outside the repo, so nothing else to clean up.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"
# shellcheck source=lib/runtime.sh
source "$SCRIPT_DIR/lib/runtime.sh"

require_root
cd "$ROOT_DIR"
load_env_exports

info "stopping all services..."
( cd services && set -a && source ../.env && set +a && docker compose down --remove-orphans )
ok "all services stopped."
