#!/bin/bash

# Server Bootstrap Script
# Purpose: Install and configure Docker Engine and Docker Compose v2
# Usage: sudo bash 2-server-bootstrap.sh

set -e
export DEBIAN_FRONTEND=noninteractive

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

handle_error() {
  echo -e "${RED}❌ Error occurred during bootstrap. Check the logs above.${NC}"
  exit 1
}
trap 'handle_error' ERR

# Ensure running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root (use sudo)${NC}"
  exit 1
fi

# Load .env to get USERNAME if present
load_env() {
  local env_file=".env"
  if [ -f "$env_file" ]; then
    echo -e "${GREEN}Loading configuration from $env_file${NC}"
    set -a
    source <(grep -v '^#' "$env_file" | grep -v '^$')
    set +a
  else
    echo -e "${YELLOW}No .env found. Using defaults.${NC}"
  fi
}

set_defaults() {
  USERNAME=${USERNAME:-"ubuntu"}
}

fix_dpkg() {
  (dpkg --configure -a || true)
  (apt-get -y install -f || true)
  rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock || true
}

load_env
set_defaults

echo -e "${BLUE}🚀 Starting Server Bootstrap (Docker + Compose v2)${NC}"

# Update apt and ensure repo helpers
fix_dpkg
apt-get update -y
apt-get install -y software-properties-common curl ca-certificates gnupg unzip || true

# Ensure 'universe' repo exists (needed on some cloud images)
if ! grep -q "^deb .*ubuntu.*universe" /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null; then
  echo -e "${YELLOW}Enabling 'universe' repository...${NC}"
  add-apt-repository -y universe || true
  apt-get update || true
fi

# Install Docker Engine from Ubuntu repo (or user can switch to Docker official later)
echo -e "${YELLOW}Installing Docker Engine...${NC}"
apt-get install -y docker.io || (echo -e "${RED}Failed to install docker.io${NC}"; exit 1)

# Configure Docker daemon to use Unix socket only
echo -e "${YELLOW}Configuring Docker daemon...${NC}"
mkdir -p /etc/docker
if [ -f /etc/docker/daemon.json ]; then
  cp /etc/docker/daemon.json /etc/docker/daemon.json.backup || true
fi
cat > /etc/docker/daemon.json << 'EOF'
{
  "hosts": ["unix:///var/run/docker.sock"]
}
EOF

# Systemd override to avoid fd:// conflict
mkdir -p /etc/systemd/system/docker.service.d
cat > /etc/systemd/system/docker.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd --containerd=/run/containerd/containerd.sock
EOF

systemctl daemon-reload
systemctl enable docker
# Ensure containerd is running (required by dockerd)
systemctl enable --now containerd || true

echo -e "${YELLOW}Starting Docker service...${NC}"
if systemctl restart docker; then
  # Wait up to 30s for Docker to be responsive
  for i in {1..30}; do
    if docker info >/dev/null 2>&1; then
      echo -e "${GREEN}Docker service is responsive${NC}"
      break
    fi
    if [ "$i" -eq 30 ]; then
      echo -e "${YELLOW}Docker daemon not responsive yet; continuing.${NC}"
    fi
    sleep 1
  done
else
  echo -e "${RED}Docker failed to start. Collecting logs...${NC}"
  systemctl status docker -n 50 || true
  journalctl -xeu docker.service -n 100 --no-pager || true
  exit 1
fi

# Ensure Docker Compose v2 is available
ensure_compose_v2() {
  echo -e "${YELLOW}Ensuring Docker Compose v2 is available...${NC}"
  if docker compose version >/dev/null 2>&1; then
    echo -e "${GREEN}Compose v2 already present${NC}"
    return 0
  fi
  echo -e "${YELLOW}Attempting apt install of docker-compose-plugin...${NC}"
  if apt-get install -y docker-compose-plugin; then
    echo -e "${GREEN}docker-compose-plugin installed via apt${NC}"
    return 0
  fi
  echo -e "${YELLOW}Apt install unavailable. Falling back to manual plugin install...${NC}"
  mkdir -p /usr/local/lib/docker/cli-plugins
  VER=$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "v\K[^"]+' || echo "2.27.0")
  URL="https://github.com/docker/compose/releases/download/v${VER}/docker-compose-$(uname -s)-$(uname -m)"
  if curl -fL "$URL" -o /usr/local/lib/docker/cli-plugins/docker-compose; then
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    if docker compose version >/dev/null 2>&1; then
      echo -e "${GREEN}Docker Compose v2 installed manually${NC}"
      return 0
    fi
  fi
  echo -e "${RED}Failed to install Docker Compose v2. Please check connectivity or use Docker's official apt repo.${NC}"
  return 1
}

ensure_compose_v2 || true

# Add target user to docker group (for non-root usage)
usermod -aG docker "$USERNAME" || true

# Verify Compose v2 for the target user
echo -e "${YELLOW}Verifying Docker Compose v2 for user '${USERNAME}'...${NC}"
if su - "$USERNAME" -c "docker compose version" >/dev/null 2>&1; then
  echo -e "${GREEN}Docker Compose v2 available for user '${USERNAME}'${NC}"
else
  echo -e "${YELLOW}Compose v2 not yet accessible for '${USERNAME}'. A re-login or reboot may be required for group changes to apply.${NC}"
fi

# Create network commonly used by control-plane setup
sudo -u "$USERNAME" docker network create dokploy-network 2>/dev/null || true

echo -e "${GREEN}✅ Server Bootstrap (Docker + Compose v2) completed.${NC}"
