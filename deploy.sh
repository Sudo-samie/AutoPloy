#!/bin/sh
set -eu

#===================================================
#DevOps Automated Deployment Script
#Description: Automates setup, deployment, and configuration of Dockerized applications on remote 
#Posix-compliant
#===================================================
# Enable pipefail if supported (bash, zsh)
(set -o pipefail >/dev/nul 2>&1) || true
#===================================================
#GLOBAL VARIABLES
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="${SCRIPT_DIR}/deploy_${TIMESTAMP}.log"
CLEANUP_MODE=false
#EXIT_CODE=0

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
    color="$2"
    shift
    shift
    message="$*"
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    printf "%b[%s]%b [%s] %s\n" "${color}" "${level}" "${NC}" "${timestamp}" "${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "${BLUE}" "$*"
}

log_success() {
    log "SUCCESS" "${GREEN}" "$*"
}

log_warning() {
    log "WARNING" "${YELLOW}" "$*"
}

log_error() {
    log "ERROR" "${RED}" "$*"
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
#=====================================================================
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

#=====================================================================
# GIT OPERATIONS
#=====================================================================  

clone_repository() {
    log_info "Starting repository clone/update process..."
    
    # Prepare authenticated URL
    case "$GIT_REPO_URL" in
        https://github.com/*)
            auth_url=$(echo "$GIT_REPO_URL" | sed "s|https://|https://${GIT_PAT}@|")
            ;;
        https://gitlab.com/*)
            auth_url=$(echo "$GIT_REPO_URL" | sed "s|https://|https://oauth2:${GIT_PAT}@|")
            ;;
        *)
            auth_url=$(echo "$GIT_REPO_URL" | sed "s|https://|https://${GIT_PAT}@|")
            ;;
    esac
    
    if [ -d "$REPO_DIR" ]; then
        log_info "Repository directory exists. Pulling latest changes..."
        cd "$REPO_DIR" || error_exit "Failed to cd into $REPO_DIR" 2
        
        git fetch origin || error_exit "Failed to fetch from origin" 3
        git checkout "$GIT_BRANCH" || error_exit "Failed to checkout branch $GIT_BRANCH" 4
        git pull origin "$GIT_BRANCH" || error_exit "Failed to pull latest changes" 5
        
        log_success "Repository updated successfully"
    else
        log_info "Cloning repository..."
        git clone "$auth_url" "$REPO_DIR" || error_exit "Failed to clone repository" 6
        
        cd "$REPO_DIR" || error_exit "Failed to cd into $REPO_DIR" 2
        git checkout "$GIT_BRANCH" || error_exit "Failed to checkout branch $GIT_BRANCH" 4
        
        log_success "Repository cloned successfully"
    fi
}

verify_docker_files() {
    log_info "Verifying Docker configuration files..."
    
    if [ -f "Dockerfile" ]; then
        log_success "Dockerfile found"
        DOCKER_FILE_TYPE="dockerfile"
    elif [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
        log_success "docker-compose.yml found"
        DOCKER_FILE_TYPE="compose"
    else
        error_exit "Neither Dockerfile nor docker-compose.yml found in repository" 7
    fi
}

#=====================================================================
# SSH OPERATIONS
#=====================================================================

test_ssh_connection() {
    log_info "Testing SSH connection to $SSH_USER@$SERVER_IP..."
    
    if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
        "$SSH_USER@$SERVER_IP" "echo 'SSH connection successful'" >/dev/null 2>&1; then
        log_success "SSH connection established"
        return 0
    else
        error_exit "Failed to establish SSH connection" 8
    fi
}

execute_remote_command() {
    command="$1"
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no \
        "$SSH_USER@$SERVER_IP" "$command"
}

#=====================================================================
# REMOTE ENVIRONMENT SETUP
#=====================================================================

prepare_remote_environment() {
    log_info "Preparing remote environment..."
    
    execute_remote_command "sudo apt-get update -y" || log_warning "apt-get update failed"
    
    log_info "Installing Docker..."
    execute_remote_command "
        if ! command -v docker >/dev/null 2>&1; then
            curl -fsSL https://get.docker.com -o get-docker.sh
            sudo sh get-docker.sh
            rm get-docker.sh
            sudo usermod -aG docker $SSH_USER
            echo 'Docker installed successfully'
        else
            echo 'Docker already installed'
        fi
    " || error_exit "Failed to install Docker" 9
    
    log_info "Installing Docker Compose..."
    execute_remote_command "
        if ! command -v docker-compose >/dev/null 2>&1; then
            sudo curl -L \"https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)\" -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
            echo 'Docker Compose installed successfully'
        else
            echo 'Docker Compose already installed'
        fi
    " || error_exit "Failed to install Docker Compose" 10
    
    log_info "Installing Nginx..."
    execute_remote_command "
        if ! command -v nginx >/dev/null 2>&1; then
            sudo apt-get install -y nginx
            echo 'Nginx installed successfully'
        else
            echo 'Nginx already installed'
        fi
    " || error_exit "Failed to install Nginx" 11
    
    log_info "Starting services..."
    execute_remote_command "
        sudo systemctl enable docker
        sudo systemctl start docker
        sudo systemctl enable nginx
        sudo systemctl start nginx
    " || error_exit "Failed to start services" 12
    
    log_info "Verifying installations..."
    execute_remote_command "
        echo 'Docker version:'
        docker --version
        echo 'Docker Compose version:'
        docker-compose --version
        echo 'Nginx version:'
        nginx -v
    "
    
    log_success "Remote environment prepared successfully"
}

#=====================================================================
# APPLICATION DEPLOYMENT
#=====================================================================

transfer_files() {
    log_info "Transferring application files to remote server..."
    
    remote_dir="/home/$SSH_USER/$REPO_NAME"
    
    # Create remote directory
    execute_remote_command "mkdir -p $remote_dir"
    
    # Transfer files using rsync
    rsync -avz -e "ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no" \
        --exclude '.git' \
        --exclude '*.log' \
        --exclude 'node_modules' \
        "$REPO_DIR/" \
        "$SSH_USER@$SERVER_IP:$remote_dir/" || error_exit "Failed to transfer files" 13
    
    log_success "Files transferred successfully"
}

deploy_application() {
    log_info "Deploying application..."
    
    remote_dir="/home/$SSH_USER/$REPO_NAME"
    container_name="${REPO_NAME}_app"
    
    # Stop and remove existing containers
    execute_remote_command "
        cd $remote_dir
        
        # Stop existing containers
        if docker ps -a | grep -q $container_name; then
            echo 'Stopping existing container...'
            docker stop $container_name || true
            docker rm $container_name || true
        fi
        
        # Remove old images (optional - keeps one backup)
        docker images | grep $REPO_NAME | tail -n +3 | awk '{print \$3}' | xargs -r docker rmi || true
    "
    
    if [ "$DOCKER_FILE_TYPE" = "compose" ]; then
        log_info "Deploying with docker-compose..."
        execute_remote_command "
            cd $remote_dir
            docker-compose down || true
            docker-compose build
            docker-compose up -d
        " || error_exit "Failed to deploy with docker-compose" 14
    else
        log_info "Deploying with Dockerfile..."
        execute_remote_command "
            cd $remote_dir
            docker build -t $REPO_NAME:latest .
            docker run -d --name $container_name -p $APP_PORT:$APP_PORT --restart unless-stopped $REPO_NAME:latest
        " || error_exit "Failed to deploy with Docker" 15
    fi
    
    # Wait for container to start
    sleep 5
    
    log_success "Application deployed successfully"
}

validate_deployment() {
    log_info "Validating deployment..."
    
    container_name="${REPO_NAME}_app"
    
    # Check if container is running
    if execute_remote_command "docker ps | grep -q $container_name || docker ps | grep -q $REPO_NAME"; then
        log_success "Container is running"
    else
        log_error "Container is not running"
        execute_remote_command "docker ps -a | grep $REPO_NAME" || true
        execute_remote_command "docker logs $container_name 2>&1 | tail -n 50" || true
        error_exit "Container failed to start" 16
    fi
    
    # Check container health
    log_info "Container status:"
    execute_remote_command "docker ps | grep $REPO_NAME"
    
    # Test application endpoint
    log_info "Testing application endpoint..."
    sleep 3
    if execute_remote_command "curl -f -s http://localhost:$APP_PORT >/dev/null 2>&1 || wget -q -O /dev/null http://localhost:$APP_PORT 2>&1"; then
        log_success "Application is responding on port $APP_PORT"
    else
        log_warning "Application not responding yet (this may be normal during startup)"
    fi
}

#=====================================================================
# NGINX CONFIGURATION
#=====================================================================

configure_nginx() {
    log_info "Configuring Nginx reverse proxy..."
    
    nginx_config="/etc/nginx/sites-available/$REPO_NAME"
    domain="${SERVER_IP}"
    
    execute_remote_command "
        sudo tee $nginx_config > /dev/null <<'EOF'
server {
    listen 80;
    server_name $domain;

    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    " || error_exit "Failed to create Nginx configuration" 17
    
    # Enable site
    execute_remote_command "
        sudo ln -sf $nginx_config /etc/nginx/sites-enabled/$REPO_NAME
        sudo rm -f /etc/nginx/sites-enabled/default
    "
    
    # Test configuration
    log_info "Testing Nginx configuration..."
    execute_remote_command "sudo nginx -t" || error_exit "Nginx configuration test failed" 18
    
    # Reload Nginx
    execute_remote_command "sudo systemctl reload nginx" || error_exit "Failed to reload Nginx" 19
    
    log_success "Nginx configured successfully"
}

validate_nginx() {
    log_info "Validating Nginx proxy..."
    
    # Test from remote server
    if execute_remote_command "curl -f -s http://localhost >/dev/null 2>&1"; then
        log_success "Nginx is proxying correctly (tested from server)"
    else
        log_warning "Nginx proxy test from server failed"
    fi
    
    # Test from local machine
    log_info "Testing external access..."
    if curl -f -s "http://$SERVER_IP" >/dev/null 2>&1; then
        log_success "Application is accessible from external network"
    else
        log_warning "External access test failed (firewall may be blocking port 80)"
    fi
}

#=====================================================================
# CLEANUP OPERATIONS
#=====================================================================

cleanup_deployment() {
    log_info "Cleaning up deployment..."
    
    remote_dir="/home/$SSH_USER/$REPO_NAME"
    container_name="${REPO_NAME}_app"
    
    execute_remote_command "
        # Stop and remove containers
        docker stop $container_name 2>/dev/null || true
        docker rm $container_name 2>/dev/null || true
        docker-compose -f $remote_dir/docker-compose.yml down 2>/dev/null || true
        
        # Remove images
        docker rmi $REPO_NAME:latest 2>/dev/null || true
        
        # Remove Nginx config
        sudo rm -f /etc/nginx/sites-enabled/$REPO_NAME
        sudo rm -f /etc/nginx/sites-available/$REPO_NAME
        sudo systemctl reload nginx
        
        # Remove application files
        rm -rf $remote_dir
        
        echo 'Cleanup completed'
    "
    
    log_success "Deployment cleaned up successfully"
}

#=====================================================================
# MAIN EXECUTION
#=====================================================================

print_banner() {
    cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║   Docker Application Deployment Script v1.0              ║
║   Production-Grade Automated Deployment                  ║
╚═══════════════════════════════════════════════════════════╝
EOF
}

print_usage() {
    cat << EOF

Usage: $0 [OPTIONS]

OPTIONS:
    --cleanup    Remove all deployed resources from remote server
    --help       Display this help message

DESCRIPTION:
    This script automates the complete deployment process of a Dockerized
    application to a remote Linux server, including:
    - Git repository cloning
    - Docker environment setup
    - Application deployment
    - Nginx reverse proxy configuration
    - Comprehensive validation and logging

EOF
}

main() {
    print_banner
    
    log_info "Deployment script started"
    log_info "Log file: $LOG_FILE"
    
    # Parse command line arguments
    while [ $# -gt 0 ]; do
        case $1 in
            --cleanup)
                CLEANUP_MODE=true
                shift
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
    
    # Check for required commands
    for cmd in git ssh scp rsync curl; do
        if ! command -v $cmd >/dev/null 2>&1; then
            error_exit "Required command not found: $cmd" 20
        fi
    done
    
    # Collect user input
    collect_user_input
    
    # Test SSH connection early
    test_ssh_connection
    
    if [ "$CLEANUP_MODE" = true ]; then
        log_warning "Running in CLEANUP mode"
        printf "Are you sure you want to remove all deployed resources? (yes/no): "
        read -r confirm
        if [ "$confirm" = "yes" ]; then
            cleanup_deployment
            log_success "Cleanup completed successfully"
        else
            log_info "Cleanup cancelled"
        fi
        exit 0
    fi
    
    # Execute deployment steps
    clone_repository
    verify_docker_files
    prepare_remote_environment
    transfer_files
    deploy_application
    validate_deployment
    configure_nginx
    validate_nginx
    
    # Final summary
    printf "\n"
    log_success "═══════════════════════════════════════════════════════"
    log_success "DEPLOYMENT COMPLETED SUCCESSFULLY"
    log_success "═══════════════════════════════════════════════════════"
    log_info "Application URL: http://$SERVER_IP"
    log_info "Direct port access: http://$SERVER_IP:$APP_PORT"
    log_info "Log file: $LOG_FILE"
    log_success "═══════════════════════════════════════════════════════"
    printf "\n"
}

# Execute main function
main "$@"

