#!/bin/bash

# Control Plane Configuration Script
# Run after 1-server-hardening.sh to configure Dokploy control plane

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to load environment variables
load_env() {
    local env_file=".env"
    if [ -f "$env_file" ]; then
        echo -e "${GREEN}Loading configuration from $env_file${NC}"
        # Source the .env file, ignoring comments and empty lines
        set -a
        source <(grep -v '^#' "$env_file" | grep -v '^$')
        set +a
    else
        echo -e "${YELLOW}No .env file found, using default values${NC}"
        echo -e "${BLUE}To customize configuration, copy .env.example to .env${NC}"
    fi
}

# Function to set default values
set_defaults() {
    USERNAME=${USERNAME:-"ubuntu"}
    SSH_PORT=${SSH_PORT:-"22"}
    FAIL2BAN_FINDTIME=${FAIL2BAN_FINDTIME:-"600"}
    FAIL2BAN_MAXRETRY=${FAIL2BAN_MAXRETRY:-"5"}
    FAIL2BAN_BANTIME=${FAIL2BAN_BANTIME:-"600"}
    CONTROL_PLANE_UI_PORT=${CONTROL_PLANE_UI_PORT:-"3000"}
    PROMETHEUS_PORT=${PROMETHEUS_PORT:-"9090"}
    GRAFANA_PORT=${GRAFANA_PORT:-"3001"}
}

# Load configuration
load_env
set_defaults

echo -e "${BLUE}🚀 Starting Control Plane Configuration${NC}"
echo -e "${BLUE}User: ${USERNAME}, SSH Port: ${SSH_PORT}${NC}"

# 7. Configure and enable fail2ban
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
echo -e "${GREEN}Fail2ban configured and started${NC}"

# 8. Configure the firewall (UFW) - CONTROL PLANE RULES
echo -e "${YELLOW}Configuring firewall for Control Plane...${NC}"
ufw allow ${SSH_PORT}/tcp comment 'SSH Port'
ufw allow 80/tcp comment 'HTTP for LetsEncrypt'
ufw allow 443/tcp comment 'HTTPS'
ufw allow ${CONTROL_PLANE_UI_PORT}/tcp comment 'Control Plane UI'
# Docker Swarm ports - open for worker nodes to connect
ufw allow 2377/tcp comment 'Docker Swarm Management'
ufw allow 7946/tcp comment 'Swarm node discovery'
ufw allow 7946/udp comment 'Swarm node discovery'
ufw allow 4789/udp comment 'Swarm overlay network'
# GitLab Runner registration (if needed)
ufw allow out 443/tcp comment 'HTTPS outbound for GitLab'
# Grafana monitoring ports
ufw allow ${PROMETHEUS_PORT}/tcp comment 'Prometheus'
ufw allow ${GRAFANA_PORT}/tcp comment 'Grafana'
ufw reload
ufw --force enable
echo -e "${GREEN}Firewall configured for Control Plane${NC}"

# 9. Enable and start Docker
echo -e "${YELLOW}Starting Docker service...${NC}"
systemctl enable docker
systemctl start docker
echo -e "${GREEN}Docker service started${NC}"

# 10. Create the /etc/dokploy directory and set permissions
echo -e "${YELLOW}Setting up Dokploy directory...${NC}"
mkdir -p /etc/dokploy
chown ${USERNAME}:${USERNAME} /etc/dokploy
chmod 775 /etc/dokploy
echo -e "${GREEN}Dokploy directory configured${NC}"

# 11. Ensure the user's .ssh directory has correct permissions
echo -e "${YELLOW}Setting SSH directory permissions...${NC}"
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.ssh
chmod 700 /home/${USERNAME}/.ssh
chmod 600 /home/${USERNAME}/.ssh/authorized_keys
echo -e "${GREEN}SSH permissions configured${NC}"

# 12. Fix Docker permissions for the user
echo -e "${YELLOW}Configuring Docker permissions...${NC}"
mkdir -p /home/${USERNAME}/.docker
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.docker
chmod 700 /home/${USERNAME}/.docker
echo "export DOCKER_CONFIG=\"/home/${USERNAME}/.docker\"" >> /home/${USERNAME}/.bashrc
echo "export DOCKER_CONFIG=\"/home/${USERNAME}/.docker\"" >> /etc/environment
echo -e "${GREEN}Docker permissions configured${NC}"

# 13. Initialize Docker for the user and test
echo -e "${YELLOW}Testing Docker access...${NC}"
sudo -u ${USERNAME} env DOCKER_CONFIG="/home/${USERNAME}/.docker" docker ps 2>/dev/null || true
sudo -u ${USERNAME} env DOCKER_CONFIG="/home/${USERNAME}/.docker" docker compose version
echo -e "${GREEN}Docker access verified${NC}"

# 14. Create the docker network
echo -e "${YELLOW}Creating Dokploy network...${NC}"
sudo -u ${USERNAME} docker network create dokploy-network 2>/dev/null || true
echo -e "${GREEN}Dokploy network ready${NC}"

# 15. Configuration complete
echo -e "${GREEN}✅ Control Plane configuration completed successfully!${NC}"
echo -e "${BLUE}Configuration Summary:${NC}"
echo -e "  ✓ Fail2ban configured for SSH protection"
echo -e "  ✓ Firewall configured for Control Plane services"
echo -e "  ✓ Docker configured for user '${USERNAME}'"
echo -e "  ✓ Dokploy directory and network ready"
echo -e "  ✓ SSH permissions secured"

echo -e "\n${BLUE}Next steps:${NC}"
echo -e "  1. Install Dokploy: ${YELLOW}curl -sSL https://dokploy.com/install.sh | sh${NC}"
echo -e "  2. Access Control Plane UI: ${YELLOW}http://YOUR_SERVER_IP:${CONTROL_PLANE_UI_PORT}${NC}"
echo -e "  3. Configure Grafana: ${YELLOW}http://YOUR_SERVER_IP:${GRAFANA_PORT}${NC}"
echo -e "  4. Configure Prometheus: ${YELLOW}http://YOUR_SERVER_IP:${PROMETHEUS_PORT}${NC}"

echo -e "\n${YELLOW}⚠️  Consider rebooting to ensure all changes take effect${NC}"
echo -e "${YELLOW}⚠️  Run: sudo reboot${NC}"