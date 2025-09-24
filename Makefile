# Cloud Infrastructure Setup Makefile
# Usage: make control-plane OR make worker

.PHONY: control-plane worker test-control-plane test-worker init-only help

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
	@echo "  init-only       - Run only initial setup (1-init.sh)"
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
	sudo bash 1-init.sh
	sudo bash 2A-control-plane.commands.sh
	sudo bash 3A-control-plane-test.sh
	@echo "✅ Control Plane setup complete!"

# Worker setup  
worker: check-env
	@echo "🔧 Setting up Worker..."
	sudo bash 1-init.sh
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
	sudo bash 1-init.sh
	@echo "✅ Initial setup complete!"
