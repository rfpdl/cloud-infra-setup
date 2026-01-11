#!/bin/bash

# Common library for cloud-infra-setup scripts
# Source this file in all scripts: source "$(dirname "$0")/lib/common.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
LOG_FILE="/var/log/cloud-setup.log"

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${timestamp} [${level}] ${message}"
}

log_info() { log "INFO" "$1"; }
log_warn() { log "WARN" "$1"; }
log_error() { log "ERROR" "$1"; }

# =============================================================================
# INPUT VALIDATION FUNCTIONS
# =============================================================================

# Validate IPv4 address format
validate_ipv4() {
    local ip="$1"
    if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 1
    fi
    for octet in ${ip//./ }; do
        if [ "$octet" -gt 255 ] 2>/dev/null; then
            return 1
        fi
    done
    return 0
}

# Validate port number (1-65535)
validate_port() {
    local port="$1"
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        return 1
    fi
    return 0
}

# Validate positive integer
validate_positive_int() {
    local num="$1"
    if ! [[ "$num" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    if [ "$num" -lt 0 ]; then
        return 1
    fi
    return 0
}

# Validate Linux username (1-32 chars, alphanumeric + ._-)
validate_username() {
    local username="$1"
    if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        return 1
    fi
    return 0
}

# Validate SSH public key format
validate_ssh_key() {
    local key="$1"
    if [[ -z "$key" ]]; then
        return 1
    fi
    # Check for valid SSH key types
    if ! [[ "$key" =~ ^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|sk-ssh-ed25519|sk-ecdsa-sha2-nistp256)[[:space:]] ]]; then
        return 1
    fi
    return 0
}

# =============================================================================
# SAFE ENVIRONMENT LOADING
# =============================================================================

# Safely load .env file with validation (prevents code injection)
load_env_safe() {
    local env_file="${1:-.env}"

    if [ ! -f "$env_file" ]; then
        log_warn "No .env file found at $env_file"
        return 1
    fi

    log_info "Loading configuration from $env_file"

    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # Extract key and value
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            # Remove surrounding quotes if present
            value="${value#\"}"
            value="${value%\"}"
            value="${value#\'}"
            value="${value%\'}"

            # Export the variable (safe because key is validated)
            export "$key=$value"
        else
            log_warn "Skipping malformed line in $env_file: $line"
        fi
    done < "$env_file"

    return 0
}

# =============================================================================
# DEFAULTS AND VALIDATION
# =============================================================================

set_defaults() {
    USERNAME=${USERNAME:-"ubuntu"}
    SSH_PORT=${SSH_PORT:-"22"}
    FAIL2BAN_FINDTIME=${FAIL2BAN_FINDTIME:-"600"}
    FAIL2BAN_MAXRETRY=${FAIL2BAN_MAXRETRY:-"3"}
    FAIL2BAN_BANTIME=${FAIL2BAN_BANTIME:-"3600"}
    SSH_MAX_AUTH_TRIES=${SSH_MAX_AUTH_TRIES:-"3"}
    SSH_CLIENT_ALIVE_INTERVAL=${SSH_CLIENT_ALIVE_INTERVAL:-"300"}
    SSH_CLIENT_ALIVE_COUNT_MAX=${SSH_CLIENT_ALIVE_COUNT_MAX:-"2"}
    SSH_MAX_STARTUPS=${SSH_MAX_STARTUPS:-"10:30:60"}
    SSH_LOGIN_GRACE_TIME=${SSH_LOGIN_GRACE_TIME:-"60"}
    CONTROL_PLANE_UI_PORT=${CONTROL_PLANE_UI_PORT:-"3000"}
    PROMETHEUS_PORT=${PROMETHEUS_PORT:-"9090"}
    GRAFANA_PORT=${GRAFANA_PORT:-"3001"}
}

validate_all_config() {
    local errors=0

    # Validate username
    if ! validate_username "$USERNAME"; then
        log_error "Invalid USERNAME: $USERNAME (must be 1-32 chars, lowercase alphanumeric + ._-)"
        ((errors++))
    fi

    # Validate ports
    for port_var in SSH_PORT CONTROL_PLANE_UI_PORT PROMETHEUS_PORT GRAFANA_PORT; do
        if ! validate_port "${!port_var}"; then
            log_error "Invalid $port_var: ${!port_var} (must be 1-65535)"
            ((errors++))
        fi
    done

    # Validate fail2ban settings
    for param in FAIL2BAN_FINDTIME FAIL2BAN_MAXRETRY FAIL2BAN_BANTIME; do
        if ! validate_positive_int "${!param}"; then
            log_error "Invalid $param: ${!param} (must be positive integer)"
            ((errors++))
        fi
    done

    # Validate SSH settings
    if ! validate_positive_int "$SSH_MAX_AUTH_TRIES"; then
        log_error "Invalid SSH_MAX_AUTH_TRIES: $SSH_MAX_AUTH_TRIES"
        ((errors++))
    fi

    # Validate CONTROL_PLANE_IP if set
    if [ -n "$CONTROL_PLANE_IP" ] && ! validate_ipv4 "$CONTROL_PLANE_IP"; then
        log_error "Invalid CONTROL_PLANE_IP: $CONTROL_PLANE_IP"
        ((errors++))
    fi

    # Validate SSH keys if set
    if [ -n "$PERSONAL_SSH_KEY" ] && ! validate_ssh_key "$PERSONAL_SSH_KEY"; then
        log_error "Invalid PERSONAL_SSH_KEY format (must start with ssh-rsa, ssh-ed25519, etc.)"
        ((errors++))
    fi

    if [ -n "$CONTROL_PLANE_SSH_KEY" ] && ! validate_ssh_key "$CONTROL_PLANE_SSH_KEY"; then
        log_error "Invalid CONTROL_PLANE_SSH_KEY format"
        ((errors++))
    fi

    if [ $errors -gt 0 ]; then
        log_error "Configuration validation failed with $errors error(s)"
        return 1
    fi

    log_info "Configuration validated successfully"
    return 0
}

# =============================================================================
# SERVICE MANAGEMENT
# =============================================================================

# Restart systemd service with error handling
systemctl_restart() {
    local service="$1"
    log_info "Restarting $service..."

    if ! systemctl restart "$service"; then
        log_error "Failed to restart $service"
        journalctl -xeu "$service.service" -n 20 --no-pager 2>/dev/null || true
        return 1
    fi

    # Wait for service to be active
    local timeout=30
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if systemctl is-active --quiet "$service"; then
            log_info "$service is running"
            return 0
        fi
        sleep 1
        ((elapsed++))
    done

    log_error "$service failed to become active within ${timeout}s"
    return 1
}

# Enable and start service
systemctl_enable_start() {
    local service="$1"
    log_info "Enabling and starting $service..."

    systemctl enable "$service" || { log_error "Failed to enable $service"; return 1; }
    systemctl start "$service" || { log_error "Failed to start $service"; return 1; }

    if systemctl is-active --quiet "$service"; then
        log_info "$service enabled and running"
        return 0
    else
        log_error "$service is not active after start"
        return 1
    fi
}

# =============================================================================
# FILE OPERATIONS
# =============================================================================

# Backup file before modifying
backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        local backup="${file}.backup.$(date +%s)"
        cp "$file" "$backup" && log_info "Backed up $file to $backup"
    fi
}

# Create directory with correct permissions (avoids race condition)
create_secure_dir() {
    local dir="$1"
    local owner="$2"
    local mode="${3:-700}"

    if [ -d "$dir" ]; then
        chown "$owner:$owner" "$dir"
        chmod "$mode" "$dir"
    else
        install -d -m "$mode" -o "$owner" -g "$owner" "$dir"
    fi
}

# =============================================================================
# NETWORK UTILITIES
# =============================================================================

# Get public IP with fallback
get_public_ip() {
    local ip=""

    # Try multiple services with timeout
    ip=$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null) ||
    ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null) ||
    ip=$(curl -s --max-time 5 https://icanhazip.com 2>/dev/null) ||
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')

    if validate_ipv4 "$ip"; then
        echo "$ip"
        return 0
    fi

    return 1
}

# Wait for service to be reachable
wait_for_service() {
    local host="$1"
    local port="$2"
    local timeout="${3:-60}"
    local elapsed=0

    log_info "Waiting for $host:$port to be reachable..."

    while [ $elapsed -lt $timeout ]; do
        if nc -z "$host" "$port" 2>/dev/null || timeout 1 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
            log_info "$host:$port is reachable"
            return 0
        fi
        sleep 2
        ((elapsed+=2))
    done

    log_error "$host:$port not reachable within ${timeout}s"
    return 1
}

# =============================================================================
# ERROR HANDLING
# =============================================================================

handle_error() {
    local exit_code=$?
    local line_number=$1
    log_error "Error on line $line_number (exit code: $exit_code)"
    exit $exit_code
}

# Usage: trap 'handle_error $LINENO' ERR
