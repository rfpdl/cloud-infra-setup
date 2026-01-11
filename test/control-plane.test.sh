#!/bin/bash

# Control Plane Configuration Test Script (moved to test/control-plane.test.sh)
# Tests control plane configuration after running:
#   1-server-hardening.sh + 2-server-bootstrap.sh + 3A-control-plane.commands.sh

set -e

# Function to load environment variables
load_env() {
    local env_file=".env"
    if [ -f "$env_file" ]; then
        # Source the .env file, ignoring comments and empty lines
        set -a
        source <(grep -v '^#' "$env_file" | grep -v '^$')
        set +a
    fi
}

# Function to set default values
set_defaults() {
    USERNAME=${USERNAME:-"ubuntu"}
    SSH_PORT=${SSH_PORT:-"22"}
    CONTROL_PLANE_UI_PORT=${CONTROL_PLANE_UI_PORT:-"3000"}
    PROMETHEUS_PORT=${PROMETHEUS_PORT:-"9090"}
    GRAFANA_PORT=${GRAFANA_PORT:-"3001"}
}

# Load configuration
load_env
set_defaults

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Helper functions
print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

print_test() {
    echo -e "${YELLOW}Testing: $1${NC}"
    ((++TESTS_TOTAL))
}

print_pass() {
    echo -e "${GREEN}✓ PASS: $1${NC}"
    ((++TESTS_PASSED))
}

print_fail() {
    echo -e "${RED}✗ FAIL: $1${NC}"
    ((++TESTS_FAILED))
}

print_info() {
    echo -e "${BLUE}ℹ INFO: $1${NC}"
}

# Test functions
test_user_setup() {
    print_header "User Configuration Tests"
    
    print_test "User '${USERNAME}' exists"
    if id "${USERNAME}" &>/dev/null; then
        print_pass "User '${USERNAME}' exists"
    else
        print_fail "User '${USERNAME}' does not exist"
    fi
    
    print_test "User '${USERNAME}' has correct groups"
    if groups ${USERNAME} | grep -q "sudo\|admin" && groups ${USERNAME} | grep -q "docker"; then
        print_pass "User '${USERNAME}' has sudo and docker groups"
    else
        print_fail "User '${USERNAME}' missing required groups"
        print_info "Current groups: $(groups ${USERNAME})"
    fi
    
    print_test "SSH directory permissions"
    if [ -d "/home/${USERNAME}/.ssh" ] && [ "$(stat -c %a /home/${USERNAME}/.ssh)" = "700" ]; then
        print_pass "SSH directory has correct permissions (700)"
    else
        print_fail "SSH directory permissions incorrect"
    fi
    
    print_test "SSH authorized_keys permissions"
    if [ -f "/home/${USERNAME}/.ssh/authorized_keys" ] && [ "$(stat -c %a /home/${USERNAME}/.ssh/authorized_keys)" = "600" ]; then
        print_pass "authorized_keys has correct permissions (600)"
    else
        print_fail "authorized_keys permissions incorrect"
    fi
    
    print_test "SSH keys present"
    if [ -s "/home/${USERNAME}/.ssh/authorized_keys" ] && ! grep -q "# SSH keys should be managed via cloud-config" /home/${USERNAME}/.ssh/authorized_keys; then
        print_pass "SSH keys are configured"
        print_info "Number of keys: $(grep -c "ssh-" /home/${USERNAME}/.ssh/authorized_keys 2>/dev/null || echo 0)"
    else
        print_fail "No SSH keys found or only placeholder content"
    fi
}

test_ssh_configuration() {
    print_header "SSH Configuration Tests"
    
    print_test "SSH hardening config exists"
    if [ -f "/etc/ssh/sshd_config.d/ssh-hardening.conf" ]; then
        print_pass "SSH hardening config file exists"
    else
        print_fail "SSH hardening config file missing"
    fi
    
    print_test "SSH running on port ${SSH_PORT}"
    if ss -tlnp | grep -q ":${SSH_PORT}"; then
        print_pass "SSH is listening on port ${SSH_PORT}"
    else
        print_fail "SSH not listening on port ${SSH_PORT}"
        print_info "SSH ports: $(ss -tlnp | grep sshd | awk '{print $4}' | cut -d: -f2)"
    fi
    
    print_test "Root login disabled"
    if grep -q "PermitRootLogin no" /etc/ssh/sshd_config* 2>/dev/null; then
        print_pass "Root login is disabled"
    else
        print_fail "Root login may still be enabled"
    fi
    
    print_test "Password authentication disabled"
    if grep -q "PasswordAuthentication no" /etc/ssh/sshd_config* 2>/dev/null; then
        print_pass "Password authentication is disabled"
    else
        print_fail "Password authentication may still be enabled"
    fi
}

test_control_plane_firewall() {
    print_header "Control Plane Firewall Tests"
    
    print_test "UFW is installed and active"
    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        print_pass "UFW is installed and active"
    else
        print_fail "UFW is not active"
    fi
    
    print_test "SSH port ${SSH_PORT} allowed in UFW"
    if ufw status | grep -q "${SSH_PORT}"; then
        print_pass "SSH port ${SSH_PORT} is allowed in UFW"
    else
        print_fail "SSH port ${SSH_PORT} not found in UFW rules"
    fi
    
    print_test "HTTP/HTTPS ports open"
    if ufw status | grep -q "80/tcp\|443/tcp"; then
        print_pass "HTTP/HTTPS ports are open"
    else
        print_fail "HTTP/HTTPS ports not found in UFW rules"
    fi
    
    print_test "Control Plane UI port ${CONTROL_PLANE_UI_PORT} open"
    if ufw status | grep -q "${CONTROL_PLANE_UI_PORT}/tcp"; then
        print_pass "Control Plane UI port ${CONTROL_PLANE_UI_PORT} is open"
    else
        print_fail "Control Plane UI port ${CONTROL_PLANE_UI_PORT} not found in UFW rules"
    fi
    
    print_test "Monitoring ports open (Grafana/Prometheus)"
    if ufw status | grep -q "${PROMETHEUS_PORT}/tcp\|${GRAFANA_PORT}/tcp"; then
        print_pass "Monitoring ports are configured"
    else
        print_fail "Monitoring ports not found in UFW rules"
    fi
    
    print_test "Docker Swarm management ports open"
    if ufw status | grep -q "2377/tcp\|7946\|4789"; then
        print_pass "Docker Swarm management ports are open"
    else
        print_fail "Docker Swarm management ports not configured"
    fi

    print_test "Docker TCP API ports 2375/2376 are NOT allowed in UFW"
    if ufw status | grep -E "2375/tcp|2376/tcp" | grep -qi "deny"; then
        print_pass "UFW denies Docker TCP API ports"
    elif ! ufw status | grep -qE "2375/tcp|2376/tcp"; then
        print_pass "No UFW allow rules found for 2375/2376"
    else
        print_fail "Found UFW allow rule for Docker TCP API (2375/2376)"
    fi
}

test_fail2ban_configuration() {
    print_header "Fail2ban Configuration Tests"
    
    print_test "Fail2ban is installed"
    if command -v fail2ban-server >/dev/null 2>&1; then
        print_pass "Fail2ban is installed"
    else
        print_fail "Fail2ban is not installed"
    fi
    
    print_test "Fail2ban is running"
    if systemctl is-active --quiet fail2ban; then
        print_pass "Fail2ban service is running"
    else
        print_fail "Fail2ban service is not running"
    fi
    
    print_test "Fail2ban SSH jail configured"
    if [ -f "/etc/fail2ban/jail.local" ] && grep -q "\[sshd\]" /etc/fail2ban/jail.local; then
        print_pass "Fail2ban SSH jail is configured"
    else
        print_fail "Fail2ban SSH jail not configured"
    fi
    
    print_test "Fail2ban monitoring SSH port ${SSH_PORT}"
    if grep -q "${SSH_PORT}" /etc/fail2ban/jail.local 2>/dev/null; then
        print_pass "Fail2ban is monitoring SSH port ${SSH_PORT}"
    else
        print_fail "Fail2ban not configured for SSH port ${SSH_PORT}"
    fi
}

test_docker_configuration() {
    print_header "Docker Configuration Tests"
    
    print_test "Docker is installed"
    if command -v docker >/dev/null 2>&1; then
        print_pass "Docker is installed"
        print_info "Docker version: $(docker --version)"
    else
        print_fail "Docker is not installed"
    fi
    
    print_test "Docker service is running"
    if systemctl is-active --quiet docker; then
        print_pass "Docker service is running"
    else
        print_fail "Docker service is not running"
    fi
    
    print_test "Docker Compose is available"
    if docker compose version >/dev/null 2>&1 || docker-compose --version >/dev/null 2>&1; then
        print_pass "Docker Compose is available"
    else
        print_fail "Docker Compose is not available"
    fi
    
    print_test "User '${USERNAME}' can run Docker commands"
    if sudo -u ${USERNAME} docker ps >/dev/null 2>&1; then
        print_pass "User '${USERNAME}' can run Docker commands"
    else
        print_fail "User '${USERNAME}' cannot run Docker commands"
    fi
    
    print_test "Dokploy network exists"
    if docker network ls | grep -q "dokploy-network"; then
        print_pass "Dokploy network exists"
    else
        print_fail "Dokploy network not found"
    fi

    print_test "Docker daemon is bound to Unix socket only"
    if [ -f "/etc/docker/daemon.json" ] && grep -q '"unix:///var/run/docker.sock"' /etc/docker/daemon.json; then
        print_pass "daemon.json configured for Unix socket"
    else
        print_fail "daemon.json missing or not set to Unix socket"
    fi

    print_test "No Docker TCP API listeners on 2375/2376"
    if ! ss -tlnp 2>/dev/null | grep -qE ":2375|:2376"; then
        print_pass "No Docker TCP API listeners detected"
    else
        print_fail "Docker TCP API listener detected on 2375/2376"
    fi
}

test_control_plane_setup() {
    print_header "Control Plane Setup Tests"
    
    print_test "Dokploy directory exists"
    if [ -d "/etc/dokploy" ]; then
        print_pass "Dokploy directory exists"
        print_info "Permissions: $(ls -ld /etc/dokploy)"
    else
        print_fail "Dokploy directory not found"
    fi
    
    print_test "Dokploy directory ownership"
    if [ -d "/etc/dokploy" ] && [ "$(stat -c %U:%G /etc/dokploy)" = "${USERNAME}:${USERNAME}" ]; then
        print_pass "Dokploy directory has correct ownership"
    else
        print_fail "Dokploy directory ownership incorrect"
    fi
    
    print_test "Ready for Dokploy installation"
    if [ -d "/etc/dokploy" ] && docker network ls 2>/dev/null | grep -q "dokploy-network"; then
        print_pass "Server ready for Dokploy installation"
    else
        print_fail "Server not ready for Dokploy installation"
    fi
}

# Main execution
main() {
    echo -e "${BLUE}🔍 Control Plane Configuration Test Suite${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}Testing: 1-server-hardening.sh + 2-server-bootstrap.sh + 3A-control-plane.commands.sh${NC}"
    
    # Run all tests
    test_user_setup
    test_ssh_configuration
    test_control_plane_firewall
    test_fail2ban_configuration
    test_docker_configuration
    test_control_plane_setup
    
    # Summary
    print_header "Test Summary"
    echo -e "Server Role: ${BLUE}Control Plane${NC}"
    echo -e "Total tests: ${TESTS_TOTAL}"
    echo -e "${GREEN}Passed: ${TESTS_PASSED}${NC}"
    echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"
    
    if [ ${TESTS_FAILED} -eq 0 ]; then
        echo -e "\n${GREEN}🎉 All tests passed! Control Plane server configuration looks good.${NC}"
        echo -e "${GREEN}✓ Ready for Dokploy + Grafana + Prometheus + GitLab Runner${NC}"
        exit 0
    else
        echo -e "\n${RED}❌ Some tests failed. Please review the Control Plane configuration.${NC}"
        exit 1
    fi
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run this script as root (use sudo)${NC}"
    exit 1
fi

main "$@"
