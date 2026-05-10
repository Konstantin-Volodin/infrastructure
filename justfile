# void homelab - task runner.
# Run `just` (no args) to list targets. Most targets need sudo on the host.

set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

compose := "docker compose -f services/docker-compose.yml --env-file .env"

# Show available targets.
default:
    @just --list

# Provision the host (system updates, SSH, firewall, Docker, etc.).
prepare:
    sudo bash scripts/prepare-linux.sh

# Bootstrap env, secrets, Authelia, configs, CA bundles, data dirs, and networks.
env:
    sudo bash scripts/bootstrap-services.sh

# Bring the stack up and configure service-level post-start bits.
up: env
    sudo bash scripts/start-services.sh

# Bash syntax + shellcheck (if present) + `docker compose config`.
validate:
    bash scripts/validate.sh

# Stop the stack and remove orphans.
down:
    sudo {{compose}} down --remove-orphans

# Restart everything, or one service: `just restart caddy`.
restart service="":
    sudo {{compose}} restart {{service}}

# Show running services.
ps:
    sudo {{compose}} ps

# Pull latest images.
pull:
    sudo {{compose}} pull

# Tail logs for the whole stack, or one service: `just logs caddy`.
logs service="":
    sudo {{compose}} logs -f --tail=200 {{service}}
