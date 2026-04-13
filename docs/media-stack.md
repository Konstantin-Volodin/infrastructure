# Media Automation Stack
Centralized documentation for a self-hosted media stack handling books, TV/movies, music, and audiobooks.


## (done) Phase 1: Shared services
Shared services that support the media stack.

### Services
- Prowlarr (indexer manager)
- qBittorrent (download client)
- Gluetun (VPN container)

### VPN setup
Gluetun handles the connection via ProtonVPN (OpenVPN). \
Get your OpenVPN credentials from https://account.protonvpn.com/account#openvpn and set `PROTONVPN_OPENVPN_USER` / `PROTONVPN_OPENVPN_PASSWORD` in `.env`.

### Setup order
1. Deploy Gluetun (with ProtonVPN OpenVPN credentials in `.env`)
2. Deploy qBittorrent (attached to Gluetun network)
3. Deploy Prowlarr and add indexers

### Post-deploy
- **Verify VPN**: `sudo docker exec gluetun wget -qO- ifconfig.me` — should return a Canadian IP
- **qBittorrent login**: `sudo docker logs qbittorrent | grep "password"` for the generated password (user: `admin`)
- **qBittorrent auth bypass**: Settings → Web UI → Authentication → enable "Bypass authentication for clients in whitelisted IP subnets" → add `172.0.0.0/8` (allows Shelfmark and other Docker containers to connect without credentials)
- **Add indexers**: Prowlarr → Indexers → Add. Recommended public indexers:
  - The Pirate Bay (general)
  - LimeTorrents (general)
  - YTS (movies)
  - Nyaa (anime)


## (done) Phase 2: Books
Automated ebook management with Shelfmark and Calibre-Web-Automated.

### Services
- Shelfmark (book search and download automation)
- Calibre-Web-Automated (ebook library manager + reading UI, auto-imports new books)

### Setup order
1. Deploy Shelfmark + Calibre-Web-Automated
2. Connect Shelfmark to Prowlarr + qBittorrent
3. In qBittorrent, create a `books` category with save path `/cwa-book-ingest` and set torrent management mode to **Automatic**

### Post-deploy
- **Shelfmark → Prowlarr**: Settings → Prowlarr (server: `http://prowlarr:9696`, API key from Prowlarr → Settings → General)
- **Shelfmark → qBittorrent**: Settings → qBittorrent (host: `gluetun`, port: `8080`, category: `books`, destination: `/cwa-book-ingest`)
- **Shelfmark direct download path**: Settings → Advanced → set download path to `/cwa-book-ingest` (otherwise files are lost inside the container)
- **qBittorrent `books` category**: right-click Categories → Add → name `books`, save path `/cwa-book-ingest`; Options → Downloads → set torrent management mode to **Automatic**
- **Calibre-Web-Automated**: login with `admin` / `admin123`, then:
  - Admin → Basic Configuration → Enable **Allow Reverse Proxy Authentication** → set header to `Remote-User`
  - Create a user matching your Authelia username


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