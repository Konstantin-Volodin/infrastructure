# Media Automation Stack
Centralized documentation for a self-hosted media stack handling books, TV/movies, music, and audiobooks.


## Phase 1: Shared services
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
- **qBittorrent auth bypass**: Settings → Web UI → Authentication → enable "Bypass authentication for clients in whitelisted IP subnets" → add `172.0.0.0/8` (allows LazyLibrarian and other Docker containers to connect without credentials)
- **Add indexers**: Prowlarr → Indexers → Add. Recommended public indexers:
  - The Pirate Bay (general)
  - LimeTorrents (general)
  - YTS (movies)
  - Nyaa (anime)


## Phase 2: Books
Automated ebook management with Calibre-Web and LazyLibrarian.

### Services
- LazyLibrarian (book search and download automation)
- Calibre-Web (ebook reading UI)

### Setup order
1. Deploy LazyLibrarian, connect to Prowlarr + qBittorrent, set Calibre library path
2. Deploy Calibre-Web, point to same Calibre library path

### Post-deploy
- **apikey in LazyLibrarian**: Settings → Interface → API key (generate a new one, full access)
- **Prowlarr → LazyLibrarian sync**: Prowlarr → Settings → Apps → Add → LazyLibrarian (Prowlarr server: `http://prowlarr:9696`, LazyLibrarian server: `http://lazylibrarian:5299`, API key: LazyLibrarian full access key from Settings → Interface)
- **qBittorrent in LazyLibrarian**: Settings → Downloaders → qBittorrent (host: `gluetun`, port: `8080`)
- **Calibre-Web**: login with `admin` / `admin123`, then:
  - Point library path to `/books`
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