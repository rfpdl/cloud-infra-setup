# Cloud Infra Setup

Automated Ubuntu 24.04 LTS server configuration for Cloud Provider cloud infrastructure with Control Plane (Dokploy + Grafana + Prometheus + GitLab Runner) and Worker nodes.

## Quick Start

### 1. Deployment

**Option A: Cloud Providers with cloud-init support (Hetzner, AWS, DigitalOcean, etc.)**
Use `0-cloud-config.yml` when creating your server. This will:
- Install git and essential packages
- Clone this repository to `/home/ubuntu/server-setup`
- Set proper permissions on scripts

**Option B: Cloud Providers without cloud-init or manual setup**
SSH to your fresh Ubuntu 24.04 LTS server and run:
```bash
curl -fsSL https://raw.githubusercontent.com/rfpdl/cloud-infra-setup/main/0-cloud-config.sh | sudo bash
```

### 2. Configure Environment
```bash
# If you used Option A (cloud-init), SSH first:
ssh ubuntu@YOUR_SERVER_IP

# For both options, configure your environment:
cd server-setup
cp .env.example .env
vim .env  # Add your SSH keys and configuration
```

**Required Variables:**
- `PERSONAL_SSH_KEY`: Your personal SSH public key
- `CONTROL_PLANE_SSH_KEY`: Control plane SSH public key
- `CONTROL_PLANE_IP`: IP address of control plane (for workers)

### 3. One-Command Setup
```bash
# For Control Plane server
make control-plane

# OR for Worker server
make worker
```

**Available Make Targets:**
- `make control-plane`: Full control plane setup + testing
- `make worker`: Full worker setup + testing  
- `make test-control-plane`: Test control plane only
- `make test-worker`: Test worker only
- `make init-only`: Run initial setup only

## Scripts Overview

- **`0-cloud-config.yml`**: Cloud-init configuration for supported providers (git install, repo clone, permissions)
- **`0-cloud-config.sh`**: Manual setup script for providers without cloud-init support
- **`1-server-hardening.sh`**: Base server setup (users, SSH hardening, Docker, fail2ban)
- **`2A-control-plane.commands.sh`**: Control plane configuration (Dokploy, Grafana, Prometheus)
- **`2B-worker.commands.sh`**: Worker configuration (Docker Swarm worker)
- **`3A-control-plane-test.sh`**: Control plane configuration testing
- **`3B-worker-test.sh`**: Worker configuration testing

## Configuration

All scripts use environment variables from `.env` file with sensible defaults:

- **Username**: `ubuntu` (standard cloud default)
- **SSH Port**: `22` (standard, customize for security)
- **Service Ports**: Dokploy (3000), Grafana (3001), Prometheus (9090)
- **Security**: Standard OpenSSH and fail2ban settings

## Architecture

- **Control Plane**: Dokploy + Monitoring + GitLab Runner
- **Workers**: Docker Swarm nodes for application deployment
- **Security**: SSH key-only auth, fail2ban, UFW firewall
- **Networking**: Docker Swarm overlay networks

## Security Features

- SSH hardening (key-only auth, custom ports)
- Fail2ban intrusion prevention
- UFW firewall with role-specific rules
- Worker nodes locked down to control plane IP only

## Testing & Development

Test your setup locally using Docker containers that simulate fresh cloud provider installations:

### Quick Test
```bash
# Test both control-plane and worker setups (simulates real cloud deployment)
make test

# Clean up test environment
make test-cleanup
```

### Manual Testing
```bash
# Start fresh cloud simulation containers
docker-compose -f test/docker-compose.test.yml up -d

# Access fresh control plane container (starts as root, like real cloud servers)
docker exec -it fresh-control-plane bash

# Access fresh worker container
docker exec -it fresh-worker bash

# Test the complete workflow manually:
# 1. Run cloud-config script (simulates cloud provider setup)
curl -fsSL https://raw.githubusercontent.com/rfpdl/cloud-infra-bootstrap/main/0-cloud-config.sh | bash

# 2. Switch to ubuntu user and configure
su - ubuntu
cd server-setup
cp .env.example .env
vim .env  # Add your SSH keys

# 3. Run setup
make control-plane  # or make worker
```

**Fresh Test Environment Features:**
- **Bare Ubuntu 24.04 LTS**: No pre-installed packages (like real cloud providers)
- **Fresh networking**: Control-plane (172.21.0.10), Worker (172.21.0.11)
- **SSH access**: Ports 2230 (control-plane) and 2231 (worker)
- **Service ports**: 3010 (Dokploy), 3011 (Grafana), 9091 (Prometheus)
- **True simulation**: Tests complete workflow from blank server to production-ready