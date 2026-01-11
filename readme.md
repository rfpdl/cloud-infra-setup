# Cloud Infrastructure Setup

Automated Ubuntu 24.04 LTS server setup for Dokploy-based infrastructure with Docker Swarm.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     CONTROL PLANE                           │
│  ┌─────────────┐  ┌──────────┐  ┌─────────────────────────┐ │
│  │   Dokploy   │  │ Traefik  │  │   Docker Swarm Manager  │ │
│  │  (port 3000)│  │ (80/443) │  │       (port 2377)       │ │
│  └─────────────┘  └──────────┘  └─────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                    Docker Swarm (overlay network)
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
┌───────────────┐     ┌───────────────┐     ┌───────────────┐
│   WORKER 1    │     │   WORKER 2    │     │   WORKER N    │
│  Docker Node  │     │  Docker Node  │     │  Docker Node  │
└───────────────┘     └───────────────┘     └───────────────┘
```

## Quick Start

### Prerequisites
- Fresh Ubuntu 24.04 LTS server(s)
- SSH access with root/sudo privileges
- Your SSH public key

### Step 1: Initialize Server

**Option A: Cloud-init (Hetzner, AWS, DigitalOcean, etc.)**

When creating your server, paste the contents of `0-init.yml` into the cloud-init/user-data field.

**Option B: Manual Setup**

SSH to your server and run:
```bash
curl -fsSL https://raw.githubusercontent.com/rfpdl/cloud-infra-setup/main/0-init.sh | sudo bash
```

### Step 2: Configure Environment

```bash
# Switch to the setup user
su - ubuntu
cd server-setup

# Create your configuration
cp .env.example .env
nano .env
```

**Required settings in `.env`:**
```bash
# Your SSH public key (REQUIRED)
PERSONAL_SSH_KEY="ssh-ed25519 AAAAC3... your-email@example.com"

# For workers only: Control plane IP address
CONTROL_PLANE_IP="your.control.plane.ip"
```

### Step 3: Run Setup

**For Control Plane:**
```bash
make control-plane
```

**For Worker:**
```bash
make worker
```

### Step 4: Join Workers to Swarm

After control plane setup, you'll see a join command. Run it on each worker:

```bash
# Shown at end of control plane setup:
docker swarm join --token SWMTKN-xxx YOUR_CONTROL_PLANE_IP:2377
```

## Setup Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           SETUP PIPELINE                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  0-init.yml/sh         Clone repo, set permissions                      │
│       │                                                                 │
│       ▼                                                                 │
│  1-server-hardening    User setup, SSH hardening, fail2ban, firewall    │
│       │                                                                 │
│       ▼                                                                 │
│  2-server-bootstrap    Docker Engine + Compose v2 installation          │
│       │                                                                 │
│       ├──────────────────────────┬──────────────────────────┐          │
│       ▼                          ▼                          │          │
│  3A-control-plane           3B-worker                       │          │
│  - Dokploy install          - Locked-down firewall          │          │
│  - Swarm init               - Swarm ports to control plane  │          │
│  - Show join token          - Ready to join swarm           │          │
│       │                          │                          │          │
│       ▼                          ▼                          │          │
│  test/control-plane.test    test/worker.test                │          │
│                                                              │          │
└─────────────────────────────────────────────────────────────────────────┘
```

## Make Targets

| Target | Description |
|--------|-------------|
| `make control-plane` | Full control plane setup with Dokploy |
| `make worker` | Full worker setup (requires CONTROL_PLANE_IP) |
| `make init-only` | Run only server hardening |
| `make bootstrap-only` | Run only Docker installation |
| `make test-control-plane` | Test control plane configuration |
| `make test-worker` | Test worker configuration |
| `make test` | Run Docker-based integration tests |
| `make test-cleanup` | Clean up test containers |

## Configuration Reference

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `USERNAME` | ubuntu | Linux username to create |
| `SSH_PORT` | 22 | SSH port |
| `PERSONAL_SSH_KEY` | - | Your SSH public key (required) |
| `CONTROL_PLANE_SSH_KEY` | - | Separate key for control plane (optional) |
| `CONTROL_PLANE_IP` | auto-detect | Control plane IP (required for workers) |
| `CONTROL_PLANE_UI_PORT` | 3000 | Dokploy UI port |
| `FAIL2BAN_MAXRETRY` | 3 | Failed attempts before ban |
| `FAIL2BAN_BANTIME` | 3600 | Ban duration in seconds |

See `.env.example` for full list with documentation.

## Security Features

- **SSH Hardening**: Key-only auth, root login disabled, configurable port
- **Fail2ban**: Brute-force protection with secure defaults
- **UFW Firewall**: Role-specific rules (control plane open, workers locked down)
- **Docker Security**: Unix socket only, no TCP API exposure
- **Input Validation**: All config values validated before use
- **Secure Defaults**: Stronger fail2ban settings, shorter SSH timeouts

### Firewall Rules

**Control Plane:**
- SSH (configurable port)
- HTTP/HTTPS (80, 443)
- Dokploy UI (3000)
- Docker Swarm (2377, 7946, 4789)
- Prometheus (9090), Grafana (3001) - optional

**Worker:**
- SSH (configurable port)
- Docker Swarm ports **restricted to control plane IP only**

## File Structure

```
cloud-infra-setup/
├── 0-init.yml                  # Cloud-init configuration
├── 0-init.sh                   # Manual initialization script
├── 1-server-hardening.sh       # Security hardening
├── 2-server-bootstrap.sh       # Docker + Compose installation
├── 3A-control-plane.commands.sh # Control plane setup + Dokploy
├── 3B-worker.commands.sh       # Worker setup
├── lib/
│   └── common.sh               # Shared functions and validation
├── test/
│   ├── control-plane.test.sh   # Control plane tests
│   ├── worker.test.sh          # Worker tests
│   └── docker-compose.test.yml # Integration test containers
├── .env.example                # Configuration template
├── Makefile                    # Build automation
└── readme.md                   # This file
```

## Troubleshooting

### SSH Connection Refused
```bash
# Check if SSH is running on the correct port
ssh -p YOUR_SSH_PORT user@server

# Verify your SSH key is correct
cat ~/.ssh/id_rsa.pub  # Compare with PERSONAL_SSH_KEY in .env
```

### Docker Permission Denied
```bash
# Re-login to apply group changes
exit
ssh user@server

# Or use sudo
sudo docker ps
```

### Swarm Join Fails with Wrong IP
The control plane script outputs the correct join command with public IP. If you see an internal IP (172.x.x.x), use this instead:

```bash
# Get the token
docker swarm join-token worker -q

# Join with correct IP
docker swarm join --token TOKEN YOUR_CONTROL_PLANE_PUBLIC_IP:2377
```

### Test Failures
```bash
# Run tests manually with verbose output
sudo bash test/worker.test.sh

# Check specific service status
systemctl status fail2ban
systemctl status docker
ufw status verbose
```

## Development

### Running Integration Tests

```bash
# Start test containers (simulates fresh cloud servers)
make test

# Access test containers
docker exec -it fresh-control-plane bash
docker exec -it fresh-worker bash

# Cleanup
make test-cleanup
```

### Adding New Validation

Add functions to `lib/common.sh`:
```bash
validate_my_param() {
    local value="$1"
    # Return 0 for valid, 1 for invalid
    [[ "$value" =~ ^[a-z]+$ ]] && return 0 || return 1
}
```

## License

MIT
