# Cloud Infrastructure Setup Makefile
# Usage: make control-plane OR make worker OR make test

.PHONY: control-plane worker test-control-plane test-worker init-only test test-cleanup help

# Default target
help:
	@echo "Cloud Infrastructure Setup"
	@echo "===================="
	@echo ""
	@echo "Available targets:"
	@echo "  control-plane    - Setup control plane (Dokploy + Monitoring)"
	@echo "  worker          - Setup worker node (Docker Swarm)"
	@echo "  test-control-plane - Test control plane configuration"
	@echo "  test-worker     - Test worker configuration"
	@echo "  init-only       - Run only initial setup (1-server-hardening.sh)"
	@echo "  test            - Run fresh cloud provider simulation tests"
	@echo "  test-cleanup    - Clean up test environment"
	@echo "  help            - Show this help message"
	@echo ""
	@echo "Prerequisites:"
	@echo "  1. Create .env file: cp .env.example .env"
	@echo "  2. Edit .env with your SSH keys and configuration"
	@echo ""

# Check if .env file exists
check-env:
	@if [ ! -f .env ]; then \
		echo "❌ Error: .env file not found"; \
		echo "Please run: cp .env.example .env && vim .env"; \
		exit 1; \
	fi
	@echo "✓ .env file found"

# Control Plane setup
control-plane: check-env
	@echo "🚀 Setting up Control Plane..."
	sudo bash 1-server-hardening.sh
	sudo bash 2A-control-plane.commands.sh
	sudo bash 3A-control-plane-test.sh
	@echo "✅ Control Plane setup complete!"

# Worker setup  
worker: check-env
	@echo "🔧 Setting up Worker..."
	sudo bash 1-server-hardening.sh
	sudo bash 2B-worker.commands.sh
	sudo bash 3B-worker-test.sh
	@echo "✅ Worker setup complete!"

# Test only targets
test-control-plane: check-env
	@echo "🧪 Testing Control Plane configuration..."
	sudo bash 3A-control-plane-test.sh

test-worker: check-env
	@echo "🧪 Testing Worker configuration..."
	sudo bash 3B-worker-test.sh

# Initial setup only
init-only: check-env
	@echo "⚙️ Running initial setup only..."
	sudo bash 1-server-hardening.sh
	@echo "✅ Initial setup complete!"

# Testing targets
test:
	@echo "🧪 Running fresh cloud provider simulation tests..."
	@docker-compose -f test/docker-compose.test.yml up -d
	@sleep 20
	@echo "Testing Control Plane..."
	@docker exec fresh-control-plane bash -c "cp /root/server-setup/0-cloud-config.sh /root/ && cd /root && bash 0-cloud-config.sh"
	@docker exec fresh-control-plane bash -c "su - ubuntu -c 'cd server-setup && cp .env.example .env && echo \"PERSONAL_SSH_KEY=\\\"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7test ubuntu@test\\\"\" >> .env && echo \"CONTROL_PLANE_SSH_KEY=\\\"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7test ubuntu@test\\\"\" >> .env'"
	@docker exec fresh-control-plane bash -lc "cd /home/ubuntu/server-setup && make control-plane"
	@echo "Testing Worker..."
	@docker exec fresh-worker bash -c "cp /root/server-setup/0-cloud-config.sh /root/ && cd /root && bash 0-cloud-config.sh"
	@docker exec fresh-worker bash -c "su - ubuntu -c 'cd server-setup && cp .env.example .env && echo \"PERSONAL_SSH_KEY=\\\"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7test ubuntu@test\\\"\" >> .env && echo \"CONTROL_PLANE_SSH_KEY=\\\"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7test ubuntu@test\\\"\" >> .env && echo \"CONTROL_PLANE_IP=\\\"172.21.0.10\\\"\" >> .env'"
	@docker exec fresh-worker bash -lc "cd /home/ubuntu/server-setup && make worker"
	@echo "✅ Fresh cloud provider simulation completed!"
	@echo "💡 Access containers: docker exec -it fresh-control-plane bash"
	@echo "💡 Cleanup: make test-cleanup"

test-cleanup:
	@echo "🧹 Cleaning up test environment..."
	@docker-compose -f test/docker-compose.test.yml down -v
	@docker system prune -f
	@echo "✅ Test cleanup complete!"
