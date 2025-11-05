#!/bin/bash
set -e

# kein nginx, kein certbot -->   deploy script schlägt fehl


# Update and install packages
sudo yum update -y
sudo yum install -y python3 python3-pip python3-devel gcc nginx docker

# Start and enable Docker + Nginx
sudo systemctl enable --now docker
sudo systemctl enable --now nginx

# Add ec2-user to docker group
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

# Write your Nginx config
sudo tee /etc/nginx/conf.d/fastapi.conf > /dev/null <<'EOF'
server {
    server_name ey-ios.com;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }

    listen 443 ssl;
    ssl_certificate /etc/letsencrypt/live/ey-ios.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/ey-ios.com/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
}

server {
    if ($host = ey-ios.com) {
        return 301 https://$host$request_uri;
    }
    listen 80;
    server_name ey-ios.com;
    return 404;
}
EOF

sudo nginx -t
sudo systemctl restart nginx



# Install Certbot and generate certificates
sudo amazon-linux-extras install epel -y
sudo yum install -y certbot python3-certbot-nginx

# Obtain certificate (replace email with yours)
sudo certbot --nginx -d ey-ios.com --non-interactive --agree-tos -m admin@ey-ios.com

# Enable auto-renewal
echo "0 3 * * * root certbot renew --quiet && systemctl reload nginx" | sudo tee /etc/cron.d/certbot-renew
