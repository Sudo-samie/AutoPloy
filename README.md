# AutoPloy Project
# Docker Application Deployment Script

A robust, production-grade Bash script that automates the complete setup, deployment, and configuration of Dockerized applications on remote Linux servers.

## 🚀 Features

- **Automated Git Operations**: Clone or update repositories with PAT authentication
- **Remote Environment Setup**: Automatic installation of Docker, Docker Compose, and Nginx
- **Flexible Deployment**: Supports both Dockerfile and docker-compose.yml configurations
- **Nginx Reverse Proxy**: Automatic configuration with SSL readiness
- **Comprehensive Validation**: Multi-stage deployment validation and health checks
- **Robust Error Handling**: Trap functions and meaningful exit codes
- **Detailed Logging**: Timestamped logs for all operations
- **Idempotent Operations**: Safe to re-run without breaking existing setups
- **Cleanup Mode**: Easy removal of all deployed resources

## 📋 Prerequisites

### Local Machine Requirements
- Bash 4.0 or higher
- Git
- SSH client
- rsync
- curl

### Remote Server Requirements
- Ubuntu/Debian-based Linux distribution (18.04+)
- SSH access with key-based authentication
- Sudo privileges
- Open ports: 22 (SSH), 80 (HTTP), and your application port

## 🔧 Installation

1. **Clone or download the script**:
```bash
git clone <your-repo-url>
cd <repo-directory>
```

2. **Make the script executable**:
```bash
chmod +x deploy.sh
```

3. **Prepare your SSH key**:
```bash
# Generate a new SSH key if needed
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"

# Copy public key to remote server
ssh-copy-id -i ~/.ssh/id_rsa.pub user@server-ip
```

## 📖 Usage

### Basic Deployment

Run the script and follow the interactive prompts:

```bash
./deploy.sh
```

You will be prompted for:
- **Git Repository URL**: Full HTTPS URL of your repository
- **Personal Access Token (PAT)**: Token with repository read access
- **Branch Name**: Target branch (default: main)
- **SSH Username**: Remote server username
- **Server IP Address**: Remote server IP
- **SSH Key Path**: Path to your private SSH key
- **Application Port**: Internal container port (e.g., 3000, 8080)

### Cleanup Mode

Remove all deployed resources from the remote server:

```bash
./deploy.sh --cleanup
```

This will:
- Stop and remove Docker containers
- Remove Docker images
- Delete Nginx configuration
- Remove application files

### Help

Display usage information:

```bash
./deploy.sh --help
```

## 📁 Project Structure

Your application repository should contain either:

**Option 1: Dockerfile**
```
your-app/
├── Dockerfile
├── src/
└── package.json (or equivalent)
```

**Option 2: docker-compose.yml**
```
your-app/
├── docker-compose.yml
├── Dockerfile (optional)
└── src/
```

## 🔐 Creating a Personal Access Token

### GitHub
1. Go to Settings → Developer settings → Personal access tokens
2. Click "Generate new token (classic)"
3. Select scopes: `repo` (full control)
4. Generate and copy the token

### GitLab
1. Go to Preferences → Access Tokens
2. Create token with `read_repository` scope
3. Copy the token

**Important**: Store your token securely and never commit it to version control.

## 🛠️ What the Script Does

### 1. Input Validation
- Validates URLs, IP addresses, ports, and file paths
- Ensures SSH key is readable and has correct permissions

### 2. Repository Operations
- Clones repository using authenticated HTTPS
- Updates existing repositories
- Switches to specified branch
- Verifies presence of Docker configuration files

### 3. Remote Environment Preparation
- Updates system packages
- Installs Docker and Docker Compose
- Installs and configures Nginx
- Adds user to Docker group
- Enables and starts services

### 4. Application Deployment
- Transfers files via rsync (excluding .git, logs, node_modules)
- Stops and removes existing containers
- Builds new Docker images
- Starts containers with restart policies
- Validates container health

### 5. Nginx Configuration
- Creates reverse proxy configuration
- Forwards HTTP traffic (port 80) to application
- Tests configuration syntax
- Reloads Nginx gracefully

### 6. Validation
- Confirms Docker service status
- Verifies container health
- Tests local and external accessibility
- Logs all validation results

## 📊 Logging

All operations are logged to timestamped files:

```
deploy_YYYYMMDD_HHMMSS.log
```

Log levels:
- **[INFO]**: General information (blue)
- **[SUCCESS]**: Successful operations (green)
- **[WARNING]**: Non-critical issues (yellow)
- **[ERROR]**: Critical failures (red)

## 🔄 Exit Codes

| Code | Description |
|------|-------------|
| 0 | Success |
| 1 | General error or user cancellation |
| 2 | Failed to change directory |
| 3 | Failed to fetch from Git origin |
| 4 | Failed to checkout branch |
| 5 | Failed to pull latest changes |
| 6 | Failed to clone repository |
| 7 | No Docker configuration files found |
| 8 | SSH connection failed |
| 9 | Docker installation failed |
| 10 | Docker Compose installation failed |
| 11 | Nginx installation failed |
| 12 | Failed to start services |
| 13 | File transfer failed |
| 14 | docker-compose deployment failed |
| 15 | Docker build/run failed |
| 16 | Container failed to start |
| 17 | Nginx configuration creation failed |
| 18 | Nginx configuration test failed |
| 19 | Nginx reload failed |
| 20 | Required command not found |

## 🔒 Security Best Practices

1. **SSH Keys**: Use key-based authentication, never passwords
2. **PAT Storage**: Never commit tokens to Git
3. **Firewall**: Configure UFW or iptables appropriately
4. **SSL/TLS**: Add Let's Encrypt certificates for production:
```bash
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d yourdomain.com
```

5. **User Permissions**: Don't run containers as root
6. **Network Isolation**: Use Docker networks
7. **Secrets Management**: Use environment variables or Docker secrets

## 🐛 Troubleshooting

### SSH Connection Failed
```bash
# Test SSH manually
ssh -i ~/.ssh/id_rsa user@server-ip

# Check SSH key permissions
chmod 600 ~/.ssh/id_rsa
```

### Docker Permission Denied
```bash
# On remote server, after adding user to docker group
sudo usermod -aG docker $USER
# Then logout and login again
```

### Container Not Starting
```bash
# Check logs on remote server
docker logs <container-name>

# Check if port is already in use
sudo netstat -tlnp | grep :<port>
```

### Nginx Configuration Error
```bash
# Test configuration manually
sudo nginx -t

# Check error logs
sudo tail -f /var/log/nginx/error.log
```

### Port Already in Use
```bash
# Find process using the port
sudo lsof -i :<port>

# Stop the process
sudo kill <PID>
```

## 🔄 Idempotency

The script is designed to be idempotent:
- Re-running won't break existing deployments
- Old containers are gracefully stopped before new deployment
- Configuration files are overwritten, not duplicated
- Safe to run multiple times for updates

## 📝 Example Deployment Flow

```bash
# 1. Run the script
./deploy.sh

# 2. Provide inputs when prompted
Enter Git Repository URL: https://github.com/username/myapp.git
Enter Personal Access Token (PAT): ghp_xxxxxxxxxxxx
Enter branch name (default: main): main
Enter SSH username: ubuntu
Enter server IP address: 192.168.1.100
Enter SSH key path: ~/.ssh/id_rsa
Enter application internal port: 3000

# 3. Watch the automated deployment
[INFO] Cloning repository...
[SUCCESS] Repository cloned successfully
[INFO] Installing Docker...
[SUCCESS] Docker installed successfully
...
[SUCCESS] DEPLOYMENT COMPLETED SUCCESSFULLY
Application URL: http://192.168.1.100
```

## 🤝 Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Open a Pull Request



## ⚡ Performance Tips

1. **Use .dockerignore**: Exclude unnecessary files from builds
2. **Multi-stage builds**: Reduce image sizes
3. **Layer caching**: Order Dockerfile commands efficiently
4. **Resource limits**: Set memory/CPU limits in docker-compose
5. **Nginx caching**: Configure proxy caching for static assets

## 📚 Additional Resources

- [Docker Documentation](https://docs.docker.com/)