#!/bin/bash
set -e
set -o pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SHARED_VOLUME="shared_data"
REGISTRY_FILE="container_registry.json"
DEFAULT_IMAGE="ubuntu:latest"
BASE_URL="ey-ios.com/"


print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

generate_hash() {
    openssl rand -hex 16
}

usage() {
    echo "Usage: $0 <container_name> <seed_data_path> <user_info_path>" # show example command # also we need to fix path issues
    # local dir structure: datapriv datashared script/this_actual_script services and files: app.py etc...we wanna copy whole thing
    #exept usual stuff .env .venv , user working dir should be private-data
    exit 1
}

[ $# -ne 3 ] && { print_error "Invalid arguments"; usage; }

CONTAINER_NAME="$1"
SEED_DATA_PATH="$2"
USER_INFO_PATH="$3"

[ ! -d "$SEED_DATA_PATH" ] && { print_error "Seed data path not found"; exit 1; }
[ ! -f "$USER_INFO_PATH" ] && { print_error "User info file not found"; exit 1; }

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
USER_HASH=$(generate_hash)
USERNAME="${CONTAINER_NAME}"
#PASSWORD=$(generate_password)

print_info "=============================================="
print_info "Container Setup: $CONTAINER_NAME"
print_info "=============================================="

# Ensure shared volume exists
docker volume inspect "$SHARED_VOLUME" &>/dev/null || docker volume create "$SHARED_VOLUME" >/dev/null

# Setup private volume
PRIVATE_VOLUME="${CONTAINER_NAME}_private"
if docker volume inspect "$PRIVATE_VOLUME" &>/dev/null; then
    print_warning "Volume exists"
    read -p "Recreate? (yes/no): " confirm
    [ "$confirm" = "yes" ] && docker volume rm "$PRIVATE_VOLUME" >/dev/null
fi
docker volume create "$PRIVATE_VOLUME" >/dev/null

# Copy seed data
print_info "Copying seed data..."
docker run --rm \
  -v "$PRIVATE_VOLUME:/data_private" \
  -v "$(realpath "$SEED_DATA_PATH"):/seed_source:ro" \
  "$DEFAULT_IMAGE" \
  bash -c "
    apt-get update -qq && apt-get install -y -qq rsync >/dev/null 2>&1
    rsync -a --exclude='.venv' --exclude='.env' --exclude='__pycache__' \
             --exclude='.git' --exclude='node_modules' /seed_source/ /data_private/
    chown -R 1000:1000 /data_private
  " >/dev/null 2>&1

# Copy user info
docker run --rm \
  -v "$PRIVATE_VOLUME:/data_private" \
  -v "$(realpath "$USER_INFO_PATH"):/user_info_source:ro" \
  "$DEFAULT_IMAGE" \
  bash -c "mkdir -p /data_private/own && cp /user_info_source /data_private/own/user_info.md" >/dev/null 2>&1 # warum liegt dir own in root? es liegt nicht in data_private

print_success "Data copied"

# Register container
print_info "Registering..."
ENTRY=$(cat <<EOF
{
  "timestamp": "$TIMESTAMP",
  "container_name": "$CONTAINER_NAME",
}
EOF
)

docker run --rm \
  -v "$SHARED_VOLUME:/data_shared" \
  "$DEFAULT_IMAGE" \
  bash -c "
    mkdir -p /data_shared
    REGISTRY='/data_shared/$REGISTRY_FILE'
    [ ! -f \"\$REGISTRY\" ] && echo '[]' > \"\$REGISTRY\"
    echo '$ENTRY' >> \"\$REGISTRY\"
  " >/dev/null 2>&1

# Remove existing container if present
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    print_warning "Container exists"
    read -p "Remove? (yes/no): " confirm
    [ "$confirm" != "yes" ] && { print_error "Aborted"; exit 1; }
    docker rm -f "$CONTAINER_NAME" >/dev/null
fi

# Start container with hash and credentials as labels
print_info "Starting container..."
docker run -d \
  --name "$CONTAINER_NAME" \
  --label user_hash="$USER_HASH" \
  --restart unless-stopped \
  -v "$PRIVATE_VOLUME:/data_private" \
  -v "$SHARED_VOLUME:/data_shared" \
  --hostname "$CONTAINER_NAME" \
  "$DEFAULT_IMAGE" \
  tail -f /dev/null >/dev/null

print_success "Container started"

echo ""
echo "=============================================="
print_success "SETUP COMPLETE"
echo "=============================================="
echo ""
echo "📦 Container: $CONTAINER_NAME"
echo "🔗 Access URL: https://$BASE_URL/$USER_HASH"
echo ""
echo ""
echo "💡 Quick Access:"
echo "   docker exec -it $CONTAINER_NAME bash"
echo ""
echo "=============================================="