#!/bin/bash

# Server Initial Setup Script (combined 1-init + 2-init)
# Complete initial security hardening for Ubuntu 24.04 LTS
# Run as root: sudo bash 1-init.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔧 Starting complete server initial setup...${NC}"

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
    SSH_MAX_AUTH_TRIES=${SSH_MAX_AUTH_TRIES:-"6"}
    SSH_CLIENT_ALIVE_INTERVAL=${SSH_CLIENT_ALIVE_INTERVAL:-"0"}
    SSH_CLIENT_ALIVE_COUNT_MAX=${SSH_CLIENT_ALIVE_COUNT_MAX:-"3"}
    SSH_MAX_STARTUPS=${SSH_MAX_STARTUPS:-"10"}
    SSH_LOGIN_GRACE_TIME=${SSH_LOGIN_GRACE_TIME:-"120"}
}

# Function to validate required variables
validate_config() {
    local missing_vars=()
    
    if [ -z "$PERSONAL_SSH_KEY" ]; then
        missing_vars+=("PERSONAL_SSH_KEY")
    fi
    
    if [ -z "$CONTROL_PLANE_SSH_KEY" ]; then
        missing_vars+=("CONTROL_PLANE_SSH_KEY")
    fi
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        echo -e "${RED}❌ Missing required environment variables:${NC}"
        for var in "${missing_vars[@]}"; do
            echo -e "${RED}  - $var${NC}"
        done
        echo -e "${YELLOW}Please create a .env file based on .env.example${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Configuration validated${NC}"
}

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Please run this script as root (use sudo)${NC}"
        exit 1
    fi
}

# Function to handle errors
handle_error() {
    echo -e "${RED}❌ Error occurred during setup. Check the logs above.${NC}"
    exit 1
}

# Set error handler
trap 'handle_error' ERR

check_root
load_env
set_defaults
validate_config

echo -e "${BLUE}Configuration:${NC}"
echo -e "  Username: ${USERNAME}"
echo -e "  SSH Port: ${SSH_PORT}"
echo -e "  Fail2ban Settings: ${FAIL2BAN_MAXRETRY} retries, ${FAIL2BAN_BANTIME}s ban"

# 1. Update and upgrade system packages
echo -e "${YELLOW}Updating system packages...${NC}"
apt update && apt upgrade -y

# 2. Install essential packages for security and Docker
echo -e "${YELLOW}Installing essential packages...${NC}"
apt install -y \
    fail2ban \
    ufw \
    docker.io \
    docker-compose \
    vim \
    tree \
    htop \
    unzip \
    software-properties-common

# 3. Create user with proper configuration
echo -e "${YELLOW}Creating user '${USERNAME}'...${NC}"
if ! id "$USERNAME" &>/dev/null; then
    adduser --disabled-password --gecos "" "$USERNAME"
    echo -e "${GREEN}User '${USERNAME}' created${NC}"
else
    echo -e "${BLUE}User '${USERNAME}' already exists${NC}"
fi

# 4. Add user to required groups
echo -e "${YELLOW}Configuring user groups...${NC}"
usermod -aG users,admin,sudo,docker "$USERNAME"

# 5. Configure sudo access
echo -e "${YELLOW}Configuring sudo access...${NC}"
if [ ! -f "/etc/sudoers.d/90-${USERNAME}" ]; then
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/90-${USERNAME}"
    echo -e "${GREEN}Sudo access configured${NC}"
else
    echo -e "${BLUE}Sudo access already configured${NC}"
fi

# 6. Set user shell
chsh -s /bin/bash "$USERNAME"

# 7. Setup SSH directory and keys
echo -e "${YELLOW}Setting up SSH access...${NC}"
mkdir -p "/home/${USERNAME}/.ssh"

# Check if SSH keys already exist and are not placeholder content
if [ -f "/home/${USERNAME}/.ssh/authorized_keys" ] && ! grep -q "# SSH keys should be managed via cloud-config" "/home/${USERNAME}/.ssh/authorized_keys"; then
    echo -e "${BLUE}SSH keys already configured, skipping...${NC}"
else
    echo -e "${YELLOW}Adding SSH authorized keys...${NC}"
    cat > "/home/${USERNAME}/.ssh/authorized_keys" << EOF
# Personal key
${PERSONAL_SSH_KEY}
# Control Plane key
${CONTROL_PLANE_SSH_KEY}
EOF
    echo -e "${GREEN}SSH keys configured${NC}"
fi

# 8. Set proper SSH permissions
echo -e "${YELLOW}Setting SSH permissions...${NC}"
chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}/.ssh"
chmod 700 "/home/${USERNAME}/.ssh"
chmod 600 "/home/${USERNAME}/.ssh/authorized_keys"

# 9. Configure SSH hardening
echo -e "${YELLOW}Configuring SSH hardening...${NC}"
if [ ! -f /etc/ssh/sshd_config.d/ssh-hardening.conf ]; then
    cat > /etc/ssh/sshd_config.d/ssh-hardening.conf << EOF
PermitRootLogin no
PasswordAuthentication no
Port ${SSH_PORT}
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
MaxAuthTries ${SSH_MAX_AUTH_TRIES}
AllowTcpForwarding no
X11Forwarding no
AllowAgentForwarding no
AuthorizedKeysFile .ssh/authorized_keys
AllowUsers ${USERNAME}
Protocol 2
ClientAliveInterval ${SSH_CLIENT_ALIVE_INTERVAL}
ClientAliveCountMax ${SSH_CLIENT_ALIVE_COUNT_MAX}
MaxStartups ${SSH_MAX_STARTUPS}
LoginGraceTime ${SSH_LOGIN_GRACE_TIME}
EOF
    echo -e "${GREEN}SSH hardening configured${NC}"
else
    echo -e "${BLUE}SSH hardening already configured${NC}"
fi

# 10. Configure fail2ban
echo -e "${YELLOW}Configuring fail2ban...${NC}"
if [ ! -f /etc/fail2ban/jail.local ]; then
    cat > /etc/fail2ban/jail.local << EOF
[sshd]
enabled = true
port = ssh,${SSH_PORT}
banaction = iptables-multiport
findtime = ${FAIL2BAN_FINDTIME}
maxretry = ${FAIL2BAN_MAXRETRY}
bantime = ${FAIL2BAN_BANTIME}
EOF
    echo -e "${GREEN}Fail2ban configured${NC}"
else
    echo -e "${BLUE}Fail2ban already configured${NC}"
fi

# 11. Enable and start fail2ban
echo -e "${YELLOW}Starting fail2ban service...${NC}"
systemctl enable fail2ban
systemctl start fail2ban

# 12. Enable and start Docker
echo -e "${YELLOW}Starting Docker service...${NC}"
systemctl enable docker
systemctl start docker

# 13. Add user to docker group (redundant but ensures it's set)
usermod -aG docker "$USERNAME"

# 14. Restart SSH to apply hardening
echo -e "${YELLOW}Restarting SSH service...${NC}"
systemctl restart sshd

# 15. Create completion markers (compatible with both cloud-init and manual setup)
mkdir -p /var/lib/cloud/instance
mkdir -p /var/lib/manual-init
touch /var/lib/cloud/instance/boot-finished
touch /var/lib/manual-init/boot-finished
echo "$(date): Initial setup completed via 1-init.sh" > /var/lib/manual-init/setup.log

echo -e "${GREEN}✅ Complete server initial setup finished successfully!${NC}"
echo -e "${BLUE}Configuration Summary:${NC}"
echo -e "  ✓ User '${USERNAME}' created with sudo and docker access"
echo -e "  ✓ SSH hardened on port ${SSH_PORT} (key-only authentication)"
echo -e "  ✓ Fail2ban configured for SSH protection"
echo -e "  ✓ Docker installed and configured"
echo -e "  ✓ All essential packages installed"

echo -e "\n${BLUE}Next steps:${NC}"
echo -e "  1. SSH to server: ${YELLOW}ssh -p ${SSH_PORT} ${USERNAME}@YOUR_SERVER_IP${NC}"
echo -e "  2. Run role-specific script:"
echo -e "     - Control Plane: ${YELLOW}sudo bash X-control-plane.commands.sh${NC}"
echo -e "     - Worker: ${YELLOW}sudo bash Y-worker.commands.sh${NC}"
echo -e "  3. Test configuration: ${YELLOW}sudo bash test-server-config.sh${NC}"

echo -e "\n${RED}⚠️  IMPORTANT SECURITY NOTES:${NC}"
echo -e "${RED}⚠️  SSH is now on port ${SSH_PORT}${NC}"
echo -e "${RED}⚠️  Password authentication is disabled${NC}"
echo -e "${RED}⚠️  Only key-based authentication is allowed${NC}"
echo -e "${RED}⚠️  Ensure you can SSH before logging out!${NC}"
