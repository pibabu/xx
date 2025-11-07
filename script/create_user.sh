#!/bin/bash
set -e
set -o pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SHARED_VOLUME="shared_data"
REGISTRY_FILE="container_registry.json"
REGISTRY_LOCK="container_registry.lock"
BASE_URL="ey-ios.com"
NETWORK_NAME="user_shared_network"

# Paths - simplified
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR"
SEED_PRIVATE="$SCRIPT_DIR/../workdir"
SEED_SHARED="$SCRIPT_DIR/../data_shared"

# Logging
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Generate random hash
generate_hash() {
    openssl rand -hex 16
}

# Validate container name
validate_name() {
    [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]] || {
        log_error "Invalid name. Use only: a-z A-Z 0-9 _ -"
        exit 1
    }
}

# Usage
usage() {
    echo "Usage: $0 <container_name> <user_tag>"
    echo "Example: $0 alice development"
    exit 1
}

# Validate arguments
[ $# -ne 2 ] && { log_error "Invalid arguments"; usage; }

CONTAINER_NAME="$1"
USER_TAG="$2"
validate_name "$CONTAINER_NAME"

# Validate templates exist
[ ! -f "$TEMPLATES_DIR/Dockerfile" ] && { log_error "Missing: Dockerfile"; exit 1; }
[ ! -f "$TEMPLATES_DIR/docker-compose.yml" ] && { log_error "Missing: docker-compose.yml"; exit 1; }

# Generate metadata
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
USER_HASH=$(generate_hash)
PRIVATE_VOLUME="${CONTAINER_NAME}_private"
BUILD_DIR="$SCRIPT_DIR/build/$CONTAINER_NAME"

# Create build directory
mkdir -p "$BUILD_DIR"
log_success "Build directory: $BUILD_DIR"

# Create shared network
if ! docker network inspect "$NETWORK_NAME" &>/dev/null; then
    log_info "Creating network: $NETWORK_NAME"
    docker network create "$NETWORK_NAME" >/dev/null
fi

# Create shared volume
if ! docker volume inspect "$SHARED_VOLUME" &>/dev/null; then
    log_info "Creating shared volume: $SHARED_VOLUME"
    docker volume create "$SHARED_VOLUME" >/dev/null
fi

# Setup private volume
if docker volume inspect "$PRIVATE_VOLUME" &>/dev/null; then
    log_warning "Volume '$PRIVATE_VOLUME' exists"
    
    if [ -t 0 ]; then
        read -p "Recreate? (yes/no): " confirm
    else
        confirm="yes"
        log_info "Non-interactive: forcing recreation"
    fi
    
    if [ "$confirm" = "yes" ]; then
        docker volume rm "$PRIVATE_VOLUME" >/dev/null
        docker volume create "$PRIVATE_VOLUME" >/dev/null
        log_success "Volume recreated"
    fi
else
    docker volume create "$PRIVATE_VOLUME" >/dev/null
    log_success "Volume created: $PRIVATE_VOLUME"
fi

# Seed private volume
if [ -d "$SEED_PRIVATE" ]; then
    log_info "Seeding private volume..."
    docker run --rm \
      -v "$PRIVATE_VOLUME:/target" \
      -v "$SEED_PRIVATE:/source:ro" \
      ubuntu:latest \
      bash -c "cp -r /source/* /target/ 2>/dev/null || true; chown -R 1000:1000 /target" 2>&1 | grep -v "debconf" || true
    log_success "Private data seeded"
else
    log_warning "No private seed data: $SEED_PRIVATE"
fi

# Seed shared volume
if [ -d "$SEED_SHARED" ]; then
    IS_EMPTY=$(docker run --rm -v "$SHARED_VOLUME:/shared" ubuntu:latest bash -c "[ -z \"\$(ls -A /shared 2>/dev/null)\" ] && echo 'yes' || echo 'no'")
    
    if [ "$IS_EMPTY" = "yes" ]; then
        log_info "Seeding empty shared volume..."
        SHOULD_SEED="yes"
    else
        log_warning "Shared volume contains data"
        docker run --rm -v "$SHARED_VOLUME:/shared" ubuntu:latest ls -lh /shared 2>/dev/null | tail -n +2 || true
        read -p "Overwrite? (yes/no): " SHOULD_SEED
    fi
    
    if [ "$SHOULD_SEED" = "yes" ]; then
        docker run --rm \
          -v "$SHARED_VOLUME:/target" \
          -v "$SEED_SHARED:/source:ro" \
          ubuntu:latest \
          bash -c "rm -rf /target/* /target/.* 2>/dev/null || true; cp -r /source/* /target/ 2>/dev/null || true; chown -R 1000:1000 /target" 2>&1 | grep -v "debconf" || true
        log_success "Shared data seeded"
    fi
else
    log_warning "No shared seed data: $SEED_SHARED"
fi

# Initialize registry
log_info "Initializing registry..."
docker run --rm -v "$SHARED_VOLUME:/shared" ubuntu:latest bash -c "
  mkdir -p /shared
  [ ! -f /shared/$REGISTRY_FILE ] && echo '[]' > /shared/$REGISTRY_FILE
  chmod 666 /shared/$REGISTRY_FILE
" 2>&1 | grep -v "debconf" || true

# Register container
log_info "Registering container..."
docker run --rm -v "$SHARED_VOLUME:/shared" ubuntu:latest bash -c "
  set -e
  apt-get update -qq && apt-get install -y -qq jq >/dev/null 2>&1
  
  REGISTRY='/shared/$REGISTRY_FILE'
  LOCKFILE='/shared/$REGISTRY_LOCK'
  
  RETRIES=0
  while ! mkdir \"\$LOCKFILE\" 2>/dev/null; do
    sleep 0.1
    RETRIES=\$((RETRIES + 1))
    [ \$RETRIES -gt 50 ] && exit 1
  done
  trap 'rmdir \"\$LOCKFILE\" 2>/dev/null || true' EXIT
  
  NEW_ENTRY='{\"container_name\":\"$CONTAINER_NAME\",\"user_tag\":\"$USER_TAG\",\"created\":\"$TIMESTAMP\"}'
  jq --argjson entry \"\$NEW_ENTRY\" '. += [\$entry]' \"\$REGISTRY\" > /tmp/new.json
  mv /tmp/new.json \"\$REGISTRY\"
" >/dev/null 2>&1
log_success "Container registered"

# Prepare build files
log_info "Preparing build files..."
cp "$TEMPLATES_DIR/Dockerfile" "$BUILD_DIR/Dockerfile"

sed -e "s/{{CONTAINER_NAME}}/$CONTAINER_NAME/g" \
    -e "s/{{PRIVATE_VOLUME}}/$PRIVATE_VOLUME/g" \
    -e "s/{{TAGS}}/$USER_TAG/g" \
    -e "s/{{USER_HASH}}/$USER_HASH/g" \
    "$TEMPLATES_DIR/docker-compose.yml" > "$BUILD_DIR/docker-compose.yml"

log_success "Build files ready"

# Remove existing container
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_warning "Container exists"
    read -p "Remove and recreate? (yes/no): " confirm
    [ "$confirm" != "yes" ] && { log_error "Aborted"; exit 1; }
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
fi

# Build and start
log_info "Building container..."

export DOCKER_BUILDKIT=0
export COMPOSE_DOCKER_CLI_BUILD=0

cd "$BUILD_DIR"

if ! docker-compose build --no-cache 2>&1; then
    log_error "Build failed"
    exit 1
fi

log_info "Starting container..."
if ! docker-compose up -d 2>&1; then
    log_error "Start failed"
    exit 1
fi

cd - >/dev/null

# Verify
sleep 3
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_success "Container running"
else
    log_error "Container not running"
    log_error "Check logs: docker logs $CONTAINER_NAME"
    exit 1
fi

# Success output
cat <<EOF

==============================================
🎉 DEPLOYMENT COMPLETE
==============================================

📦 Container:  $CONTAINER_NAME
🏷️  Tag:        $USER_TAG
🔑 Hash:       $USER_HASH
🔗 URL:        https://$BASE_URL?hash=$USER_HASH

💡 Access:     docker exec -it $CONTAINER_NAME bash

📂 Private:    /llm/private (rw)
📂 Shared:     /llm/shared (rw)

📁 Build:      $BUILD_DIR

==============================================

EOF