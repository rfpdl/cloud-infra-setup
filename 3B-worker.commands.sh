#!/bin/bash

# Worker Configuration Script (renamed from 2B-worker.commands.sh)
# Run after 1-server-hardening.sh and 2-server-bootstrap.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

load_env() {
    local env_file=".env"
    if [ -f "$env_file" ]; then
        echo -e "${GREEN}Loading configuration from $env_file${NC}"
        set -a
        source <(grep -v '^#' "$env_file" | grep -v '^$')
        set +a
    else
        echo -e "${YELLOW}No .env file found, using default values${NC}"
        echo -e "${BLUE}To customize configuration, copy .env.example to .env${NC}"
    fi
}

set_defaults() {
    USERNAME=${USERNAME:-"ubuntu"}
    SSH_PORT=${SSH_PORT:-"22"}
    FAIL2BAN_FINDTIME=${FAIL2BAN_FINDTIME:-"600"}
    FAIL2BAN_MAXRETRY=${FAIL2BAN_MAXRETRY:-"5"}
    FAIL2BAN_BANTIME=${FAIL2BAN_BANTIME:-"600"}
    CONTROL_PLANE_IP=${CONTROL_PLANE_IP:-""}
}

validate_config() {
    if [ -z "$CONTROL_PLANE_IP" ]; then
        echo -e "${RED}ERROR: CONTROL_PLANE_IP is required for worker configuration${NC}"
        echo -e "${YELLOW}Please set CONTROL_PLANE_IP in your .env file${NC}"
        exit 1
    fi
}

load_env
set_defaults
validate_config

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
