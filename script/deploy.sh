#!/bin/bash

################################################################################
# FastAPI WebSocket Chat - EC2 Deployment Script
# Used by AWS CodePipeline/CodeDeploy
################################################################################

set -e  # Exit immediately if any command fails
set -o pipefail  # Catch errors in pipes

# Color output for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

################################################################################
# Configuration
################################################################################

APP_DIR="/home/ubuntu/fastapi-chat"
VENV_DIR="$APP_DIR/venv"
SERVICE_NAME="fastapi-chat"
PYTHON_VERSION="python3.11"  # Adjust to your Python version
APP_USER="ubuntu"
APP_PORT="8000"

log_info "Starting deployment to $APP_DIR"

################################################################################
# Step 1: Install System Dependencies
################################################################################

log_info "Step 1: Installing system dependencies..."

# Update package lists
sudo apt-get update -y

# Install Python and essential build tools
# - python3.11: Your application runtime
# - python3.11-venv: Virtual environment support
# - python3-pip: Package installer
# - nginx: Reverse proxy (optional but recommended)
# - supervisor: Process manager to keep app running
sudo apt-get install -y \
    $PYTHON_VERSION \
    ${PYTHON_VERSION}-venv \
    python3-pip \
    nginx \
    supervisor

log_info "✓ System dependencies installed"

################################################################################
# Step 2: Create Application Directory Structure
################################################################################

log_info "Step 2: Setting up application directory..."

# Create app directory if it doesn't exist
# -p flag: creates parent directories if needed, no error if exists
sudo mkdir -p $APP_DIR

# Copy application files from CodeDeploy staging area
# CodePipeline puts files in /opt/codedeploy-agent/deployment-root/...
# We assume they're in current directory during deployment
sudo cp -r . $APP_DIR/

# Set ownership to application user
# This ensures the app runs with proper permissions (not root)
sudo chown -R $APP_USER:$APP_USER $APP_DIR

log_info "✓ Application files copied to $APP_DIR"

################################################################################
# Step 3: Setup Python Virtual Environment
################################################################################

log_info "Step 3: Creating Python virtual environment..."

cd $APP_DIR

# Remove old virtual environment if it exists
# This ensures clean installation of dependencies
if [ -d "$VENV_DIR" ]; then
    log_warn "Removing old virtual environment..."
    sudo rm -rf $VENV_DIR
fi

# Create new virtual environment
# Virtual environments isolate Python packages from system Python
# This prevents version conflicts and allows per-project dependencies
sudo -u $APP_USER $PYTHON_VERSION -m venv $VENV_DIR

log_info "✓ Virtual environment created"

################################################################################
# Step 4: Install Python Dependencies
################################################################################

log_info "Step 4: Installing Python dependencies..."

# Activate virtual environment and install packages
# We use the venv's pip to ensure packages go into the virtual environment
sudo -u $APP_USER $VENV_DIR/bin/pip install --upgrade pip

# Install application dependencies from requirements.txt
# --no-cache-dir: Reduces disk space usage
sudo -u $APP_USER $VENV_DIR/bin/pip install --no-cache-dir -r $APP_DIR/requirements.txt

log_info "✓ Python dependencies installed"

################################################################################
# Step 5: Configure Environment Variables
################################################################################

log_info "Step 5: Configuring environment variables..."

# Create .env file with sensitive configuration
# In production, these should come from AWS Secrets Manager or Parameter Store
# For now, we'll create a template and rely on AWS Systems Manager
sudo tee $APP_DIR/.env > /dev/null <<EOF
# OpenAI API Key - Replace with actual key or use AWS Secrets Manager
OPENAI_API_KEY=\${OPENAI_API_KEY}

# Application Settings
APP_ENV=production
APP_PORT=$APP_PORT
LOG_LEVEL=info
EOF

# Set proper permissions (read/write for owner only)
# 600 means: owner can read/write, group and others have no access
sudo chmod 600 $APP_DIR/.env
sudo chown $APP_USER:$APP_USER $APP_DIR/.env

log_info "✓ Environment variables configured"

################################################################################
# Step 6: Configure Supervisor (Process Manager)
################################################################################

log_info "Step 6: Configuring Supervisor process manager..."

# Supervisor keeps your application running
# It automatically restarts the app if it crashes
# It manages logs and provides easy start/stop/restart commands

sudo tee /etc/supervisor/conf.d/$SERVICE_NAME.conf > /dev/null <<EOF
[program:$SERVICE_NAME]
# Command to run your FastAPI app with Uvicorn
# --host 0.0.0.0: Listen on all network interfaces
# --port $APP_PORT: Port to bind to
# --workers 4: Number of worker processes (adjust based on CPU cores)
# --ws websockets: Enable WebSocket support (critical for your chat app)
command=$VENV_DIR/bin/uvicorn main:app --host 0.0.0.0 --port $APP_PORT --workers 4 --ws websockets

# Working directory
directory=$APP_DIR

# Run as non-root user for security
user=$APP_USER

# Auto-start on system boot
autostart=true

# Auto-restart if process crashes
autorestart=true

# Consider failed if process exits in < 10 seconds
startsecs=10

# Send SIGTERM to stop, then SIGKILL after 10s
stopsignal=TERM
stopwaitsecs=10

# Logging configuration
stdout_logfile=/var/log/supervisor/$SERVICE_NAME.log
stdout_logfile_maxbytes=50MB
stdout_logfile_backups=10
stderr_logfile=/var/log/supervisor/$SERVICE_NAME.error.log
stderr_logfile_maxbytes=50MB
stderr_logfile_backups=10

# Load environment variables from .env file
environment=OPENAI_API_KEY="%(ENV_OPENAI_API_KEY)s"
EOF

log_info "✓ Supervisor configuration created"

################################################################################
# Step 7: Configure Nginx (Reverse Proxy)
################################################################################

log_info "Step 7: Configuring Nginx reverse proxy..."

# Nginx sits in front of your FastAPI app
# Benefits: SSL termination, load balancing, static file serving, security
sudo tee /etc/nginx/sites-available/$SERVICE_NAME > /dev/null <<'EOF'
server {
    listen 80;
    server_name _;  # Replace with your domain name

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Main application proxy
    location / {
        # Forward requests to FastAPI app
        proxy_pass http://127.0.0.1:8000;
        
        # Preserve original request headers
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # WebSocket configuration - CRITICAL for /ws endpoint
    location /ws {
        proxy_pass http://127.0.0.1:8000;
        
        # WebSocket specific headers
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Preserve headers
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        
        # Long timeouts for WebSocket connections
        proxy_connect_timeout 7d;
        proxy_send_timeout 7d;
        proxy_read_timeout 7d;
    }

    # Health check endpoint
    location /health {
        proxy_pass http://127.0.0.1:8000/health;
        access_log off;  # Don't log health checks
    }
}
EOF

# Enable the site by creating symbolic link
sudo ln -sf /etc/nginx/sites-available/$SERVICE_NAME /etc/nginx/sites-enabled/

# Remove default Nginx site
sudo rm -f /etc/nginx/sites-enabled/default

# Test Nginx configuration for syntax errors
sudo nginx -t

log_info "✓ Nginx configuration created"

################################################################################
# Step 8: Restart Services
################################################################################

log_info "Step 8: Restarting services..."

# Reload Supervisor to pick up new configuration
sudo supervisorctl reread
sudo supervisorctl update

# Restart application
sudo supervisorctl restart $SERVICE_NAME

# Restart Nginx
sudo systemctl restart nginx

# Enable services to start on boot
sudo systemctl enable supervisor
sudo systemctl enable nginx

log_info "✓ Services restarted"

################################################################################
# Step 9: Health Check
################################################################################

log_info "Step 9: Performing health check..."

# Wait for application to start
sleep 5

# Check if application is responding
# curl -f: fail on HTTP errors
# --retry: retry if connection fails
# --retry-delay: wait between retries
if curl -f --retry 5 --retry-delay 2 http://localhost:$APP_PORT/health > /dev/null 2>&1; then
    log_info "✓ Health check passed - Application is running!"
else
    log_error "Health check failed - Application may not be running correctly"
    log_error "Check logs: sudo tail -f /var/log/supervisor/$SERVICE_NAME.log"
    exit 1
fi

################################################################################
# Step 10: Display Service Status
################################################################################

log_info "Deployment completed successfully!"
echo ""
log_info "Service Status:"
sudo supervisorctl status $SERVICE_NAME
echo ""
log_info "Useful Commands:"
echo "  View logs:        sudo tail -f /var/log/supervisor/$SERVICE_NAME.log"
echo "  Restart app:      sudo supervisorctl restart $SERVICE_NAME"
echo "  Stop app:         sudo supervisorctl stop $SERVICE_NAME"
echo "  Start app:        sudo supervisorctl start $SERVICE_NAME"
echo "  Nginx logs:       sudo tail -f /var/log/nginx/access.log"
echo "  Check status:     sudo supervisorctl status"
echo ""
log_info "Application accessible at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"