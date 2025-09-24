#!/bin/bash

# Cloud Config Script for Providers without cloud-init support
# Run this script on a fresh Ubuntu 24.04 LTS server after initial login

set -e

echo "Starting cloud-config equivalent setup..."

# Update system packages
apt-get update
apt-get upgrade -y

# Install required packages
apt-get install -y git curl wget unzip vim

# Create ubuntu user if it doesn't exist (some providers use different default users)
if ! id "ubuntu" &>/dev/null; then
    useradd -m -s /bin/bash ubuntu
    usermod -aG sudo ubuntu
    echo "ubuntu ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
fi

# Switch to ubuntu user home directory
cd /home/ubuntu

# Clone the server setup repository
if [ -d "server-setup" ]; then
    echo "Repository already exists, pulling latest changes..."
    cd server-setup
    git pull
    cd ..
else
    echo "Cloning server setup repository..."
    git clone https://github.com/rfpdl/cloud-infra-setup.git server-setup
fi

# Set proper ownership and permissions
chown -R ubuntu:ubuntu /home/ubuntu/server-setup
chmod +x /home/ubuntu/server-setup/*.sh

# Create completion marker
mkdir -p /var/lib/cloud/instance
touch /var/lib/cloud/instance/cloud-config-finished
echo "$(date): Cloud-config script completed - server-setup repo cloned" > /var/log/cloud-config-setup.log

echo "=========================================="
echo "Server setup repository has been cloned to /home/ubuntu/server-setup"
echo ""
echo "Next steps:"
echo "1. Switch to ubuntu user: sudo su - ubuntu"
echo "2. cd server-setup"
echo "3. cp .env.example .env && vim .env"
echo "4. make control-plane (or make worker)"
echo "=========================================="

echo "Setup completed successfully!"
