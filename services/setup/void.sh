#!/bin/bash
# =============================================================================
# SSH setup
# Ubuntu Server 24.04 LTS
#
# running:
#   scp services/setup/void.sh user@host:/setup.sh
#   sudo bash setup.sh
#
# what this does:
#   1. updates the system
#   2. disables sleep & suspend
#   3. SSH — disable password auth, enable on startup
#   4. UFW firewall — deny all incoming except SSH (22) and DNS (53), allow all outgoing
#   5. fail2ban - basic config to ban IPs after 5 failed SSH attempts for a day
#   6. network configuration — set static IPs for Ethernet and WiFi
#   7. docker — install docker engine and docker compose
# =============================================================================

# ===== helpers ====================
info()  { echo "  [·] $*"; }
ok()    { echo "  [✓] $*"; }
warn()  { echo "  [!] $*"; }
die()   { echo "  [✗] $*" >&2; exit 1; }

# ===== log errors ====================
set -euo pipefail
[[ $EUID -ne 0 ]] && die "run as root: sudo bash setup.sh"

## ===== system update ====================
info "updating packages..."
apt-get update -q
apt-get upgrade -y -q
ok "system up to date."

## ===== disable sleep & suspend ====================
info "disabling sleep..."
systemctl mask sleep.target
systemctl mask suspend.target
systemctl mask hibernate.target
systemctl mask hybrid-sleep.target

ok "sleep and suspend disabled."

## ===== SSH ====================
info "setting up SSH..."
SSHD_CONFIG="/etc/ssh/sshd_config"
cat > "$SSHD_CONFIG" << 'EOF'
# managed by setup.sh
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PermitRootLogin no
Subsystem sftp /usr/lib/openssh/sftp-server
EOF
systemctl enable ssh

ok "SSH configured. Password auth disabled, starts on boot."

# ===== UFW ====================
info "setting up UFW..."
apt-get install -y -q ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh comment "SSH"
ufw allow 53  comment "DNS TCP (Pi-hole)"
ufw allow 53/udp comment "DNS UDP (Pi-hole)"
ufw allow 80/tcp comment "Pi-hole web UI"
ufw allow 443/tcp comment "Pi-hole web UI HTTPS"
ufw --force enable

ok "firewall configured. allowed: SSH (22), DNS TCP (53), DNS UDP (53), HTTP (80), HTTPS (443)."
info "run 'ufw status' to review. add more rules as services are deployed."

# ===== fail2ban ====================
info "setting up fail2ban..."
apt-get install -y -q fail2ban
cat > /etc/fail2ban/jail.d/sshd.local << 'EOF'
[sshd]
enabled  = true
port     = ssh
maxretry = 5
findtime = 1h
bantime  = 24h
EOF
systemctl enable --now fail2ban
ok "fail2ban configured."

## ===== network ====================
info "configuring network..."
read -rp  "  [?] Ethernet interface (default: enp0s31f6):       " ETH_IF;   ETH_IF=${ETH_IF:-enp0s31f6}
read -rp  "  [?] WiFi interface     (default: wlp2s0):          " WIFI_IF;   WIFI_IF=${WIFI_IF:-wlp2s0}
read -rp  "  [?] Ethernet IP        (default: 192.168.28.100/24): " ETH_IP;  ETH_IP=${ETH_IP:-192.168.28.100/24}
read -rp  "  [?] WiFi IP            (default: 192.168.28.101/24): " WIFI_IP; WIFI_IP=${WIFI_IP:-192.168.28.101/24}
read -rp  "  [?] Gateway            (default: 192.168.28.1):    " GATEWAY;  GATEWAY=${GATEWAY:-192.168.28.1}
read -rp  "  [?] WiFi SSID: " WIFI_SSID
read -rsp "  [?] WiFi password: " WIFI_PASS
echo

cat > /etc/netplan/50-cloud-init.yaml << EOF
network:
  version: 2
  ethernets:
    ${ETH_IF}:
      dhcp4: no
      optional: true
      addresses: [${ETH_IP}]
      routes:
        - to: default
          via: ${GATEWAY}
          metric: 100
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
  wifis:
    ${WIFI_IF}:
      optional: true
      access-points:
        "${WIFI_SSID}":
          password: "${WIFI_PASS}"
      dhcp4: no
      addresses: [${WIFI_IP}]
      routes:
        - to: default
          via: ${GATEWAY}
          metric: 600
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
EOF

chmod 600 /etc/netplan/50-cloud-init.yaml
netplan apply
ok "network configured. Ethernet: ${ETH_IP}, WiFi: ${WIFI_IP}"

# ===== docker ====================
info "installing docker..."
apt-get install -y -q docker.io
apt-get install -y -q docker-compose-v2
systemctl enable docker
ok "docker installed. version: $(docker --version)"

# ===== pihole ====================
info "disabling systemd-resolved stub listener (frees port 53 for Pi-hole)..."
sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
ok "DNS stub listener disabled."

# ===== done =====================
ok "setup complete. review configs, adjust as needed, and reboot."
