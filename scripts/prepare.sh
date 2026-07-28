#!/bin/bash
# =============================================================================
# prepare.sh - provision the host (Ubuntu Server 24.04 LTS).
#
# usage:
#   sudo bash scripts/prepare.sh
#   # or via just: `just prepare`
#
# what this does:
#   1.  system update
#   2.  disable sleep & suspend
#   3.  SSH hardening - pubkey only, no root login
#   4.  UFW firewall - deny all except SSH, DNS, HTTP, HTTPS
#   5.  fail2ban - ban IPs after 5 failed SSH attempts
#   6.  network - DHCP on both links via Netplan, ethernet preferred
#   7.  docker + git + helper tools
#   8.  pihole - free port 53 (disable systemd-resolved stub listener)
# =============================================================================

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_root

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
# managed by prepare.sh
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
info "configuring network..."
read -rp  "  [?] Ethernet interface (default: enp0s31f6): " ETH_IF;  ETH_IF=${ETH_IF:-enp0s31f6}
read -rp  "  [?] WiFi interface     (default: wlp2s0):    " WIFI_IF; WIFI_IF=${WIFI_IF:-wlp2s0}
read -rp  "  [?] WiFi SSID: " WIFI_SSID
read -rsp "  [?] WiFi password: " WIFI_PASS; echo

# both links take DHCP - the LAN address is not load-bearing here. HOST_IP is
# re-detected on every `just up`, and Pi-hole's wildcard resolves to the
# Tailscale IP. Pin a reservation on the router if you want a stable address.
# Route metrics keep ethernet preferred and wifi as fallback.
cat > /etc/netplan/50-cloud-init.yaml << EOF
network:
  version: 2
  ethernets:
    ${ETH_IF}:
      dhcp4: true
      optional: true
      dhcp4-overrides:
        route-metric: 100
  wifis:
    ${WIFI_IF}:
      dhcp4: true
      optional: true
      dhcp4-overrides:
        route-metric: 600
      access-points:
        "${WIFI_SSID}":
          password: "${WIFI_PASS}"
EOF

chmod 600 /etc/netplan/50-cloud-init.yaml
netplan apply
ok "network configured. ethernet preferred, wifi fallback, both via DHCP."

## ===== docker + git + helper tools ====================
info "installing docker, git, and helper tools..."
apt-get install -y -q docker.io docker-compose-v2 git gettext-base just
systemctl enable docker
ok "docker $(docker --version | cut -d' ' -f3 | tr -d ',') and helper tools installed."

## ===== pihole - free port 53 ====================
info "freeing port 53 for Pi-hole..."
sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf

# with the stub listener off, nothing answers on 127.0.0.53 - the address the
# default /etc/resolv.conf symlink points at. Replace it with real upstreams so
# the host can still resolve, and resolve without depending on Pi-hole being up
# (Pi-hole is a container; needing DNS to start it would be circular).
rm -f /etc/resolv.conf
cat > /etc/resolv.conf << 'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

systemctl restart systemd-resolved
ok "systemd-resolved stub listener disabled, host resolver pointed upstream."

## ===== done ====================
echo ""
ok "setup complete. reboot for funsies."
