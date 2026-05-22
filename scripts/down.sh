#!/bin/bash
# Tear the stack down and normalize git-tracked file ownership.

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

info "stopping all services..."
( cd services && set -a && source ../.env && set +a && docker compose down --remove-orphans )
ok "all services stopped."

chown_git_tracked_files
