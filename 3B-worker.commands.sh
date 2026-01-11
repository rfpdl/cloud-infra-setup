#!/bin/bash

# Worker Configuration Script
# Run after 1-server-hardening.sh and 2-server-bootstrap.sh

set -e

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
    source "$SCRIPT_DIR/lib/common.sh"
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
fi

# Error handler
trap 'echo -e "${RED}❌ Error on line $LINENO${NC}"; exit 1' ERR

# Load environment
if type load_env_safe &>/dev/null; then
    load_env_safe ".env" || echo -e "${YELLOW}No .env file found, using defaults${NC}"
else
    [ -f ".env" ] && { set -a; source <(grep -v '^#' ".env" | grep -v '^$'); set +a; }
fi

# Set defaults
if type set_defaults &>/dev/null; then
    set_defaults
else
    USERNAME=${USERNAME:-"ubuntu"}
    SSH_PORT=${SSH_PORT:-"22"}
    FAIL2BAN_FINDTIME=${FAIL2BAN_FINDTIME:-"600"}
    FAIL2BAN_MAXRETRY=${FAIL2BAN_MAXRETRY:-"3"}
    FAIL2BAN_BANTIME=${FAIL2BAN_BANTIME:-"3600"}
    CONTROL_PLANE_IP=${CONTROL_PLANE_IP:-""}
fi

# Validate CONTROL_PLANE_IP is set and valid
if [ -z "$CONTROL_PLANE_IP" ]; then
    echo -e "${RED}ERROR: CONTROL_PLANE_IP is required for worker configuration${NC}"
    echo -e "${YELLOW}Please set CONTROL_PLANE_IP in your .env file${NC}"
    exit 1
fi

if type validate_ipv4 &>/dev/null && ! validate_ipv4 "$CONTROL_PLANE_IP"; then
    echo -e "${RED}ERROR: Invalid CONTROL_PLANE_IP: $CONTROL_PLANE_IP${NC}"
    exit 1
fi

echo -e "${BLUE}🔧 Starting Worker Configuration${NC}"
echo -e "${BLUE}User: ${USERNAME}, SSH Port: ${SSH_PORT}${NC}"
echo -e "${BLUE}Control Plane IP: ${CONTROL_PLANE_IP}${NC}"

# Fail2ban config
echo -e "${YELLOW}Configuring fail2ban...${NC}"
cat > /etc/fail2ban/jail.local << EOF
[sshd]
enabled = true
port = ssh,${SSH_PORT}
banaction = iptables-multiport
findtime = ${FAIL2BAN_FINDTIME}
maxretry = ${FAIL2BAN_MAXRETRY}
bantime = ${FAIL2BAN_BANTIME}
EOF
systemctl enable fail2ban
systemctl start fail2ban

# Firewall rules (locked down to control plane)
echo -e "${YELLOW}Configuring firewall for Worker (locked down)...${NC}"
ufw allow ${SSH_PORT}/tcp comment 'SSH Port'
ufw allow from $CONTROL_PLANE_IP to any port 2377 proto tcp comment 'Swarm Management'
ufw allow from $CONTROL_PLANE_IP to any port 7946 proto tcp comment 'Swarm Discovery TCP'
ufw allow from $CONTROL_PLANE_IP to any port 7946 proto udp comment 'Swarm Discovery UDP'
ufw allow from $CONTROL_PLANE_IP to any port 4789 proto udp comment 'Overlay Network'
ufw allow out 443/tcp comment 'HTTPS outbound'
ufw allow out 80/tcp comment 'HTTP outbound'
ufw deny 2375/tcp comment 'Block Docker API (unencrypted)'
ufw deny 2376/tcp comment 'Block Docker API (TLS)'
ufw reload
ufw --force enable

# SSH directory permissions
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.ssh
chmod 700 /home/${USERNAME}/.ssh
chmod 600 /home/${USERNAME}/.ssh/authorized_keys

# Docker permissions and verification (assumes bootstrap installed Docker)
mkdir -p /home/${USERNAME}/.docker
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.docker
chmod 700 /home/${USERNAME}/.docker
echo "export DOCKER_CONFIG=\"/home/${USERNAME}/.docker\"" >> /home/${USERNAME}/.bashrc

echo -e "${YELLOW}Testing Docker access...${NC}"
sudo -u ${USERNAME} env DOCKER_CONFIG="/home/${USERNAME}/.docker" docker ps 2>/dev/null || true
if sudo -u ${USERNAME} env DOCKER_CONFIG="/home/${USERNAME}/.docker" docker compose version >/dev/null 2>&1; then
  echo -e "${GREEN}Docker Compose v2 available (docker compose)${NC}"
elif command -v docker-compose >/dev/null 2>&1; then
  sudo -u ${USERNAME} docker-compose --version
  echo -e "${YELLOW}Using legacy docker-compose binary (v1). Consider installing docker-compose-plugin for v2.${NC}"
else
  echo -e "${RED}Docker Compose not found. Install one of the following:${NC}"
  echo -e "  - ${YELLOW}docker-compose-plugin${NC} (preferred, provides 'docker compose')"
  echo -e "  - ${YELLOW}docker-compose${NC} (legacy binary)"
fi

echo -e "${YELLOW}Creating Dokploy network...${NC}"
sudo -u ${USERNAME} docker network create dokploy-network 2>/dev/null || true

echo -e "${GREEN}✅ Worker configuration completed successfully!${NC}"
