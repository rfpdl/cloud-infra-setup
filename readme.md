# Cloud Infra Setup

Automated Ubuntu 24.04 LTS server configuration for Cloud Provider cloud infrastructure with Control Plane (Dokploy + Grafana + Prometheus + GitLab Runner) and Worker nodes.

## Quick Start

### 1. Deployment

**Option A: Cloud Providers with cloud-init support (Hetzner, AWS, DigitalOcean, etc.)**
Use `0-init.yml` when creating your server. This will:
- Install git and essential packages
- Clone this repository to `/home/ubuntu/server-setup`
- Set proper permissions on scripts

**Option B: Cloud Providers without cloud-init or manual setup**
SSH to your fresh Ubuntu 24.04 LTS server and run:
```bash
curl -fsSL https://raw.githubusercontent.com/rfpdl/cloud-infra-setup/main/0-init.sh | sudo bash
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
- `make control-plane`: Hardening -> Bootstrap (Docker+Compose v2) -> Control Plane config -> Tests
- `make worker`: Hardening -> Bootstrap (Docker+Compose v2) -> Worker config -> Tests  
- `make test-control-plane`: Test control plane only (`test/control-plane.test.sh`)
- `make test-worker`: Test worker only (`test/worker.test.sh`)
- `make init-only`: Run only initial hardening (no Docker)
- `make bootstrap-only`: Run only Docker/Compose v2 bootstrap

### 4. Install Dokploy (after control-plane)
```bash
curl -sSL https://dokploy.com/install.sh | sh
```

Once installed, access Dokploy UI at:
- http://YOUR_SERVER_IP:3000

Notes:
- Grafana (3001) and Prometheus (9090) are not installed by default. You can deploy them via Dokploy or with your own Compose stack.

## Docker Swarm (Multi‑Server Setup)

Use these steps when your Control Plane and Worker(s) are on different servers.

1) Control Plane setup

- Run on the control plane host:
  - `make control-plane`
  - Install Dokploy (optional step can be done later):
    - `curl -sSL https://dokploy.com/install.sh | sh`

2) Worker setup

- On each worker host:
  - Set `CONTROL_PLANE_IP` in `.env` to the control plane server IP
  - Run: `make worker`

3) Initialize Swarm on Control Plane

- On the control plane host, initialize Docker Swarm (if not already initialized):
```bash
docker swarm init --advertise-addr <CONTROL_PLANE_IP>
```

4) Join Workers to Swarm

- Get the worker join command on the control plane:
```bash
docker swarm join-token worker
```
- Run the printed `docker swarm join ...` command on each worker.

5) Verify the Swarm cluster (run on control plane)
```bash
docker node ls
```
All workers should appear as Ready/Active.

6) Deploying from Dokploy

- Dokploy should be installed on the control plane (Swarm manager) and have the Docker socket mounted:
  - Mount `-v /var/run/docker.sock:/var/run/docker.sock` if running Dokploy via Docker.
- Deploy stacks from the control plane (manager). For Swarm apps, prefer `docker stack deploy` semantics via Dokploy.

7) Required ports (already handled by scripts)

- Control Plane (open to workers):
  - 2377/tcp (Swarm management)
  - 7946/tcp, 7946/udp (node discovery)
  - 4789/udp (overlay network)
- Workers: the worker script (`2B-worker.commands.sh`) restricts these to `CONTROL_PLANE_IP` via UFW.

8) Compose v2 note

- Ensure `docker compose` (Compose v2) is available on the control plane. If missing, install `docker-compose-plugin` or use Docker’s official apt repository.
- Our scripts fall back to legacy `docker-compose` where possible, but Dokploy typically expects Compose v2.

9) Troubleshooting

- If deployments from Dokploy fail with generic Docker help output, check:
  - `docker compose version || docker-compose --version`
  - `docker ps` (within Dokploy container if applicable) to confirm socket access
  - `docker node ls` on the control plane to confirm manager role and worker readiness
- Verify no conflicting DOCKER_* environment variables are set in Dokploy’s environment unless intentionally using a remote Docker context.

## Scripts Overview

- **`0-init.yml`**: Cloud-init minimal initialization (git, basic tools, clone repo)
- **`0-init.sh`**: Manual minimal initialization (for providers without cloud-init)
- **`1-server-hardening.sh`**: Security hardening (users, SSH keys/hardening, fail2ban, UFW) — no Docker
- **`2-server-bootstrap.sh`**: Docker Engine + Compose v2 installation/configuration and readiness
- **`3A-control-plane.commands.sh`**: Control plane configuration (firewall, Dokploy directory, swarm ports)
- **`3B-worker.commands.sh`**: Worker configuration (locked-down firewall to control plane, swarm ports)
- **`test/control-plane.test.sh`**: Control plane configuration test suite
- **`test/worker.test.sh`**: Worker configuration test suite

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
# 1. Run minimal init script (simulates cloud provider setup)
curl -fsSL https://raw.githubusercontent.com/rfpdl/cloud-infra-setup/main/0-init.sh | bash

# 2. Switch to ubuntu user and configure
su - ubuntu
cd server-setup
cp .env.example .env
vim .env  # Add your SSH keys

# 3. Run setup
make control-plane  # or make worker

## One-liners

Control Plane (from a fresh server):
```bash
curl -fsSL https://raw.githubusercontent.com/rfpdl/cloud-infra-setup/main/0-init.sh | sudo bash && cd /home/ubuntu/server-setup && sudo bash 1-server-hardening.sh && sudo bash 2-server-bootstrap.sh && sudo bash 3A-control-plane.commands.sh && sudo bash test/control-plane.test.sh
```

Worker (from a fresh server):
```bash
curl -fsSL https://raw.githubusercontent.com/rfpdl/cloud-infra-setup/main/0-init.sh | sudo bash && cd /home/ubuntu/server-setup && sudo bash 1-server-hardening.sh && sudo bash 2-server-bootstrap.sh && sudo bash 3B-worker.commands.sh && sudo bash test/worker.test.sh
```
```

**Fresh Test Environment Features:**
- **Bare Ubuntu 24.04 LTS**: No pre-installed packages (like real cloud providers)
- **Fresh networking**: Control-plane (172.21.0.10), Worker (172.21.0.11)
- **SSH access**: Ports 2277 (control-plane) and 2278 (worker)
- **Service ports**: 3000 (Dokploy), 3001 (Grafana), 9090 (Prometheus)
- **True simulation**: Tests complete workflow from blank server to production-ready

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
