# void homelab - task runner.
# Run `just` (no args) to list targets. Most targets need sudo on the host.

set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

# Interpolation for the included files comes from their own `env_file:` entries,
# so this only has to cover the top-level compose file.
compose := "docker compose -f services/docker-compose.yml --env-file .env"

default:
    @just --list

## ===== setup =====
prepare:
    sudo bash scripts/prepare.sh
env:
    sudo bash scripts/env.sh
media:
    sudo bash scripts/media.sh
# repair: hand the storage tree back to the container user
permissions:
    sudo bash scripts/permissions.sh

## ===== lifecycle =====
up: env
    sudo {{compose}} up -d --remove-orphans
    sudo bash scripts/post-start.sh
down:
    sudo {{compose}} down --remove-orphans
restart: down up

# Nightly at 04:00 via /etc/cron.d/void-update, installed by scripts/env.sh.
# `up -d` recreates only containers whose image actually changed, so untouched
# services keep running and a no-op night stops nothing.
update:
    @echo "  [·] ===== update run: $(date -Is) ====="
    sudo {{compose}} pull --quiet
    sudo {{compose}} up -d --remove-orphans
    sudo docker image prune -f > /dev/null
    @echo "  [✓] images pulled; changed services recreated."

## ===== check =====
validate:
    bash scripts/validate.sh

## ===== inspect =====
ps:
    sudo {{compose}} ps
pull:
    sudo {{compose}} pull
logs service="":
    sudo {{compose}} logs -f --tail=200 {{service}}
