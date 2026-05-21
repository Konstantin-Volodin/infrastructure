#!/bin/bash
# This script wires up the media stack mesh automatically.

set -euo pipefail

source scripts/lib/log.sh
source scripts/lib/runtime.sh
CURL_IMAGE="curlimages/curl:8.11.1"


gcurl() { docker run --rm --network "container:gluetun" "$CURL_IMAGE" -fsS --max-time 20 "$@"; }

wait_http() {
    for _ in {1..60}; do
        gcurl -o /dev/null "$1" 2>/dev/null && { ok "$2 is ready."; return 0; }
        sleep 2
    done
    warn "$2 not reachable after 120s - skipping."
    return 1
}

api_key() {
    local f="${DATA_DIR}/$1/config.xml"
    for _ in {1..30}; do
        [ -f "$f" ] && grep -q '<ApiKey>' "$f" && { sed -n 's:.*<ApiKey>\(.*\)</ApiKey>.*:\1:p' "$f"; return 0; }
        sleep 2
    done
    return 1
}

configure_qbittorrent() {
    wait_http "http://localhost:8080/api/v2/app/version" "qBittorrent" || return 0
    set_category() {
        gcurl -X POST "http://localhost:8080/api/v2/torrents/createCategory" \
            --data-urlencode "category=$1" --data-urlencode "savePath=$2" >/dev/null 2>&1 || \
        gcurl -X POST "http://localhost:8080/api/v2/torrents/editCategory" \
            --data-urlencode "category=$1" --data-urlencode "savePath=$2" >/dev/null 2>&1
        ok "qBittorrent: '$1' → $2"
    }
    set_category books  /data/cwa-books-ingest
    set_category tv     /data/downloads/tv
    set_category movies /data/downloads/movies
}

# $1=Label $2=port $3=configDir $4=qbitCategory $5=rootFolder
configure_arr() {
    local label=$1 port=$2 cfg=$3 cat=$4 root=$5 key base
    wait_http "http://localhost:${port}/ping" "$label" || return 0

    if ! key=$(api_key "$cfg"); then
        warn "$label API key not found in ${DATA_DIR}/${cfg}/config.xml — skipping."
        return 0
    fi
    base="http://localhost:${port}/api/v3"

    if gcurl -H "X-Api-Key: $key" "${base}/downloadclient" 2>/dev/null \
        | grep -q '"name":"qBittorrent"'; then
        ok "$label download client already configured."
    elif gcurl -H "X-Api-Key: $key" -H "Content-Type: application/json" \
        -X POST "${base}/downloadclient" -d "{
          \"enable\":true,\"protocol\":\"torrent\",\"priority\":1,
          \"name\":\"qBittorrent\",\"implementation\":\"QBittorrent\",
          \"configContract\":\"QBittorrentSettings\",
          \"fields\":[
            {\"name\":\"host\",\"value\":\"localhost\"},
            {\"name\":\"port\",\"value\":8080},
            {\"name\":\"category\",\"value\":\"${cat}\"},
            {\"name\":\"useSsl\",\"value\":false}
          ]}" >/dev/null 2>&1; then
        ok "$label → qBittorrent download client added (category '${cat}')."
    else
        warn "$label download client POST failed (API shape changed?)."
    fi

    if gcurl -H "X-Api-Key: $key" "${base}/rootfolder" 2>/dev/null \
        | grep -q "\"path\":\"${root}\""; then
        ok "$label root folder already configured."
    elif gcurl -H "X-Api-Key: $key" -H "Content-Type: application/json" \
        -X POST "${base}/rootfolder" -d "{\"path\":\"${root}\"}" >/dev/null 2>&1; then
        ok "$label → root folder ${root} added."
    else
        warn "$label root folder POST failed (path missing on disk?)."
    fi
}

configure_prowlarr() {
    wait_http "http://localhost:9696/ping" "Prowlarr" || return 0

    local pkey skey rkey apps
    if ! pkey=$(api_key prowlarr); then
        warn "Prowlarr API key not found — skipping app links."
        return 0
    fi
    skey=$(api_key sonarr || true)
    rkey=$(api_key radarr || true)
    apps=$(gcurl -H "X-Api-Key: $pkey" \
        "http://localhost:9696/api/v1/applications" 2>/dev/null || echo '[]')

    # $1=name $2=implementation $3=baseUrl $4=appApiKey $5=syncCategories
    link_app() {
        if echo "$apps" | grep -q "\"name\":\"$1\""; then
            ok "Prowlarr: $1 already linked."
            return 0
        fi
        if [ -z "$4" ]; then
            warn "Prowlarr: $1 API key unavailable — skipping link."
            return 0
        fi
        if gcurl -H "X-Api-Key: $pkey" -H "Content-Type: application/json" \
            -X POST "http://localhost:9696/api/v1/applications" -d "{
              \"name\":\"$1\",\"implementation\":\"$2\",
              \"configContract\":\"${2}Settings\",\"syncLevel\":\"fullSync\",
              \"fields\":[
                {\"name\":\"prowlarrUrl\",\"value\":\"http://localhost:9696\"},
                {\"name\":\"baseUrl\",\"value\":\"$3\"},
                {\"name\":\"apiKey\",\"value\":\"$4\"},
                {\"name\":\"syncCategories\",\"value\":[$5]}
              ]}" >/dev/null 2>&1; then
            ok "Prowlarr → $1 linked (full sync)."
        else
            warn "Prowlarr: linking $1 failed (API shape changed?)."
        fi
    }

    link_app Sonarr Sonarr "http://localhost:8989" "$skey" \
        "5000,5010,5020,5030,5040,5045,5050"
    link_app Radarr Radarr "http://localhost:7878" "$rkey" \
        "2000,2010,2020,2030,2040,2045,2050,2060"
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
