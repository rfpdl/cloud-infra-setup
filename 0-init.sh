#!/bin/bash

# 0-init.sh
# Purpose: Minimal initialization for servers without cloud-init support.
# - Installs basic tooling (git, make, curl, wget, unzip, vim)
# - Optionally sets the ubuntu user's SSH authorized_keys (see below)
# - Clones this repository to /home/ubuntu/server-setup
# - Sets permissions
# Next steps (run manually after SSH):
#   1) sudo bash 1-server-hardening.sh
#   2) sudo bash 2-server-bootstrap.sh
#   3) sudo bash 3A-control-plane.commands.sh OR sudo bash 3B-worker.commands.sh
#   4) sudo bash test/control-plane.test.sh OR sudo bash test/worker.test.sh

set -e
export DEBIAN_FRONTEND=noninteractive

# Handle interrupted dpkg/apt states gracefully
fix_dpkg() {
    (dpkg --configure -a || true)
    (apt-get -y install -f || true)
    rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock || true
}

# Auto-enable TEST_MODE when running inside a container (e.g., make test)
if [ -z "${TEST_MODE:-}" ]; then
    if [ -f "/.dockerenv" ] || grep -qa docker /proc/1/cgroup 2>/dev/null; then
        export TEST_MODE=1
        echo "[TEST_MODE] Detected container environment. Running in TEST_MODE=1 (skip apt upgrade)."
    fi
fi

echo "Starting minimal initialization (0-init.sh)..."

# Update system packages (leaner in TEST_MODE)
fix_dpkg
apt-get update
if [ "${TEST_MODE:-}" != "1" ]; then
    apt-get upgrade -y
fi

# Install required minimal packages only (security/Docker handled later)
apt-get install -y git curl wget unzip vim make

# Ensure ubuntu user exists
if ! id "ubuntu" &>/dev/null; then
    useradd -m -s /bin/bash ubuntu
    usermod -aG sudo ubuntu
    echo "ubuntu ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
fi

# Minimal SSH hardening to block password auth (avoid port changes here)
echo "Applying minimal SSH hardening..."
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/99-init.conf << 'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
EOF
systemctl restart ssh || systemctl restart sshd || true

# Optionally set SSH public key for ubuntu user
# Priority: 1) first script argument 2) $SSH_PUBLIC_KEY 3) $PERSONAL_SSH_KEY
SSH_KEY_INPUT="${1:-${SSH_PUBLIC_KEY:-${PERSONAL_SSH_KEY:-}}}"
if [ -n "$SSH_KEY_INPUT" ]; then
    echo "Configuring SSH authorized_keys for ubuntu user..."
    mkdir -p /home/ubuntu/.ssh
    {
        echo "# Added by 0-init.sh"
        echo "$SSH_KEY_INPUT"
    } > /home/ubuntu/.ssh/authorized_keys
    chown -R ubuntu:ubuntu /home/ubuntu/.ssh
    chmod 700 /home/ubuntu/.ssh
    chmod 600 /home/ubuntu/.ssh/authorized_keys
else
    echo "No SSH key provided to 0-init.sh. You can set it by rerunning with:"
    echo "  SSH_PUBLIC_KEY=\"ssh-...\" sudo bash 0-init.sh"
    echo "or pass the key as the first argument:"
    echo "  sudo bash 0-init.sh \"ssh-...\""
fi

# Clone the server setup repository
cd /home/ubuntu
if [ -d "server-setup" ]; then
    echo "Repository already exists, pulling latest changes..."
    cd server-setup && git pull && cd - >/dev/null
else
    echo "Cloning server setup repository..."
    git clone https://github.com/rfpdl/cloud-infra-setup.git server-setup
fi

# Set proper ownership and permissions
chown -R ubuntu:ubuntu /home/ubuntu/server-setup
chmod +x /home/ubuntu/server-setup/*.sh || true

# Fallback: if no SSH key was applied earlier, try to read from repo .env
if [ ! -s /home/ubuntu/.ssh/authorized_keys ] && [ -f /home/ubuntu/server-setup/.env ]; then
    echo "Attempting to load SSH key from /home/ubuntu/server-setup/.env..."
    set -a
    # shellcheck disable=SC1091
    source <(grep -v '^#' /home/ubuntu/server-setup/.env | grep -v '^$') || true
    set +a
    ENV_SSH_KEY="${SSH_PUBLIC_KEY:-${PERSONAL_SSH_KEY:-}}"
    if [ -n "$ENV_SSH_KEY" ]; then
        mkdir -p /home/ubuntu/.ssh
        {
            echo "# Added by 0-init.sh from .env"
            echo "$ENV_SSH_KEY"
        } > /home/ubuntu/.ssh/authorized_keys
        chown -R ubuntu:ubuntu /home/ubuntu/.ssh
        chmod 700 /home/ubuntu/.ssh
        chmod 600 /home/ubuntu/.ssh/authorized_keys
        echo "SSH key installed from .env"
    else
        echo "No SSH_PUBLIC_KEY or PERSONAL_SSH_KEY found in .env"
    fi
fi

# Create completion marker
mkdir -p /var/lib/cloud/instance
touch /var/lib/cloud/instance/cloud-config-finished

echo "=========================================="
echo "Server setup repository is at /home/ubuntu/server-setup"
echo "Next steps:"
echo "1. SSH as ubuntu: sudo su - ubuntu"
echo "2. cd server-setup"
echo "3. cp .env.example .env && vim .env"
echo "4. make control-plane   # or: make worker"
echo "=========================================="

echo "0-init.sh completed successfully!"
