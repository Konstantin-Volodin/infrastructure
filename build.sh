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
if [ ! -f ~/.env ]; then
	cp ~/infrastructure/.env.example ~/.env

	# Insert generated secrets into the correct lines
	sed -i "s/^AUTHENTIK_DB_PASSWORD=.*/AUTHENTIK_DB_PASSWORD=$(openssl rand -base64 32 | tr -d '\n')/" ~/.env
	sed -i "s/^AUTHENTIK_SECRET_KEY=.*/AUTHENTIK_SECRET_KEY=$(openssl rand -base64 32 | tr -d '\n')/" ~/.env
	sed -i "s/^IMMICH_DB_PASSWORD=.*/IMMICH_DB_PASSWORD=$(openssl rand -base64 32 | tr -d '\n')/" ~/.env

# ===== start services =====
info "starting pihole ..."
cd ~/pihole && docker compose up -d
ok "pihole done."

info "starting immich ..."
cd ~/immich && docker compose up -d
ok "immich up."

info "starting mealie ..."
cd ~/mealie && docker compose up -d
ok "mealie up."

# ===== reboot =====
read -p "Do you want to reboot void now? [y/N]: " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
	info "rebooting void ..."
	sudo reboot
else
	info "reboot skipped."
fi