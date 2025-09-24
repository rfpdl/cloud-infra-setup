#!/bin/bash

# Worker Configuration Test Script
# Tests worker specific configuration after running 1-server-hardening.sh + 2B-worker.commands.sh

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
    CONTROL_PLANE_IP=${CONTROL_PLANE_IP:-""}
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
    ((TESTS_TOTAL++))
}

print_pass() {
    echo -e "${GREEN}✓ PASS: $1${NC}"
    ((TESTS_PASSED++))
}

print_fail() {
    echo -e "${RED}✗ FAIL: $1${NC}"
    ((TESTS_FAILED++))
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

test_worker_firewall() {
    print_header "Worker Firewall Tests (Locked Down)"
    
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
    
    print_test "Restricted Docker Swarm access"
    if ufw status | grep -E "from [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | grep -q "2377\|7946\|4789"; then
        print_pass "Docker Swarm ports are restricted to control plane IP"
        control_plane_ip=$(ufw status | grep -E "from [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | head -1 | grep -oE "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+")
        print_info "Control plane IP: $control_plane_ip"
    else
        print_fail "Docker Swarm ports not properly restricted"
    fi
    
    print_test "No public web ports open"
    if ! ufw status | grep -q "80/tcp\|443/tcp\|${CONTROL_PLANE_UI_PORT}/tcp"; then
        print_pass "No public web ports are open (secure worker)"
    else
        print_fail "Public web ports found - worker should be locked down"
    fi
    
    print_test "Outbound HTTPS/HTTP allowed"
    if ufw status | grep -q "80/tcp.*OUT\|443/tcp.*OUT"; then
        print_pass "Outbound HTTP/HTTPS allowed for Docker registry access"
    else
        print_fail "Outbound HTTP/HTTPS not configured"
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
}

test_worker_setup() {
    print_header "Worker Setup Tests"
    
    print_test "No Dokploy directory (security)"
    if [ ! -d "/etc/dokploy" ]; then
        print_pass "No Dokploy directory found (correct for worker)"
    else
        print_fail "Dokploy directory found on worker (security risk)"
    fi
    
    print_test "Ready for Docker Swarm join"
    if systemctl is-active --quiet docker && ufw status | grep -E "from [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | grep -q "2377"; then
        print_pass "Worker ready to join Docker Swarm"
    else
        print_fail "Worker not ready for Docker Swarm"
    fi
    
    print_test "Zventy project readiness"
    if docker --version >/dev/null 2>&1 && sudo -u ${USERNAME} docker ps >/dev/null 2>&1; then
        print_pass "Ready for Zventy Laravel deployment"
    else
        print_fail "Not ready for application deployment"
    fi
}

test_system_security() {
    print_header "System Security Tests"
    
    print_test "System packages are up to date"
    if apt list --upgradable 2>/dev/null | grep -q "upgradable"; then
        print_fail "System has available package updates"
        print_info "Run 'apt update && apt upgrade' to update"
    else
        print_pass "System packages are up to date"
    fi
    
    print_test "Essential security packages installed"
    missing_packages=()
    for package in fail2ban ufw docker.io; do
        if ! dpkg -l | grep -q "^ii.*$package"; then
            missing_packages+=("$package")
        fi
    done
    
    if [ ${#missing_packages[@]} -eq 0 ]; then
        print_pass "All essential security packages are installed"
    else
        print_fail "Missing packages: ${missing_packages[*]}"
    fi
}

# Main execution
main() {
    echo -e "${BLUE}🔍 Worker Configuration Test Suite${NC}"
    echo -e "${BLUE}===================================${NC}"
    echo -e "${BLUE}Testing: 1-server-hardening.sh + 2B-worker.commands.sh${NC}"
    
    # Run all tests
    test_user_setup
    test_ssh_configuration
    test_worker_firewall
    test_fail2ban_configuration
    test_docker_configuration
    test_worker_setup
    test_system_security
    
    # Summary
    print_header "Test Summary"
    echo -e "Server Role: ${BLUE}Worker${NC}"
    echo -e "Total tests: ${TESTS_TOTAL}"
    echo -e "${GREEN}Passed: ${TESTS_PASSED}${NC}"
    echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"
    
    if [ ${TESTS_FAILED} -eq 0 ]; then
        echo -e "\n${GREEN}🎉 All tests passed! Worker server configuration looks good.${NC}"
        echo -e "${GREEN}✓ Ready for Zventy Laravel application deployment${NC}"
        exit 0
    else
        echo -e "\n${RED}❌ Some tests failed. Please review the Worker configuration.${NC}"
        exit 1
    fi
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run this script as root (use sudo)${NC}"
    exit 1
fi

main "$@"
