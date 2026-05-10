# Media Automation Stack
Centralized documentation for a self-hosted media stack handling books, TV/movies, music, and audiobooks.

Phase 1 (shared services: Prowlarr, qBittorrent, Gluetun) and Phase 2 (Books: Shelfmark, Calibre-Web-Automated) are deployed — see [README.md](../README.md#post-setup) for their operational reference.


## Phase 3: TV & Movies
Automated TV show and movie management with streaming via Jellyfin.

### Services
- Sonarr (TV show automation)
- Radarr (movie automation)
- Jellyfin (media server)

### Setup order
1. Deploy Sonarr + Radarr, connect to Prowlarr + qBittorrent
2. Deploy Jellyfin, point to media directories
3. Add Caddy routes + Homepage entries


## Optional: Music
Automated music management with Lidarr and streaming via Navidrome.

### Services
- Lidarr (music automation)
- Navidrome (music streaming server)
- Audiobookshelf (audiobook server)

## RAM considerations
Current stack uses ~2.5 GB. Each phase adds:
- shared services: ~1 GB (Gluetun is the main consumer)
- Books: ~0.5 GB
- TV/movies: ~1-1.5 GB (Jellyfin is the main consumer)
- Music: ~0.5 GB

Total: ~5 GB with everything running