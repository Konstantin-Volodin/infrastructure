#!/bin/bash
#
# Wires up the media stack mesh.
#
# - qBittorrent: books / tv / movies categories
# - Sonarr/Radarr: download client + root folder
# - Prowlarr: full sync to Sonarr & Radarr
#
# Idempotent. Re-running converges to the same state.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CURL_IMAGE="curlimages/curl:8.11.1"


gcurl() { docker run --rm --network "container:gluetun" "$CURL_IMAGE" -fsS --max-time 20 "$@"; }

wait_http() {
    for _ in {1..60}; do
        gcurl -o /dev/null "$1" 2>/dev/null && { ok "$2 ready."; return; } || sleep 2
    done
    warn "$2 unreachable after 120s."; return 1
}

api_key() {
    local f="${CONFIG_DIR}/$1/config.xml"
    for _ in {1..30}; do
        [ -f "$f" ] && grep -q '<ApiKey>' "$f" && { sed -n 's:.*<ApiKey>\(.*\)</ApiKey>.*:\1:p' "$f"; return; } || sleep 2
    done
    return 1
}


configure_qbittorrent() {
    wait_http "http://localhost:8080/api/v2/app/version" "qBittorrent" || return 0

    local base="http://localhost:8080/api/v2/torrents"
    set_category() {
        local args=(--data-urlencode "category=$1" --data-urlencode "savePath=$2")
        if   gcurl -X POST "${base}/createCategory" "${args[@]}" >/dev/null 2>&1 \
          || gcurl -X POST "${base}/editCategory"   "${args[@]}" >/dev/null 2>&1
        then ok   "qBittorrent: '$1' → $2"
        else warn "qBittorrent: '$1' → $2 failed."
        fi
    }

    set_category books  /data/books
    set_category tv     /data/downloads/tv
    set_category movies /data/downloads/movies
}

DC_BODY_TEMPLATE='{
  "enable": true, "protocol": "torrent", "priority": 1,
  "name": "qBittorrent", "implementation": "QBittorrent",
  "configContract": "QBittorrentSettings",
  "fields": [
    {"name": "host",     "value": "localhost"},
    {"name": "port",     "value": 8080},
    {"name": "category", "value": "__CAT__"},
    {"name": "useSsl",   "value": false}
  ]
}'
configure_arr() {
    local label=$1 port=$2 cfg=$3 cat=$4 root=$5
    wait_http "http://localhost:${port}/ping" "$label" || return 0

    local key=$(api_key "$cfg")
    local base="http://localhost:${port}/api/v3"

    local dc_url="${base}/downloadclient"
    local dc_marker='"name":"qBittorrent"'
    local dc_body="${DC_BODY_TEMPLATE//__CAT__/$cat}"
    local dc_desc="qBittorrent download client (category '${cat}')"

    local rf_url="${base}/rootfolder"
    local rf_marker="\"path\":\"${root}\""
    local rf_body="{\"path\":\"${root}\"}"
    local rf_desc="root folder ${root}"

    ensure() {
        if   gcurl -H "X-Api-Key: $key" "$1" 2>/dev/null | grep -q "$2"
        then ok   "$label $4 already configured."
        elif gcurl -H "X-Api-Key: $key" -H "Content-Type: application/json" \
                -X POST "$1" -d "$3" >/dev/null 2>&1
        then ok   "$label → $4 added."
        else warn "$label $4 POST failed."
        fi
    }

    ensure "$dc_url" "$dc_marker" "$dc_body" "$dc_desc"
    ensure "$rf_url" "$rf_marker" "$rf_body" "$rf_desc"
}

APP_BODY_TEMPLATE='{
  "name": "__APP__", "implementation": "__APP__",
  "configContract": "__APP__Settings", "syncLevel": "fullSync",
  "fields": [
    {"name": "prowlarrUrl",    "value": "http://localhost:9696"},
    {"name": "baseUrl",        "value": "__BASE_URL__"},
    {"name": "apiKey",         "value": "__API_KEY__"},
    {"name": "syncCategories", "value": [__CATEGORIES__]}
  ]
}'
configure_prowlarr() {
    wait_http "http://localhost:9696/ping" "Prowlarr" || return 0

    local pkey=$(api_key prowlarr)
    local apps_url="http://localhost:9696/api/v1/applications"
    local apps=$(gcurl -H "X-Api-Key: $pkey" "$apps_url" 2>/dev/null)

    local son_name="Sonarr"
    local son_url="http://localhost:8989"
    local son_key=$(api_key sonarr)
    local son_cats="5000,5010,5020,5030,5040,5045,5050"

    local rad_name="Radarr"
    local rad_url="http://localhost:7878"
    local rad_key=$(api_key radarr)
    local rad_cats="2000,2010,2020,2030,2040,2045,2050,2060"

    link_app() {
        local name=$1 url=$2 key=$3 cats=$4
        local body="$APP_BODY_TEMPLATE"
        body="${body//__APP__/$name}"
        body="${body//__BASE_URL__/$url}"
        body="${body//__API_KEY__/$key}"
        body="${body//__CATEGORIES__/$cats}"

        if   echo "$apps" | grep -q "\"name\":\"$name\""
        then ok   "Prowlarr: $name already linked."
        elif gcurl -H "X-Api-Key: $pkey" -H "Content-Type: application/json" \
                -X POST "$apps_url" -d "$body" >/dev/null 2>&1
        then ok   "Prowlarr → $name linked (full sync)."
        else warn "Prowlarr: linking $name failed."
        fi
    }

    link_app "$son_name" "$son_url" "$son_key" "$son_cats"
    link_app "$rad_name" "$rad_url" "$rad_key" "$rad_cats"
}


main() {
    require_root
    load_env_exports

    info "configuring media stack mesh..."
    configure_qbittorrent
    configure_arr Sonarr 8989 sonarr tv     /data/tv
    configure_arr Radarr 7878 radarr movies /data/movies
    configure_prowlarr
    ok "media stack mesh configured."
}

main "$@"
