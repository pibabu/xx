#!/bin/bash
# Deployment script for FastAPI WebSocket application
# This runs on EC2 via AWS CodePipeline (SSM agent)

set -e  # Exit immediately if any command fails
set -u  # Exit if undefined variable is used

# ==========================================
# CONFIGURATION
# ==========================================
APP_DIR="/home/ubuntu/fastapi-app"
LOG_FILE="/var/log/fastapi-deploy.log"
APP_USER="ubuntu"
PYTHON_BIN="/usr/bin/python3"
VENV_DIR="$APP_DIR/venv"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=========================================="
log "Starting deployment process"
log "=========================================="

# ==========================================
# STEP 1: Setup Application Directory
# ==========================================
# Why: We need a persistent location for our app
# CodePipeline extracts files to a temporary location, we copy to permanent one

log "Step 1: Setting up application directory"

if [ ! -d "$APP_DIR" ]; then
    log "Creating app directory: $APP_DIR"
    sudo mkdir -p "$APP_DIR"
    sudo chown $APP_USER:$APP_USER "$APP_DIR"
else
    log "App directory already exists"
fi

# ==========================================
# STEP 2: Copy New Code
# ==========================================
# Why: CodePipeline extracted your repo to current directory
# We need to copy it to our permanent app location

log "Step 2: Copying application files"

# Current directory contains your repo files
log "Current directory: $(pwd)"
log "Files in current directory:"
ls -la

# Copy everything to app directory (excluding .git if present)
log "Copying files to $APP_DIR"
rsync -av --exclude='.git' --exclude='venv' ./ "$APP_DIR/"

# Set proper permissions
sudo chown -R $APP_USER:$APP_USER "$APP_DIR"

log "Files copied successfully"

# ==========================================
# STEP 3: Setup Python Virtual Environment
# ==========================================
# Why: Isolate dependencies from system Python
# Prevents conflicts and makes dependency management clean

log "Step 3: Setting up Python virtual environment"

cd "$APP_DIR"

if [ ! -d "$VENV_DIR" ]; then
    log "Creating new virtual environment"
    $PYTHON_BIN -m venv "$VENV_DIR"
else
    log "Virtual environment already exists"
fi

# Activate virtual environment
# Why: All pip installs and python commands use this isolated environment
source "$VENV_DIR/bin/activate"

log "Virtual environment activated: $(which python)"

# ==========================================
# STEP 4: Install/Update Dependencies
# ==========================================
# Why: Install FastAPI, OpenAI SDK, and other requirements
# This reads your requirements.txt

log "Step 4: Installing Python dependencies"

# Upgrade pip first
# Why: Older pip versions can have issues with newer packages
pip install --upgrade pip

# Install requirements
# Why: This installs fastapi, openai, uvicorn, websockets, etc.
if [ -f "requirements.txt" ]; then
    log "Installing from requirements.txt"
    pip install -r requirements.txt
    log "Dependencies installed successfully"
else
    log "ERROR: requirements.txt not found!"
    exit 1
fi

# ==========================================
# STEP 5: Setup Environment Variables
# ==========================================
# Why: Your app needs OPENAI_API_KEY and other secrets
# Don't commit these to git!

log "Step 5: Setting up environment variables"

# Check if .env file exists
# You should manually create this on EC2 with your secrets
if [ ! -f "$APP_DIR/.env" ]; then
    log "WARNING: .env file not found!"
    log "Creating placeholder .env - YOU MUST UPDATE THIS WITH REAL VALUES"
    cat > "$APP_DIR/.env" << 'EOF'
OPENAI_API_KEY=your_openai_api_key_here
# Add other environment variables as needed
EOF
    log "Please update $APP_DIR/.env with real values!"
else
    log ".env file exists"
fi

# ==========================================
# STEP 6: Stop Old Application Process
# ==========================================
# Why: We need to restart the app with new code
# Kill old process gracefully

log "Step 6: Stopping old application process"

# Find and kill any running uvicorn processes for this app
# Why: pkill finds processes by name pattern
if pgrep -f "uvicorn app:app" > /dev/null; then
    log "Found running application process, stopping it..."
    pkill -f "uvicorn app:app" || true
    
    # Wait for process to die
    sleep 2
    
    # Force kill if still running
    if pgrep -f "uvicorn app:app" > /dev/null; then
        log "Force killing stubborn process"
        pkill -9 -f "uvicorn app:app" || true
    fi
    
    log "Old process stopped"
else
    log "No running process found"
fi

# ==========================================
# STEP 7: Start New Application
# ==========================================
# Why: Launch your FastAPI app with the new code

log "Step 7: Starting new application"

cd "$APP_DIR"

# Start uvicorn in background
# Why each flag:
# - uvicorn: ASGI server for FastAPI
# - app:app: module_name:app_instance (your app.py file, FastAPI() instance)
# - --host 0.0.0.0: Listen on all network interfaces (allows external access)
# - --port 8000: Port to listen on
# - nohup: Keeps running after SSH disconnect
# - > /var/log/fastapi.log: Redirect stdout to log file
# - 2>&1: Redirect stderr to same log file
# - &: Run in background

log "Starting uvicorn server"
nohup "$VENV_DIR/bin/python" -m uvicorn app:app \
    --host 0.0.0.0 \
    --port 8000 \
    --log-level info \
    > /var/log/fastapi.log 2>&1 &

# Save the process ID
APP_PID=$!
log "Application started with PID: $APP_PID"

# Wait a moment for app to start
sleep 3

# ==========================================
# STEP 8: Verify Application is Running
# ==========================================
# Why: Make sure deployment actually worked

log "Step 8: Verifying application"

if pgrep -f "uvicorn app:app" > /dev/null; then
    log "✓ Application is running"
    
    # Try to curl the health endpoint
    if curl -f http://localhost:8000/ > /dev/null 2>&1; then
        log "✓ Application responding to HTTP requests"
    else
        log "⚠ Application running but not responding yet (may still be starting)"
    fi
else
    log "✗ ERROR: Application failed to start!"
    log "Check logs: tail -f /var/log/fastapi.log"
    exit 1
fi

# ==========================================
# DEPLOYMENT COMPLETE
# ==========================================

log "=========================================="
log "Deployment completed successfully!"
log "=========================================="
log "Application directory: $APP_DIR"
log "Application logs: /var/log/fastapi.log"
log "Application URL: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8000"
log "To view logs: tail -f /var/log/fastapi.log"
log "To check status: pgrep -f 'uvicorn app:app'"

exit 0