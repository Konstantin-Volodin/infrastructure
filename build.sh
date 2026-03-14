#!/bin/bash
# =============================================================================
# deploy.sh - provision void from scratch
#
# =============================================================================

set -euo pipefail

REMOTE="void"

info() { echo "  [·] $*"; }
ok()   { echo "  [✓] $*"; }

# ===== run setup (interactive for network) =====
ok "starting setup ..."
sudo bash ~/setup.sh
ok "setup done."

# ===== create .env file =====
cp .env.example .env
echo AUTHENTIK_DB_PASSWORD=$(openssl rand -hex 128 | tr -d '\n') >> .env
echo AUTHENTIK_SECRET_KEY=$(openssl rand -hex 128 | tr -d '\n') >> .env
echo DB_PASSWORD=$(openssl rand -hex 128 | tr -d '\n') >> .env
ok ".env file created."

# ===== start services =====
info "starting pihole ..."
sudo docker compose -f services/pihole/docker-compose.yml --env-file .env up -d
ok "pihole done."

info "starting immich ..."
sudo docker compose -f services/immich/docker-compose.yml --env-file .env up -d
ok "immich up."

info "starting mealie ..."
sudo docker compose -f services/mealie/docker-compose.yml --env-file .env up -d
ok "mealie up."

info "starting authentik ..."
sudo docker compose -f services/authentik/docker-compose.yml

# ===== reboot =====
read -p "Do you want to reboot void now? [y/N]: " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
	info "rebooting void ..."
	sudo reboot
else
	info "reboot skipped."
fi
