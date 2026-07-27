# void homelab - task runner.
# Run `just` (no args) to list targets. Most targets need sudo on the host.

set shell := ["bash", "-eu", "-o", "pipefail", "-c"]
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

## ===== lifecycle =====
up: env
    sudo bash scripts/up.sh
down:
    sudo bash scripts/down.sh
restart: down up
update:
    sudo bash scripts/update.sh

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
