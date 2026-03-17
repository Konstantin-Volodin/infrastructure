#!/bin/bash
# =============================================================================
# setup.sh — provision void (Ubuntu Server 24.04 LTS)
#
# usage:
#   scp services/setup.sh user@host:~/setup.sh
#   sudo bash ~/setup.sh
#
# what this does:
#   1.  system update
#   2.  disable sleep & suspend
#   3.  SSH hardening — pubkey only, no root login
#   4.  UFW firewall — deny all except SSH, DNS, HTTP, HTTPS
#   5.  fail2ban — ban IPs after 5 failed SSH attempts
#   6.  network — static IPs via Netplan
#   7.  docker + git — install
#   8.  docker network — create shared 'net' for inter-container routing
#   9.  pihole — free port 53 (disable systemd-resolved stub listener)
#  10.  tailscale — install for private remote access
# =============================================================================

info() { echo "  [·] $*"; }
ok()   { echo "  [✓] $*"; }
warn() { echo "  [!] $*"; }
die()  { echo "  [✗] $*" >&2; exit 1; }

set -euo pipefail
[[ $EUID -ne 0 ]] && die "run as root: sudo bash setup.sh"

## ===== system update ====================
info "updating packages..."
apt-get update -q 
apt-get upgrade -y -q
ok "system up to date."

## ===== disable sleep & suspend ====================
info "disabling sleep..."
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
ok "sleep and suspend disabled."

## ===== SSH ====================
info "hardening SSH..."
cat > /etc/ssh/sshd_config << 'EOF'
# managed by setup.sh
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PermitRootLogin no
Subsystem sftp /usr/lib/openssh/sftp-server
EOF
systemctl enable ssh
ok "SSH hardened. password auth disabled."

## ===== UFW ====================
info "configuring firewall..."
apt-get install -y -q ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh      comment "SSH"
ufw allow 53/tcp   comment "DNS (Pi-hole)"
ufw allow 53/udp   comment "DNS (Pi-hole)"
ufw allow 80/tcp   comment "HTTP (Caddy)"
ufw allow 443/tcp  comment "HTTPS (Caddy)"
ufw --force enable
ok "firewall enabled. allowed: SSH, DNS, HTTP, HTTPS."

## ===== fail2ban ====================
info "configuring fail2ban..."
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
info "configuring static network..."
read -rp  "  [?] Ethernet interface (default: enp0s31f6):         " ETH_IF;  ETH_IF=${ETH_IF:-enp0s31f6}
read -rp  "  [?] WiFi interface     (default: wlp2s0):            " WIFI_IF; WIFI_IF=${WIFI_IF:-wlp2s0}
read -rp  "  [?] Ethernet IP        (default: 192.168.28.100/24): " ETH_IP;  ETH_IP=${ETH_IP:-192.168.28.100/24}
read -rp  "  [?] WiFi IP            (default: 192.168.28.101/24): " WIFI_IP; WIFI_IP=${WIFI_IP:-192.168.28.101/24}
read -rp  "  [?] Gateway            (default: 192.168.28.1):      " GW;      GW=${GW:-192.168.28.1}
read -rp  "  [?] WiFi SSID: " WIFI_SSID
read -rsp "  [?] WiFi password: " WIFI_PASS; echo

cat > /etc/netplan/50-cloud-init.yaml << EOF
network:
  version: 2
  ethernets:
    ${ETH_IF}:
      dhcp4: no
      optional: true
      addresses: [${ETH_IP}]
      routes:
        - { to: default, via: ${GW}, metric: 100 }
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
        - { to: default, via: ${GW}, metric: 600 }
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
EOF

chmod 600 /etc/netplan/50-cloud-init.yaml
netplan apply
ok "network configured. Ethernet: ${ETH_IP}, WiFi: ${WIFI_IP}."

## ===== docker + git ====================
info "installing docker and git..."
apt-get install -y -q docker.io docker-compose-v2 git
systemctl enable docker
ok "docker $(docker --version | cut -d' ' -f3 | tr -d ',') and git installed."

## ===== docker network ====================
info "creating shared docker network..."
docker network create net 2>/dev/null || true
ok "docker network 'net' ready."

## ===== pihole — free port 53 ====================
info "freeing port 53 for Pi-hole..."
sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
ok "systemd-resolved stub listener disabled."

## ===== tailscale ====================
info "installing tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh
systemctl enable tailscaled
ok "tailscale installed. run 'sudo tailscale up' to authenticate."

## ===== done ====================
echo ""
ok "setup complete. reboot for funsies."
