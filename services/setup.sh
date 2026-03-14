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
#   3.  SSH — disable password auth, enable pubkey only
#   4.  UFW — deny all incoming except SSH / DNS / HTTP / HTTPS
#   5.  fail2ban — ban IPs after 5 failed SSH attempts for 24h
#   6.  network — static IPs for Ethernet and WiFi via Netplan
#   7.  docker — install engine + compose plugin
#   8.  git — install + configure user + generate SSH key for GitHub
#   9.  pihole — free port 53 (disable systemd-resolved stub listener)
# =============================================================================

# ===== helpers ====================
info()  { echo "  [·] $*"; }
ok()    { echo "  [✓] $*"; }
warn()  { echo "  [!] $*"; }
die()   { echo "  [✗] $*" >&2; exit 1; }

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
info "setting up SSH..."
cat > /etc/ssh/sshd_config << 'EOF'
# managed by setup.sh
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PermitRootLogin no
Subsystem sftp /usr/lib/openssh/sftp-server
EOF
systemctl enable ssh
ok "SSH configured. password auth disabled, starts on boot."

## ===== UFW ====================
info "setting up UFW..."
apt-get install -y -q ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh          comment "SSH"
ufw allow 53/tcp       comment "DNS TCP (Pi-hole)"
ufw allow 53/udp       comment "DNS UDP (Pi-hole)"
ufw allow 80/tcp       comment "HTTP"
ufw allow 443/tcp      comment "HTTPS"
ufw --force enable
ok "firewall configured. allowed: SSH (22), DNS (53), HTTP (80), HTTPS (443)."
info "run 'ufw status' to review. add rules as services are deployed."

## ===== fail2ban ====================
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
read -rp  "  [?] Ethernet interface (default: enp0s31f6):        " ETH_IF;   ETH_IF=${ETH_IF:-enp0s31f6}
read -rp  "  [?] WiFi interface     (default: wlp2s0):           " WIFI_IF;  WIFI_IF=${WIFI_IF:-wlp2s0}
read -rp  "  [?] Ethernet IP        (default: 192.168.28.100/24):" ETH_IP;   ETH_IP=${ETH_IP:-192.168.28.100/24}
read -rp  "  [?] WiFi IP            (default: 192.168.28.101/24):" WIFI_IP;  WIFI_IP=${WIFI_IP:-192.168.28.101/24}
read -rp  "  [?] Gateway            (default: 192.168.28.1):     " GATEWAY;  GATEWAY=${GATEWAY:-192.168.28.1}
read -rp  "  [?] WiFi network: " WIFI_SSID
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

## ===== docker ====================
info "installing docker..."
apt-get install -y -q docker.io docker-compose-v2
systemctl enable docker
ok "docker installed. $(docker --version)"

## ===== git + SSH key for GitHub ====================
info "setting up git..."
apt-get install -y -q git

# Determine non-root user to configure git for
GIT_USER="${SUDO_USER:-}"
if [[ -z "$GIT_USER" ]]; then
    read -rp "  [?] Username to configure git for (e.g. void): " GIT_USER
fi
GIT_HOME=$(getent passwd "$GIT_USER" | cut -d: -f6)

read -rp  "  [?] git user.name  (e.g. John Doe): "           GIT_NAME
read -rp  "  [?] git user.email (e.g. john@example.com): "   GIT_EMAIL

sudo -u "$GIT_USER" git config --global user.name  "$GIT_NAME"
sudo -u "$GIT_USER" git config --global user.email "$GIT_EMAIL"
sudo -u "$GIT_USER" git config --global init.defaultBranch main

# Generate SSH key if one doesn't exist
SSH_DIR="$GIT_HOME/.ssh"
KEY_FILE="$SSH_DIR/id_ed25519"
mkdir -p "$SSH_DIR"
if [[ ! -f "$KEY_FILE" ]]; then
    sudo -u "$GIT_USER" ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$KEY_FILE" -N ""
    ok "SSH key generated."
else
    ok "SSH key already exists, skipping generation."
fi

chmod 700 "$SSH_DIR"
chmod 600 "$KEY_FILE"
chmod 644 "${KEY_FILE}.pub"
chown -R "$GIT_USER:$GIT_USER" "$SSH_DIR"

echo ""
warn "Add this public key to GitHub → Settings → SSH and GPG keys → New SSH key:"
echo ""
cat "${KEY_FILE}.pub"
echo ""
info "verify with: ssh -T git@github.com"
ok "git configured for $GIT_USER."

## ===== pihole — free port 53 ====================
info "disabling systemd-resolved stub listener (frees port 53 for Pi-hole)..."
sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
ok "DNS stub listener disabled."

## ===== done ====================
echo ""
ok "setup complete. review configs above, add the SSH key to GitHub, then reboot."
