#!/bin/bash
# Remove torrents whose library copy is gone. Sonarr and Radarr import by
# hardlink, so deleting from a UI drops one name and qBittorrent keeps seeding
# the other. Link count is the tell: two names means the library still wants it.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CURL_IMAGE="curlimages/curl:8.11.1"
QBIT_API="http://localhost:8080/api/v2"

# A torrent that just finished may not be imported yet — leave it alone.
GRACE_HOURS="${REAP_GRACE_HOURS:-24}"

DRY_RUN=0


gcurl() {
    docker run --rm --network container:gluetun "$CURL_IMAGE" -fsS --max-time 30 "$@"
}

usage() {
    echo "usage: sudo bash scripts/reap.sh [--dry-run]"
    echo "  -n, --dry-run   report what would be reaped, remove nothing"
    exit 0
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -n|--dry-run) DRY_RUN=1 ;;
            -h|--help)    usage ;;
            *)            die "unknown argument: $1" ;;
        esac
        shift
    done
}

# One TSV row per doomed torrent on stdout, the human report on stderr.
classify() {
    python3 - "$MEDIA_DIR" "$GRACE_HOURS" "$1" <<'PY'
import json, os, sys, time

media_dir  = sys.argv[1]
grace_secs = int(sys.argv[2]) * 3600
now        = time.time()

torrents = json.load(open(sys.argv[3]))

def host_path(p):
    # qBittorrent sees the media root as /data; the host has it at MEDIA_DIR.
    return media_dir + p[len("/data"):] if p.startswith("/data") else p

def link_survey(path):
    """(highest link count, total bytes) across the torrent's content."""
    if os.path.isfile(path):
        st = os.stat(path)
        return st.st_nlink, st.st_size

    best, total = 0, 0
    for root, _, files in os.walk(path):
        for name in files:
            try:
                st = os.stat(os.path.join(root, name))
            except OSError:
                continue
            best   = max(best, st.st_nlink)
            total += st.st_size
    return best, total

reap, keep, waiting, missing = [], [], [], []

for t in torrents:
    if t.get("progress", 0) < 1:
        continue                                      # still downloading

    path = host_path(t["content_path"])
    age  = now - t.get("completion_on", 0)

    if not os.path.exists(path):
        missing.append((t, 0))
    elif age < grace_secs:
        waiting.append((t, 0))                        # too fresh to judge
    else:
        links, size = link_survey(path)
        (keep if links >= 2 else reap).append((t, size))

def report(label, rows, show=6):
    if not rows:
        return
    total = sum(size for _, size in rows)
    print(f"\n  {label}: {len(rows)} torrent(s), {total/1e9:.1f} GB", file=sys.stderr)
    for t, size in sorted(rows, key=lambda r: -r[1])[:show]:
        print(f"      {size/1e9:7.2f} GB  {t['name'][:70]}", file=sys.stderr)
    if len(rows) > show:
        print(f"      ... and {len(rows) - show} more", file=sys.stderr)

report("still in the library, seeding on", keep)
report("inside grace period, left alone", waiting)
report("files already gone, clearing the entry", missing)
report("NO library copy, reaping", reap)

print(f"\n  reclaiming {sum(size for _, size in reap)/1e9:.1f} GB\n", file=sys.stderr)

for t, size in reap + missing:
    print(f"{t['hash']}\t{size}\t{t['name']}")
PY
}


main() {
    parse_args "$@"
    require_root
    load_env_exports

    [ -n "${MEDIA_DIR:-}" ] || die "MEDIA_DIR unset — run 'just env' first"

    info "asking qBittorrent what it is holding..."
    local list; list=$(mktemp)
    trap 'rm -f "$list"' EXIT
    gcurl "${QBIT_API}/torrents/info" > "$list" \
        || die "qBittorrent unreachable — is the stack up?"

    info "checking each torrent for a surviving library hardlink..."
    local doomed
    doomed=$(classify "$list")

    if [ -z "$doomed" ]; then
        ok "nothing to reap — every torrent still has a library copy."
        return
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        warn "dry run — nothing removed. Drop --dry-run to go through with it."
        return
    fi

    # One call, pipe-separated: qBittorrent takes the whole batch at once.
    local hashes
    hashes=$(cut -f1 <<< "$doomed" | paste -sd'|' -)

    gcurl -X POST "${QBIT_API}/torrents/delete" \
        --data-urlencode "hashes=${hashes}" \
        --data-urlencode "deleteFiles=true" > /dev/null \
        || die "delete call failed — nothing was removed"

    ok "reaped $(wc -l <<< "$doomed") torrent(s) and their files."
}

main "$@"
