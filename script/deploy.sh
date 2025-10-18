#!/bin/bash
# Deployment script for FastAPI WebSocket application
# Runs on EC2 via AWS CodePipeline + SSM agent

set -e  # Exit on error (we'll disable for non-critical commands)
set -u  # Exit on undefined variables

# ==========================================
# CONFIGURATION
# ==========================================
APP_DIR="/home/ec2-user/fastapi-app"
LOG_FILE="/var/log/fastapi-deploy.log"
APP_USER="ec2-user"
PYTHON_BIN="/usr/bin/python3"
VENV_DIR="$APP_DIR/venv"

export OPENAI_API_KEY="${OPENAI_API_KEY}"


log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=========================================="
log "Starting deployment process"
log "=========================================="

# ==========================================
# STEP 1: Setup Application Directory
# ==========================================
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
# CodePipeline extracts your GitHub repo to current working directory
# We need to copy it to our permanent app location
log "Step 2: Copying application files"

log "Current directory: $(pwd)"
log "Files in current directory:"
ls -la

log "Copying files to $APP_DIR"
rsync -av --exclude='.git' --exclude='venv' ./ "$APP_DIR/"

sudo chown -R $APP_USER:$APP_USER "$APP_DIR"

log "Files copied successfully"

# ==========================================
# STEP 3: Setup Python Virtual Environment
# ==========================================
# Your AMI already created this via user data
# This just ensures it exists if AMI didn't run properly
log "Step 3: Setting up Python virtual environment"

cd "$APP_DIR"

if [ ! -d "$VENV_DIR" ]; then
    log "Creating new virtual environment"
    $PYTHON_BIN -m venv "$VENV_DIR"
else
    log "Virtual environment already exists"
fi

source "$VENV_DIR/bin/activate"

log "Virtual environment activated: $(which python)"

# ==========================================
# STEP 4: Install/Update Dependencies
# ==========================================
# CRITICAL FIX: Removed --no-deps flag
# --no-deps prevents installing sub-dependencies which breaks packages
log "Step 4: Checking Python dependencies"

if [ -f "requirements.txt" ]; then
    log "Found requirements.txt, updating dependencies"
    pip install --upgrade -r requirements.txt
    log "Dependencies updated successfully"
else
    log "No requirements.txt found, using AMI pre-installed packages"
fi

# ==========================================
# STEP 5: Verify Critical Files
# ==========================================
log "Step 5: Verifying application files"

if [ ! -f "app.py" ]; then
    log "ERROR: app.py not found in $APP_DIR"
    log "Directory contents:"
    ls -la "$APP_DIR"
    exit 1
fi

log "✓ app.py found"

# ==========================================
# STEP 6: Stop Old Application Process
# ==========================================
# CRITICAL FIX: Disable 'set -e' because pkill returns exit code 1
# if no process found, which would stop the whole script
log "Step 6: Stopping old application process"

set +e  # Don't exit on error for this section

if pgrep -f "uvicorn app:app" > /dev/null; then
    log "Found running application process, stopping it..."
    
    pkill -f "uvicorn app:app"  # Send SIGTERM (graceful)
    sleep 3
    
    if pgrep -f "uvicorn app:app" > /dev/null; then
        log "Process still running, force killing..."
        pkill -9 -f "uvicorn app:app"  # Send SIGKILL (force)
        sleep 1
    fi
    
    log "Old process stopped"
else
    log "No running process found (this is fine)"
fi

set -e  # Re-enable exit on error

# ==========================================
# STEP 7: Start New Application
# ==========================================
log "Step 7: Starting new application"

cd "$APP_DIR"

log "Starting uvicorn server"
nohup "$VENV_DIR/bin/python" -m uvicorn app:app \
    --host 0.0.0.0 \
    --port 8000 \
    --log-level info \
    > /var/log/fastapi.log 2>&1 &

APP_PID=$!
log "Application started with PID: $APP_PID"

sleep 5  # Give app time to start

# ==========================================
# STEP 8: Verify Application is Running
# ==========================================
log "Step 8: Verifying application"

if pgrep -f "uvicorn app:app" > /dev/null; then
    log "✓ Application process is running"
    
    set +e  # Don't exit if curl fails
    
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/ 2>/dev/null || echo "000")
    
    if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 500 ]; then
        log "✓ Application responding to HTTP requests (HTTP $HTTP_CODE)"
    else
        log "⚠ Application running but may not be ready yet (HTTP $HTTP_CODE)"
        log "Check logs: tail -f /var/log/fastapi.log"
        log "Last 20 lines of application log:"
        tail -n 20 /var/log/fastapi.log | tee -a "$LOG_FILE"
    fi
    
    set -e
else
    log "✗ ERROR: Application failed to start!"
    log "=== Last 30 lines of application log ==="
    tail -n 30 /var/log/fastapi.log | tee -a "$LOG_FILE"
    log "======================================="
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

PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "unknown")
log "Application URL: http://$PUBLIC_IP:8000"

log "Useful commands:"
log "  View logs: tail -f /var/log/fastapi.log"
log "  Check process: pgrep -f 'uvicorn app:app'"
log "  Stop app: pkill -f 'uvicorn app:app'"

exit 0