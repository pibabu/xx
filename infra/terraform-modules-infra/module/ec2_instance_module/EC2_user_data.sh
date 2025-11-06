#!/bin/bash
set -e

# Log everything
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "=== Starting user data script ==="
echo "=== Running on Amazon Linux 2023 ==="

# Update and install packages
sudo dnf update -y
sudo dnf install -y python3 python3-pip python3-devel gcc nginx docker

# Install Certbot (AL2023 uses dnf, not amazon-linux-extras)
sudo dnf install -y certbot python3-certbot-nginx

# Start and enable Docker
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -a -G docker ec2-user

# Install docker-compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Setup FastAPI app directory
sudo mkdir -p /home/ec2-user/fastapi-app
sudo chown ec2-user:ec2-user /home/ec2-user/fastapi-app

# Create virtual environment and install Python packages
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
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF

# Test and start Nginx
sudo nginx -t
sudo systemctl enable nginx
sudo systemctl start nginx

# Wait a moment for Nginx to be fully up
sleep 5

echo "=== Obtaining SSL certificate ==="
# Obtain certificate (this will auto-configure Nginx for HTTPS)
sudo certbot --nginx -d ey-ios.com --non-interactive --agree-tos -m admin@ey-ios.com --redirect

# Setup auto-renewal
echo "0 3 * * * root certbot renew --quiet && systemctl reload nginx" | sudo tee /etc/cron.d/certbot-renew

# Verify services are running
echo "=== Service Status Check ==="
sudo systemctl status nginx --no-pager
sudo systemctl status docker --no-pager

echo "=== User data script completed successfully ==="

### set ###


    #!/bin/bash
# Fetch SSL cert from SSM
aws ssm get-parameter \
  --name "/fastapi-app/ssl-cert" \
  --with-decryption \
  --region eu-central-1 \
  --query 'Parameter.Value' \
  --output text > /etc/ssl/certs/my-cert.pem

# Fetch private key
aws ssm get-parameter \
  --name "/fastapi-app/ssl-key" \
  --with-decryption \
  --region eu-central-1 \
  --query 'Parameter.Value' \
  --output text > /etc/ssl/private/my-key.pem

# Set proper permissions
chmod 644 /etc/ssl/certs/my-cert.pem
chmod 600 /etc/ssl/private/my-key.pem

#!/bin/bash

# Fetch OpenAI API key from SSM
OPENAI_API_KEY=$(aws ssm get-parameter \
  --name "/fastapi-app/openai-api-key" \
  --region eu-central-1 \
  --query 'Parameter.Value' \
  --output text)

# Export as environment variable
export OPENAI_API_KEY="$OPENAI_API_KEY"

# Or write to .env file for your FastAPI app
echo "OPENAI_API_KEY=$OPENAI_API_KEY" > /home/ubuntu/fastapi-app/.env

# Set proper permissions
chmod 600 /home/ubuntu/fastapi-app/.env
chown ubuntu:ubuntu /home/ubuntu/fastapi-app/.env