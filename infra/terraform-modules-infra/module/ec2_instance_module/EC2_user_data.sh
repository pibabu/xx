#!/bin/bash
set -e

# ==========================================
# CONFIGURATION
# ==========================================
REGION="eu-central-1"
DOMAIN="ey-ios.com"
ADMIN_EMAIL="admin@ey-ios.com"
APP_DIR="/home/ec2-user/fastapi-app"
APP_USER="ec2-user"
APP_PORT=8000
USER_DATA_MOUNT="/mnt/user-data"

# ==========================================
# LOGGING SETUP
# ==========================================
exec > >(tee /var/log/user-data.log)
exec 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "=== Starting user data script ==="
log "=== Running on Amazon Linux 2023 ==="

# ==========================================
# EBS VOLUME SETUP
# ==========================================
log "Setting up EBS volume for user data..."

# Wait for the additional volume to attach (typically /dev/nvme1n1 on Nitro instances)
log "Waiting for EBS volume to attach..."
DEVICE="/dev/nvme1n1"
TIMEOUT=60
ELAPSED=0

while [ ! -e "$DEVICE" ] && [ $ELAPSED -lt $TIMEOUT ]; do
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    log "Waiting for $DEVICE... (${ELAPSED}s)"
done

if [ ! -e "$DEVICE" ]; then
    log "ERROR: EBS volume did not attach within ${TIMEOUT} seconds"
    log "Continuing without user data volume..."
else
    log "EBS volume detected at $DEVICE"
    
    # Check if filesystem already exists
    if ! blkid "$DEVICE" > /dev/null 2>&1; then
        log "Formatting new EBS volume with ext4..."
        sudo mkfs -t ext4 "$DEVICE"
        log "Filesystem created successfully"
    else
        log "Existing filesystem detected on $DEVICE"
    fi
    
    # Create mount point
    log "Creating mount point at $USER_DATA_MOUNT..."
    sudo mkdir -p "$USER_DATA_MOUNT"
    
    # Mount the volume
    log "Mounting EBS volume..."
    sudo mount "$DEVICE" "$USER_DATA_MOUNT"
    
    # Get UUID for fstab
    UUID=$(sudo blkid -s UUID -o value "$DEVICE")
    log "Volume UUID: $UUID"
    
    # Add to fstab for automatic mount on reboot (if not already present)
    if ! grep -q "$UUID" /etc/fstab; then
        log "Adding entry to /etc/fstab for automatic mounting..."
        echo "UUID=$UUID $USER_DATA_MOUNT ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
    else
        log "fstab entry already exists"
    fi
    
    # Create directory structure for user data
    log "Creating user data directory structure..."
    sudo mkdir -p "$USER_DATA_MOUNT/users"
    sudo mkdir -p "$USER_DATA_MOUNT/shared"
    sudo mkdir -p "$USER_DATA_MOUNT/uploads"
    sudo mkdir -p "$USER_DATA_MOUNT/temp"
    
    # Set permissions
    sudo chmod 755 "$USER_DATA_MOUNT/users"
    sudo chmod 755 "$USER_DATA_MOUNT/shared"
    sudo chmod 755 "$USER_DATA_MOUNT/uploads"
    sudo chmod 1777 "$USER_DATA_MOUNT/temp"  # Sticky bit for temp directory
    
    # Set ownership
    sudo chown -R $APP_USER:$APP_USER "$USER_DATA_MOUNT"
    
    log "User data volume setup completed successfully"
    log "Mount point: $USER_DATA_MOUNT"
    log "Available space: $(df -h $USER_DATA_MOUNT | tail -1 | awk '{print $4}')"
fi

# ==========================================
# SYSTEM UPDATES & PACKAGE INSTALLATION
# ==========================================
log "Installing system packages..."
sudo dnf update -y
sudo dnf install -y \
    python3 \
    python3-pip \
    python3-devel \
    gcc \
    nginx \
    docker \
    aws-cli

# ==========================================
# DOCKER SETUP
# ==========================================
log "Configuring Docker..."
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -a -G docker $APP_USER

# Install docker-compose
log "Installing docker-compose..."
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# ==========================================
# APPLICATION DIRECTORY SETUP
# ==========================================
log "Setting up application directory..."
sudo mkdir -p $APP_DIR
sudo chown $APP_USER:$APP_USER $APP_DIR

# ==========================================
# PYTHON ENVIRONMENT SETUP
# ==========================================
log "Creating Python virtual environment..."
sudo -u $APP_USER python3 -m venv $APP_DIR/venv
sudo -u $APP_USER $APP_DIR/venv/bin/pip install --upgrade pip
sudo -u $APP_USER $APP_DIR/venv/bin/pip install \
    fastapi \
    uvicorn[standard] \
    websockets \
    openai \
    pydantic \
    python-dotenv \
    supervisor

# ==========================================
# FETCH SECRETS FROM SSM PARAMETER STORE
# ==========================================
log "Fetching secrets from SSM Parameter Store..."

# Fetch OpenAI API key
set +e  # Don't exit on error for SSM fetch
OPENAI_API_KEY=$(aws ssm get-parameter \
    --name "/fastapi-app/openai-api-key" \
    --region $REGION \
    --query 'Parameter.Value' \
    --output text 2>/dev/null)

if [ -z "$OPENAI_API_KEY" ] || [ "$OPENAI_API_KEY" = "None" ]; then
    log "WARNING: Could not fetch OPENAI_API_KEY from Parameter Store"
    log "Please ensure the parameter exists: /fastapi-app/openai-api-key"
else
    log "Successfully fetched OPENAI_API_KEY"
    # Create .env file
    sudo -u $APP_USER tee $APP_DIR/.env > /dev/null <<EOF
OPENAI_API_KEY=$OPENAI_API_KEY
USER_DATA_PATH=$USER_DATA_MOUNT
EOF
    sudo chmod 600 $APP_DIR/.env
    sudo chown $APP_USER:$APP_USER $APP_DIR/.env
fi

# Fetch SSL certificate
SSL_CERT=$(aws ssm get-parameter \
    --name "/fastapi-app/ssl-cert" \
    --with-decryption \
    --region $REGION \
    --query 'Parameter.Value' \
    --output text 2>/dev/null)

SSL_KEY=$(aws ssm get-parameter \
    --name "/fastapi-app/ssl-key" \
    --with-decryption \
    --region $REGION \
    --query 'Parameter.Value' \
    --output text 2>/dev/null)

if [ -z "$SSL_CERT" ] || [ "$SSL_CERT" = "None" ] || [ -z "$SSL_KEY" ] || [ "$SSL_KEY" = "None" ]; then
    log "ERROR: SSL certificates not found in SSM Parameter Store"
    log "Please create parameters: /fastapi-app/ssl-cert and /fastapi-app/ssl-key"
    exit 1
fi

log "Installing SSL certificates from SSM..."
sudo mkdir -p /etc/pki/tls/private
echo "$SSL_CERT" | sudo tee /etc/pki/tls/certs/my-cert.pem > /dev/null
echo "$SSL_KEY" | sudo tee /etc/pki/tls/private/my-key.pem > /dev/null
sudo chmod 644 /etc/pki/tls/certs/my-cert.pem
sudo chmod 600 /etc/pki/tls/private/my-key.pem
set -e  # Re-enable exit on error

# ==========================================
# NGINX CONFIGURATION
# ==========================================
log "Configuring Nginx..."

sudo tee /etc/nginx/conf.d/fastapi.conf > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;     
    http2 on; 
    server_name $DOMAIN;

    ssl_certificate /etc/pki/tls/certs/my-cert.pem;
    ssl_certificate_key /etc/pki/tls/private/my-key.pem;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # Increase client body size for file uploads
    client_max_body_size 100M;

    location / {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        
        # WebSocket timeouts
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
}
EOF

# ==========================================
# START NGINX
# ==========================================
log "Starting Nginx..."
sudo nginx -t
sudo systemctl enable nginx
sudo systemctl start nginx

# ==========================================
# IAM ROLE VERIFICATION
# ==========================================
log "Verifying IAM role and SSM access..."
aws sts get-caller-identity || log "WARNING: AWS credentials may not be configured"

# ==========================================
# SERVICE STATUS CHECK
# ==========================================
log "=== Service Status Check ==="
sudo systemctl status nginx --no-pager || true
sudo systemctl status docker --no-pager || true

# ==========================================
# FINAL MOUNT STATUS
# ==========================================
if [ -d "$USER_DATA_MOUNT" ]; then
    log "=== EBS Volume Mount Status ==="
    df -h "$USER_DATA_MOUNT" || true
    log "=== User Data Directory Structure ==="
    ls -la "$USER_DATA_MOUNT" || true
fi

log "=== User data script completed successfully ==="
log "=== Next steps: Deploy your FastAPI application ==="
log "=== Application directory: $APP_DIR ==="
log "=== Environment file: $APP_DIR/.env ==="
log "=== User data storage: $USER_DATA_MOUNT ==="