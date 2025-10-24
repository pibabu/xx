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
BASE_URL="ey-ios.com"

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

generate_hash() {
    openssl rand -hex 16
}

usage() {
    cat << 'EOF'
Usage: ./deploy.sh <container_name> <user_tag>

Arguments:
  container_name    - Unique name for the container
  user_tag          - User identifier tag (e.g., "john_doe" or "user123")

Example:
  ./deploy.sh my_container "John Doe - Developer"

EOF
    exit 1
}

[ $# -ne 2 ] && { print_error "Invalid arguments"; usage; }

CONTAINER_NAME="$1"
USER_TAG="$2"
SEED_DATA_PATH="./data_private"

[ ! -d "$SEED_DATA_PATH" ] && { print_error "Seed data path not found: $SEED_DATA_PATH"; exit 1; }

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
USER_HASH=$(generate_hash)
USERNAME="${CONTAINER_NAME}"

print_info "=============================================="
print_info "Container Setup: $CONTAINER_NAME"
print_info "User Tag: $USER_TAG"
print_info "=============================================="

# Ensure shared volume exists
docker volume inspect "$SHARED_VOLUME" &>/dev/null || docker volume create "$SHARED_VOLUME" >/dev/null

# Setup private volume
PRIVATE_VOLUME="${CONTAINER_NAME}_private"
if docker volume inspect "$PRIVATE_VOLUME" &>/dev/null; then
    print_warning "Volume '$PRIVATE_VOLUME' already exists"
    read -p "Recreate? (yes/no): " confirm
    [ "$confirm" = "yes" ] && docker volume rm "$PRIVATE_VOLUME" >/dev/null
fi
docker volume create "$PRIVATE_VOLUME" >/dev/null

# Copy seed data to private volume
print_info "Copying seed data..."
docker run --rm \
  -v "$PRIVATE_VOLUME:/data_private" \
  -v "$(realpath "$SEED_DATA_PATH"):/seed_source:ro" \
  "$DEFAULT_IMAGE" \
  bash -c "
    apt-get update -qq && apt-get install -y -qq rsync >/dev/null 2>&1
    rsync -a --exclude='.venv' --exclude='.env' --exclude='__pycache__' \
             --exclude='.git' --exclude='node_modules' --exclude='script/deploy.sh' \
             /seed_source/ /data_private/
    chown -R 1000:1000 /data_private
  " >/dev/null 2>&1

print_success "Data copied to private volume"

# Register container in shared registry
print_info "Registering container..."
ENTRY=$(cat <<EOF
{
  "container_name": "$CONTAINER_NAME",
  "user_tag": "$USER_TAG",
  "user_hash": "$USER_HASH"
}
EOF
)

docker run --rm \
  -v "$SHARED_VOLUME:/data_shared" \
  "$DEFAULT_IMAGE" \
  bash -c "
    apt-get update -qq && apt-get install -y -qq jq >/dev/null 2>&1
    mkdir -p /data_shared
    REGISTRY='/data_shared/$REGISTRY_FILE'
    if [ ! -f \"\$REGISTRY\" ]; then
      echo '[]' > \"\$REGISTRY\"
    fi
    
    # Add new entry to JSON array
    jq '. += [${ENTRY}]' \"\$REGISTRY\" > /tmp/registry_new.json
    mv /tmp/registry_new.json \"\$REGISTRY\"
  " >/dev/null 2>&1

print_success "Container registered"

# Remove existing container if present
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    print_warning "Container '$CONTAINER_NAME' already exists"
    read -p "Remove and recreate? (yes/no): " confirm
    [ "$confirm" != "yes" ] && { print_error "Deployment aborted"; exit 1; }
    docker rm -f "$CONTAINER_NAME" >/dev/null
fi

# Start container with labels
print_info "Starting container..."
docker run -d \
  --name "$CONTAINER_NAME" \
  --label user_hash="$USER_HASH" \
  --label user_tag="$USER_TAG" \
  --restart unless-stopped \
  -v "$PRIVATE_VOLUME:/data_private" \
  -v "$SHARED_VOLUME:/data_shared" \
  -w /data_private \
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
echo "🏷️  User Tag: $USER_TAG"
echo "🔗 Access URL: https://$BASE_URL/$USER_HASH"
echo ""
echo "💡 Quick Access:"
echo "   docker exec -it $CONTAINER_NAME bash"
echo ""
echo "📂 Working Directory: /data_private"
echo "📂 Shared Data: /data_shared"
echo ""
echo "=============================================="