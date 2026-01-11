#!/bin/bash

# Control Plane Configuration Script
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
    CONTROL_PLANE_UI_PORT=${CONTROL_PLANE_UI_PORT:-"3000"}
    PROMETHEUS_PORT=${PROMETHEUS_PORT:-"9090"}
    GRAFANA_PORT=${GRAFANA_PORT:-"3001"}
fi

# Auto-detect public IP if not set
if [ -z "$CONTROL_PLANE_IP" ]; then
    if type get_public_ip &>/dev/null; then
        CONTROL_PLANE_IP=$(get_public_ip)
    else
        CONTROL_PLANE_IP=$(curl -s --max-time 5 https://ifconfig.me || curl -s --max-time 5 https://api.ipify.org || hostname -I | awk '{print $1}')
    fi
fi

# Validate IP
if type validate_ipv4 &>/dev/null && ! validate_ipv4 "$CONTROL_PLANE_IP"; then
    echo -e "${RED}Invalid CONTROL_PLANE_IP: $CONTROL_PLANE_IP${NC}"
    exit 1
fi

echo -e "${BLUE}🚀 Starting Control Plane Configuration${NC}"
echo -e "${BLUE}User: ${USERNAME}, SSH Port: ${SSH_PORT}${NC}"

# Fail2ban config and start
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

# Firewall rules
echo -e "${YELLOW}Configuring firewall for Control Plane...${NC}"
ufw allow ${SSH_PORT}/tcp comment 'SSH Port'
ufw allow 80/tcp comment 'HTTP for LetsEncrypt'
ufw allow 443/tcp comment 'HTTPS'
ufw allow ${CONTROL_PLANE_UI_PORT}/tcp comment 'Control Plane UI'
ufw allow 2377/tcp comment 'Docker Swarm Management'
ufw allow 7946/tcp comment 'Swarm node discovery'
ufw allow 7946/udp comment 'Swarm node discovery'
ufw allow 4789/udp comment 'Swarm overlay network'
ufw allow out 443/tcp comment 'HTTPS outbound for GitLab'
ufw allow ${PROMETHEUS_PORT}/tcp comment 'Prometheus'
ufw allow ${GRAFANA_PORT}/tcp comment 'Grafana'
ufw deny 2375/tcp comment 'Block Docker API (unencrypted)'
ufw deny 2376/tcp comment 'Block Docker API (TLS)'
ufw reload
ufw --force enable

# Dokploy directory
echo -e "${YELLOW}Setting up Dokploy directory...${NC}"
mkdir -p /etc/dokploy
chown ${USERNAME}:${USERNAME} /etc/dokploy
chmod 775 /etc/dokploy

# SSH directory permissions
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.ssh
chmod 700 /home/${USERNAME}/.ssh
chmod 600 /home/${USERNAME}/.ssh/authorized_keys

# Docker permissions
mkdir -p /home/${USERNAME}/.docker
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.docker
chmod 700 /home/${USERNAME}/.docker
echo "export DOCKER_CONFIG=\"/home/${USERNAME}/.docker\"" >> /home/${USERNAME}/.bashrc

# Verify Docker access and Compose (assumes 2-server-bootstrap.sh installed Docker)
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

# Install Dokploy (it handles swarm init internally)
echo -e "${YELLOW}Installing Dokploy...${NC}"
curl -sSL https://dokploy.com/install.sh | sh

# Wait for Dokploy to be ready
echo -e "${YELLOW}Waiting for Dokploy to start...${NC}"
for i in {1..60}; do
    if curl -s "http://localhost:${CONTROL_PLANE_UI_PORT}" >/dev/null 2>&1; then
        echo -e "${GREEN}Dokploy is ready!${NC}"
        break
    fi
    sleep 2
done

# Get swarm token and show CORRECT join command with public IP
# (Dokploy may output internal IP which won't work for external workers)
SWARM_TOKEN=$(docker swarm join-token worker -q 2>/dev/null || echo "")
if [ -n "$SWARM_TOKEN" ]; then
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${GREEN}To add workers, run this on worker nodes:${NC}"
    echo -e "${BLUE}docker swarm join --token ${SWARM_TOKEN} ${CONTROL_PLANE_IP}:2377${NC}"
    echo -e "${YELLOW}========================================${NC}"
fi

echo -e "${GREEN}✅ Control Plane configuration completed successfully!${NC}"
echo -e "${BLUE}Access Dokploy at: http://${CONTROL_PLANE_IP}:${CONTROL_PLANE_UI_PORT}${NC}"
