# Troubleshooting (Local Testing)

- **Exit 137 / OOM during tests**
  - Cause: The simulated "fresh cloud" containers perform package operations that may exceed default Docker Desktop memory.
  - Fixes:
    - Increase Docker Desktop memory to 6–8 GB.
    - Tests auto-enable `TEST_MODE=1` inside containers to skip `apt upgrade` for reliability.
    - Run only control plane tests: `make test-control-plane`.
    - Run tests on a separate VM/server instead of a laptop.

- **Port conflicts (3000/3001/9090)**
  - If you already run Dokploy/Monitoring on the host, test ports may clash.
  - Either change test ports in `test/docker-compose.test.yml` or remove the mappings and use `docker exec` only.

- **SSH test port conflicts (2277/2278)**
  - Change to unused host ports in `test/docker-compose.test.yml` (e.g., 2299/2300).

- **sudo prompts inside test containers**
  - The Makefile runs test targets as root inside containers to avoid interactive sudo.

> TODO: Optimize test resource usage further and provide an optional lightweight test profile that avoids heavy package operations.

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
- `PERSONAL_SSH_KEY`: Your personal SSH public key (can be used for both roles)
- `CONTROL_PLANE_SSH_KEY`: Control plane SSH public key (optional if same as personal)
- `CONTROL_PLANE_IP`: IP address of control plane (for workers)

### 3. One-Command Setup
```bash
# For Control Plane server
make control-plane         # Base setup + tests (does NOT install Dokploy itself)

# OR for Worker server
make worker
```

**Available Make Targets:**
- `make control-plane`: Control plane base setup + testing (firewall, Docker, users, SSH, Dokploy network). Dokploy is NOT installed by this target.
- `make worker`: Full worker setup + testing  
- `make test-control-plane`: Test control plane only
- `make test-worker`: Test worker only
- `make init-only`: Run only initial setup (1-server-hardening.sh)

### 4. Install Dokploy (after control-plane)
```bash
curl -sSL https://dokploy.com/install.sh | sh
```

Once installed, access Dokploy UI at:
- http://YOUR_SERVER_IP:3000

Notes:
- Grafana (3001) and Prometheus (9090) are not installed by default. You can deploy them via Dokploy or with your own Compose stack.

## Scripts Overview

- **`0-cloud-config.yml`**: Cloud-init configuration for supported providers (git install, repo clone, permissions)
- **`0-cloud-config.sh`**: Manual setup script for providers without cloud-init support
- **`1-server-hardening.sh`**: Base server setup (users, SSH hardening, Docker, fail2ban)
- **`2A-control-plane.commands.sh`**: Control plane preparation (users, firewall, Docker, Dokploy network, opens ports). It does not install Dokploy/monitoring.
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
curl -fsSL https://raw.githubusercontent.com/rfpdl/cloud-infra-setup/main/0-cloud-config.sh | bash

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
- **SSH access**: Ports 2277 (control-plane) and 2278 (worker)
- **Service ports**: 3000 (Dokploy), 3001 (Grafana), 9090 (Prometheus)
- **True simulation**: Tests complete workflow from blank server to production-ready