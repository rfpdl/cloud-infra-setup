#!/bin/bash

# Worker Configuration Script
# Run after 1-server-hardening.sh to configure Docker Swarm worker

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
    CONTROL_PLANE_IP=${CONTROL_PLANE_IP:-""}
}

# Function to validate required variables
validate_config() {
    if [ -z "$CONTROL_PLANE_IP" ]; then
        echo -e "${RED}ERROR: CONTROL_PLANE_IP is required for worker configuration${NC}"
        echo -e "${YELLOW}Please set CONTROL_PLANE_IP in your .env file${NC}"
        exit 1
    fi
}

# Load configuration
load_env
set_defaults
validate_config

echo -e "${BLUE}🔧 Starting Worker Configuration${NC}"
echo -e "${BLUE}User: ${USERNAME}, SSH Port: ${SSH_PORT}${NC}"
echo -e "${BLUE}Control Plane IP: ${CONTROL_PLANE_IP}${NC}"

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

# 8. Configure the firewall (UFW) - WORKER RULES (LOCKED DOWN)
echo -e "${YELLOW}Configuring firewall for Worker (locked down)...${NC}"

ufw allow ${SSH_PORT}/tcp comment 'SSH Port'
# STRICT: Only allow Docker Swarm traffic from control plane
ufw allow from $CONTROL_PLANE_IP to any port 2377 proto tcp comment 'Swarm Management'
ufw allow from $CONTROL_PLANE_IP to any port 7946 proto tcp comment 'Swarm Discovery TCP'
ufw allow from $CONTROL_PLANE_IP to any port 7946 proto udp comment 'Swarm Discovery UDP'
ufw allow from $CONTROL_PLANE_IP to any port 4789 proto udp comment 'Overlay Network'
# Allow outbound connections for Docker registry access
ufw allow out 443/tcp comment 'HTTPS outbound'
ufw allow out 80/tcp comment 'HTTP outbound'

ufw reload
ufw --force enable
echo -e "${GREEN}Firewall configured for Worker (restricted to ${CONTROL_PLANE_IP})${NC}"

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
echo -e "${GREEN}✅ Worker configuration completed successfully!${NC}"
echo -e "${BLUE}Configuration Summary:${NC}"
echo -e "  ✓ Fail2ban configured for SSH protection"
echo -e "  ✓ Firewall configured for Worker (restricted to ${CONTROL_PLANE_IP})"
echo -e "  ✓ Docker configured for user '${USERNAME}'"
echo -e "  ✓ Dokploy directory and network ready"
echo -e "  ✓ SSH permissions secured"

echo -e "\n${BLUE}Next steps:${NC}"
echo -e "  1. Join Docker Swarm from Control Plane:"
echo -e "     ${YELLOW}docker swarm join-token worker${NC}"
echo -e "  2. Run the join command on this worker"
echo -e "  3. Deploy Zventy Laravel app from Control Plane"

echo -e "\n${YELLOW}⚠️  Consider rebooting to ensure all changes take effect${NC}"
echo -e "${YELLOW}⚠️  Run: sudo reboot${NC}"