#!/bin/sh
set -eu

#===================================================
#DevOps Automated Deployment Script
#Description: Automates setup, deployment, and configuration of Dockerized applications on remote 
#Posix-compliant
#===================================================
# Enable pipefail if supported (bash, zsh)
(set -o pipefail >/dev/nul 2>&1 ) || true
#===================================================
#GLOBAL VARIABLES
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="${SCRIPT_DIR}/deploy_${TIMESTAMP}.log"
CLEANUP_MODE=false
EXIT_CODE=0

#Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No color

#===================================================
# LOGGING 
log() {
    level="$1"
    shift
    message="$*"
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    printf "[%s] [%s] %s\n" "${timestamp}" "${level}" "${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    printf "%b[INFO]%b %s\n" "${BLUE}" "${NC}" "$*" | tee -a "${LOG_FILE}"
}

log_success() {
    printf "%b[SUCCESS]%b %s\n" "${GREEN}" "${NC}" "$*" | tee -a "${LOG_FILE}"
}

log_warning() {
    printf "%b[WARNING]%b %s\n" "${YELLOW}" "${NC}" "$*" | tee -a "${LOG_FILE}"
}

log_error() {
    printf "%b[ERROR]%b %s\n" "${RED}" "${NC}" "$*" | tee -a "${LOG_FILE}"
}
#===================================================
#ERROR HANDLING
error_exit() {
    log_error "$1"
    exit_code="${2:-1}"
    log_error "FATAL: Command failed with exit code $? on line $LINENO."
    exit "${exit_code}"
}

cleanup_on_error() {
    log_error "Script interrupted or failed. Cleaning up..."
    exit 1
}

trap cleanup_on_error INT TERM
#===================================================
#INPUT VALIDATION
validate_url() {
    url="$1"
    case "$url" in
        http://*|https://*) 
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}
validate_ip() {
    ip="$1"
    stat=1

    if echo "$ip" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
        OIFS=$IFS
        IFS='.'
        set -- "$ip"
        IFS=$OIFS
        [ "$1" -le 255 ] && [ "$2" -le 255 ] && [ "$3" -le 255 ] && [ "$4" -le 255 ]
        stat=$?
    fi
    return $stat
}
validate_port() {
    port="$1"
    # Check if it's a number
    case "$port" in
        ''|*[!0-9]*)
            return 1
            ;;
    esac
    # Check range
    if [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    fi
    return 1
}
validate_ssh_key() {
    key_path="$1"
    if [ ! -f "$key_path" ]; then
        return 1
    fi
    if [ ! -r "$key_path" ]; then
        return 1
    fi
    return 0
}
#===================================================
#.GETTING PARAMETER FROM USER INPUT
#Idealy we use read -rp, but to to be posix compliant
#we use printf + read -r in this case
collect_user_input() {
    log_info "Starting user input collection..."
    
    # Git Repository URL
    while true; do
        printf "Enter Git Repository URL: "
        read -r GIT_REPO_URL
        if validate_url "$GIT_REPO_URL"; then
            break
        else
            log_error "Invalid URL format. Please enter a valid HTTP/HTTPS URL."
        fi
    done
    
    # Personal Access Token
    while true; do
        printf "Enter Personal Access Token (PAT): "
        stty -echo
        read -r GIT_PAT
        stty echo
        printf "\n"
        if [ -n "$GIT_PAT" ]; then
            break
        else
            log_error "PAT cannot be empty."
        fi
    done
    
    # Branch name
    printf "Enter branch name (default: main): "
    read -r GIT_BRANCH
    GIT_BRANCH="${GIT_BRANCH:-main}"
    
    # SSH Username
    printf "Enter SSH username: "
    read -r SSH_USER
    
    # Server IP
    while true; do
        printf "Enter server IP address: "
        read -r SERVER_IP
        if validate_ip "$SERVER_IP"; then
            break
        else
            log_error "Invalid IP address format."
        fi
    done
    
    # SSH Key Path
    while true; do
        printf "Enter SSH key path (e.g., ~/.ssh/id_rsa): "
        read -r SSH_KEY_PATH
        
        # Expand tilde manually for POSIX compliance
        case "$SSH_KEY_PATH" in
            ~*)
                SSH_KEY_PATH="$HOME${SSH_KEY_PATH#\~}"
                ;;
        esac
        
        if validate_ssh_key "$SSH_KEY_PATH"; then
            chmod 600 "$SSH_KEY_PATH" 2>/dev/null || true
            break
        else
            log_error "SSH key not found or not readable: $SSH_KEY_PATH"
        fi
    done
    
    # Application Port
    while true; do
        printf "Enter application internal port: "
        read -r APP_PORT
        if validate_port "$APP_PORT"; then
            break
        else
            log_error "Invalid port number (must be 1-65535)."
        fi
    done
    
    # Extract repo name from URL
    REPO_NAME=$(basename "$GIT_REPO_URL" .git)
    REPO_DIR="${SCRIPT_DIR}/${REPO_NAME}"
    
    log_success "User input collected successfully"
    log_info "Repository: $GIT_REPO_URL"
    log_info "Branch: $GIT_BRANCH"
    log_info "Server: $SSH_USER@$SERVER_IP"
    log_info "Application Port: $APP_PORT"
}

