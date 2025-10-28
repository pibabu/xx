#!/bin/bash
# Deployment script for FastAPI WebSocket application
# Runs on EC2 via AWS CodePipeline + SSM agent
# With Nginx reverse proxy for ey-ios.com

set -u  # Exit on undefined variables

# ==========================================
# TRIGGER FLAG - Set to true to enable user creation
# ==========================================
CREATE_RANDOM_USER=true  # Change to false to disable user creation

# ==========================================
# CONFIGURATION 
# ==========================================
APP_DIR="/home/ec2-user/fastapi-app"
LOG_FILE="/var/log/fastapi-deploy.log"
APP_USER="ec2-user"
PYTHON_BIN="/usr/bin/python3"
VENV_DIR="$APP_DIR/venv"
APP_PORT=8000 

# ==========================================
# LOGGING FUNCTION
# ==========================================
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=========================================="
log "Starting deployment process"
log "User creation trigger: $CREATE_RANDOM_USER"
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
log "Step 2: Copying application files"

log "Current directory: $(pwd)"
log "Files in current directory:"
ls -la

log "Copying files to $APP_DIR"
rsync -av --exclude='.git' --exclude='venv' --exclude='.env' ./ "$APP_DIR/"

sudo chown -R $APP_USER:$APP_USER "$APP_DIR"

log "Setting execute permissions for scripts"
find "$APP_DIR" -type f -name "*.sh" -exec chmod +x {} \;

log "Files copied and permissions set successfully"


# ==========================================
# STEP 3: Create .env from AWS Systems Manager Parameter Store
# ==========================================



set +e

# Try to fetch from Parameter Store
OPENAI_KEY=$(aws ssm get-parameter --name "/fastapi-app/openai-api-key" --with-decryption --query "Parameter.Value" --output text 2>/dev/null)

if [ -z "$OPENAI_KEY" ] || [ "$OPENAI_KEY" = "None" ]; then
    log "WARNING: Could not fetch OPENAI_API_KEY from Parameter Store"
    log "Checking for existing .env file..."
    
    if [ ! -f "$APP_DIR/.env" ]; then
        log "ERROR: No .env file found and Parameter Store unavailable"
        log "Please create Parameter Store entry: /fastapi-app/openai-api-key"
        exit 1
    else
        log "Using existing .env file"
    fi
else
    log "Creating .env file from Parameter Store..."
    cat > $APP_DIR/.env << EOF
OPENAI_API_KEY=$OPENAI_KEY
APP_PORT=$APP_PORT
APP_HOST=0.0.0.0
DOMAIN=ey-ios.com
EOF
    
    # Secure the .env file
    chmod 600 $APP_DIR/.env
    chown $APP_USER:$APP_USER $APP_DIR/.env
    
    log ".env file created successfully"
fi

set -e

# ==========================================
# STEP 4: Setup Python Virtual Environment
# ==========================================
log "Step 4: Setting up Python virtual environment"

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
# STEP 5: Install/Update Dependencies
# ==========================================
log "Step 5: Checking Python dependencies"

if [ -f "requirements.txt" ]; then
    log "Found requirements.txt, updating dependencies"
    pip install --upgrade pip
    pip install --upgrade -r requirements.txt
    log "Dependencies updated successfully"
else
    log "WARNING: No requirements.txt found"
fi

# ==========================================
# STEP 6: Verify Critical Files
# ==========================================
log "Step 6: Verifying application files"

if [ ! -f "app.py" ]; then
    log "ERROR: app.py not found in $APP_DIR"
    log "Directory contents:"
    ls -la "$APP_DIR"
    exit 1
fi

log "✓ app.py found"

# ==========================================
# STEP 7: Stop Old Application Process
# ==========================================
log "Step 7: Stopping old application process"

set +e

if pgrep -f "uvicorn app:app" > /dev/null; then
    log "Found running application process, stopping it..."
    
    pkill -f "uvicorn app:app"
    sleep 3
    
    if pgrep -f "uvicorn app:app" > /dev/null; then
        log "Process still running, force killing..."
        pkill -9 -f "uvicorn app:app"
        sleep 1
    fi
    
    log "Old process stopped"
else
    log "No running process found (this is fine)"
fi

set -e

# ==========================================
# STEP 8: Start New Application
# ==========================================
log "Step 8: Starting new application"

cd "$APP_DIR"

# Create logs directory if it doesn't exist
mkdir -p "$APP_DIR/logs"

log "Starting uvicorn server on port $APP_PORT"
nohup "$VENV_DIR/bin/python" -m uvicorn app:app \
    --host 0.0.0.0 \
    --port $APP_PORT \
    --log-level info \
    --proxy-headers \
    --forwarded-allow-ips='*' \
    > "$APP_DIR/logs/fastapi.log" 2>&1 &

APP_PID=$!
log "Application started with PID: $APP_PID"

sleep 5

# ==========================================
# STEP 9: Verify Application is Running
# ==========================================
log "Step 9: Verifying application"

if pgrep -f "uvicorn app:app" > /dev/null; then
    log "✓ Application process is running"
    
    set +e
    
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$APP_PORT/ 2>/dev/null || echo "000")
    
    if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 500 ]; then
        log "✓ Application responding to HTTP requests (HTTP $HTTP_CODE)"
    else
        log "⚠ Application running but may not be ready yet (HTTP $HTTP_CODE)"
        log "Check logs: tail -f $APP_DIR/logs/fastapi.log"
    fi
    
    set -e
else
    log "✗ ERROR: Application failed to start!"
    log "=== Last 30 lines of application log ==="
    tail -n 30 "$APP_DIR/logs/fastapi.log" | tee -a "$LOG_FILE"
    log "======================================="
    exit 1
fi

# ==========================================
# STEP 10: Reload Nginx (if needed)
# ==========================================
log "Step 10: Checking Nginx configuration"

set +e

if command -v nginx &> /dev/null; then
    log "Testing Nginx configuration..."
    sudo nginx -t
    
    if [ $? -eq 0 ]; then
        log "Nginx configuration valid, reloading..."
        sudo systemctl reload nginx
        log "✓ Nginx reloaded"
    else
        log "⚠ Nginx configuration test failed"
    fi
else
    log "Nginx not found (expected if running elsewhere)"
fi

set -e

# ==========================================
# STEP 11: Create Random User (if enabled)
# ==========================================
log "Step 11: Checking user creation trigger"

if [ "$CREATE_RANDOM_USER" = true ]; then
    log "User creation is ENABLED"
    
    set +e
    
    if [ -f "$APP_DIR/script/create_user.sh" ]; then
        # Generate random 5-character name (alphanumeric lowercase)
        RANDOM_NAME=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 5 | head -n 1)
        RANDOM_JOB="developer"  # Change this to desired job title
        
        log "Running create_user.sh with name: $RANDOM_NAME, job: $RANDOM_JOB"
        
        # Create logs directory if it doesn't exist
        mkdir -p "$APP_DIR/logs"
        
        # Run script and capture output to both deployment log and separate file 
        SCRIPT_LOG="$APP_DIR/logs/create_user_$RANDOM_NAME.log"
        
        # Run script with 'no' as default answer to shared data question
        # Redirect output to both deployment log and script-specific log
        {
            echo "no" | bash "$APP_DIR/script/create_user.sh" "$RANDOM_NAME" "$RANDOM_JOB"
        } 2>&1 | tee -a "$SCRIPT_LOG" | tee -a "$LOG_FILE"
        
        if [ $? -eq 0 ]; then
            log "✓ User creation script completed successfully"
            log "   Script output saved to: $SCRIPT_LOG"
        else
            log "⚠ User creation script returned non-zero exit code (continuing anyway)"
            log "   Check logs at: $SCRIPT_LOG"
        fi
    else
        log "⚠ create_user.sh not found at $APP_DIR/script/create_user.sh"
    fi
    
    set -e
else
    log "User creation is DISABLED (skipping)"
fi

# ==========================================
# DEPLOYMENT COMPLETE
# ==========================================

log "=========================================="
log "Deployment completed successfully!"
log "=========================================="
log "Application directory: $APP_DIR"
log "Application logs: $APP_DIR/logs/fastapi.log"
log "Deployment logs: $LOG_FILE"
log ""


exit 0