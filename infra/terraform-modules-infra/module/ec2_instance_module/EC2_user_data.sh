#!/bin/bash
set -e

# Log everything
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "=== Starting user data script ==="

# Update and install packages
sudo yum update -y
sudo yum install -y python3 python3-pip python3-devel gcc nginx docker

# Install Certbot FIRST (before configuring Nginx)
sudo amazon-linux-extras install epel -y
sudo yum install -y certbot python3-certbot-nginx

# Start and enable Docker
sudo systemctl enable --now docker
sudo usermod -a -G docker ec2-user

# Install docker-compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Setup FastAPI app
sudo mkdir -p /home/ec2-user/fastapi-app
sudo chown ec2-user:ec2-user /home/ec2-user/fastapi-app

sudo -u ec2-user python3 -m venv /home/ec2-user/fastapi-app/venv
sudo -u ec2-user /home/ec2-user/fastapi-app/venv/bin/pip install --upgrade pip
sudo -u ec2-user /home/ec2-user/fastapi-app/venv/bin/pip install fastapi uvicorn[standard] websockets openai pydantic python-dotenv

# Create TEMPORARY HTTP-only Nginx config for Certbot
sudo tee /etc/nginx/conf.d/fastapi.conf > /dev/null <<'EOF'
server {
    listen 80;
    server_name ey-ios.com;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF

# Start Nginx with HTTP-only config
sudo nginx -t
sudo systemctl enable --now nginx

echo "=== Obtaining SSL certificate ==="
# Obtain certificate (this will auto-configure Nginx for HTTPS)
sudo certbot --nginx -d ey-ios.com --non-interactive --agree-tos -m admin@ey-ios.com --redirect

# Enable auto-renewal
echo "0 3 * * * root certbot renew --quiet && systemctl reload nginx" | sudo tee /etc/cron.d/certbot-renew

echo "=== User data script completed successfully ==="