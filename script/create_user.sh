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
REGISTRY_LOCK="container_registry.lock"
BASE_URL="ey-ios.com"
NETWORK_NAME="user_shared_network"

# File paths - Fixed: data dirs are in parent directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
DOCKERFILE_TEMPLATE="$SCRIPT_DIR/Dockerfile"
COMPOSE_TEMPLATE="$SCRIPT_DIR/docker-compose.yml"
SEED_DATA_PRIVATE="$PARENT_DIR/data_private"
SEED_DATA_SHARED="$PARENT_DIR/data_shared"

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

generate_hash() {
    openssl rand -hex 16
}

validate_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        print_error "Invalid container name. Use only alphanumeric characters, hyphens, and underscores."
        exit 1
    fi
}

usage() {
    echo "Usage: $0 <container_name> <user_tag>"
    echo "Example: $0 user_alice development"
    exit 1
}

[ $# -ne 2 ] && { print_error "Invalid arguments"; usage; }

CONTAINER_NAME="$1"
USER_TAG="$2"

# Validate inputs
validate_name "$CONTAINER_NAME"

# Validate required files exist
[ ! -f "$DOCKERFILE_TEMPLATE" ] && { print_error "Dockerfile not found: $DOCKERFILE_TEMPLATE"; exit 1; }
[ ! -f "$COMPOSE_TEMPLATE" ] && { print_error "Docker Compose template not found: $COMPOSE_TEMPLATE"; exit 1; }
[ ! -d "$SEED_DATA_PRIVATE" ] && { print_warning "Private data path not found: $SEED_DATA_PRIVATE (will create empty)"; }
[ ! -d "$SEED_DATA_SHARED" ] && { print_warning "Shared data path not found: $SEED_DATA_SHARED (will skip)"; }

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
USER_HASH=$(generate_hash)
PRIVATE_VOLUME="${CONTAINER_NAME}_private"

# Create user-specific directory for docker-compose
USER_DIR="$SCRIPT_DIR/users/${CONTAINER_NAME}"
mkdir -p "$USER_DIR"

# Create shared network if it doesn't exist
if ! docker network inspect "$NETWORK_NAME" &>/dev/null; then
    print_info "Creating shared network: $NETWORK_NAME"
    docker network create "$NETWORK_NAME" >/dev/null
fi

# Ensure shared volume exists
if ! docker volume inspect "$SHARED_VOLUME" &>/dev/null; then
    print_info "Creating shared volume: $SHARED_VOLUME"
    docker volume create "$SHARED_VOLUME" >/dev/null
fi

# Setup private volume
if docker volume inspect "$PRIVATE_VOLUME" &>/dev/null; then
    print_warning "Volume '$PRIVATE_VOLUME' already exists"
    read -p "Recreate? (yes/no): " confirm
    if [ "$confirm" = "yes" ]; then
        docker volume rm "$PRIVATE_VOLUME" >/dev/null
        docker volume create "$PRIVATE_VOLUME" >/dev/null
    fi
else
    docker volume create "$PRIVATE_VOLUME" >/dev/null
fi

# Seed private volume with data_private only
if [ -d "$SEED_DATA_PRIVATE" ]; then
    print_info "Seeding private volume with data_private..."
    docker run --rm \
      -v "$PRIVATE_VOLUME:/mnt/target" \
      -v "$SEED_DATA_PRIVATE:/mnt/source:ro" \
      ubuntu:latest \
      bash -c "cp -r /mnt/source/* /mnt/target/ 2>/dev/null || true; chown -R 1000:1000 /mnt/target" 2>&1 | grep -v "debconf" || true
    print_success "Private data seeded"
else
    print_warning "No private data found, volume will be empty"
fi

# Seed shared volume with data_shared (one-time initialization)
if [ -d "$SEED_DATA_SHARED" ]; then
    # Check if shared volume is empty
    IS_EMPTY=$(docker run --rm -v "$SHARED_VOLUME:/mnt/shared" ubuntu:latest bash -c "[ -z \"\$(ls -A /mnt/shared 2>/dev/null)\" ] && echo 'yes' || echo 'no'")
    
    if [ "$IS_EMPTY" = "yes" ]; then
        print_info "Seeding shared volume with data_shared (first time)..."
        docker run --rm \
          -v "$SHARED_VOLUME:/mnt/target" \
          -v "$SEED_DATA_SHARED:/mnt/source:ro" \
          ubuntu:latest \
          bash -c "cp -r /mnt/source/* /mnt/target/ 2>/dev/null || true; chown -R 1000:1000 /mnt/target" 2>&1 | grep -v "debconf" || true
        print_success "Shared data seeded"
    else
        print_info "Shared volume already has data, skipping seed"
    fi
fi

# Initialize shared volume registry if needed
print_info "Checking shared volume registry..."
docker run --rm \
  -v "$SHARED_VOLUME:/mnt/shared" \
  ubuntu:latest \
  bash -c "
    mkdir -p /mnt/shared
    REGISTRY='/mnt/shared/$REGISTRY_FILE'
    if [ ! -f \"\$REGISTRY\" ]; then
      echo '[]' > \"\$REGISTRY\"
      chmod 666 \"\$REGISTRY\"
    fi
  " 2>&1 | grep -v "debconf" || true

# Register container in shared registry with file locking
print_info "Registering container in shared registry..."
docker run --rm \
  -v "$SHARED_VOLUME:/mnt/shared" \
  ubuntu:latest \
  bash -c "
    set -e
    apt-get update -qq && apt-get install -y -qq jq >/dev/null 2>&1
    REGISTRY='/mnt/shared/$REGISTRY_FILE'
    LOCKFILE='/mnt/shared/$REGISTRY_LOCK'

    # Simple file-based locking
    RETRIES=0
    while ! mkdir \"\$LOCKFILE\" 2>/dev/null; do
      sleep 0.1
      RETRIES=\$((RETRIES + 1))
      [ \$RETRIES -gt 50 ] && { echo 'Lock timeout'; exit 1; }
    done
    trap 'rmdir \"\$LOCKFILE\" 2>/dev/null || true' EXIT

    # Add new entry to JSON array
    NEW_ENTRY='{\"container_name\":\"$CONTAINER_NAME\",\"user_tag\":\"$USER_TAG\",\"created\":\"$TIMESTAMP\"}'
    jq --argjson entry \"\$NEW_ENTRY\" '. += [\$entry]' \"\$REGISTRY\" > /tmp/registry_new.json
    mv /tmp/registry_new.json \"\$REGISTRY\"
  " >/dev/null 2>&1

print_success "Container registered in shared registry"

# Copy Dockerfile to user directory
print_info "Preparing docker-compose configuration..."
cp "$DOCKERFILE_TEMPLATE" "$USER_DIR/Dockerfile"

# Generate docker-compose.yml from template
sed -e "s/{{CONTAINER_NAME}}/$CONTAINER_NAME/g" \
    -e "s/{{PRIVATE_VOLUME}}/$PRIVATE_VOLUME/g" \
    -e "s/{{TAGS}}/$USER_TAG/g" \
    "$COMPOSE_TEMPLATE" > "$USER_DIR/docker-compose.yml"

print_success "Configuration files created in $USER_DIR"

# Check if container already exists
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    print_warning "Container '$CONTAINER_NAME' already exists"
    read -p "Remove and recreate? (yes/no): " confirm
    if [ "$confirm" = "yes" ]; then
        cd "$USER_DIR"
        docker compose down 2>/dev/null || docker-compose down 2>/dev/null || true
        cd - >/dev/null
    else
        print_error "Deployment aborted"
        exit 1
    fi
fi

# Build and start container using docker compose
print_info "Building and starting container..."
cd "$USER_DIR"

# Detect docker compose command
if docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
else
    print_error "Neither 'docker compose' nor 'docker-compose' found"
    exit 1
fi

print_info "Using: $COMPOSE_CMD"

# Build and start (removed problematic flags)
$COMPOSE_CMD build
$COMPOSE_CMD up -d

cd - >/dev/null

# Wait for container to be ready
print_info "Waiting for container to be ready..."
sleep 3

if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    print_success "Container is running"
else
    print_error "Container failed to start"
    print_error "Check logs with: cd $USER_DIR && $COMPOSE_CMD logs"
    exit 1
fi

# Add labels to the running container
docker update --label-add "user_tag=$USER_TAG" \
              --label-add "created=$TIMESTAMP" \
              "$CONTAINER_NAME" 2>/dev/null || true

echo ""
echo "=============================================="
print_success "SETUP COMPLETE"
echo "=============================================="
echo ""
echo "📦 Container: $CONTAINER_NAME"
echo "🏷️  User Tag: $USER_TAG"
echo "🔑 User Hash: $USER_HASH"
echo "🔗 Access URL: https://$BASE_URL?$USER_HASH"
echo ""
echo "💡 Quick Access:"
echo "   docker exec -it $CONTAINER_NAME bash"
echo ""
echo "📂 Configuration: $USER_DIR"
echo "📂 Private Data: /app/private (read-write)"
echo "📂 Shared Data: /app/shared (read-write)"
echo ""
echo "🔧 Management Commands:"
echo "   cd $USER_DIR"
echo "   $COMPOSE_CMD logs -f      # View logs"
echo "   $COMPOSE_CMD restart      # Restart container"
echo "   $COMPOSE_CMD down         # Stop and remove"
echo ""
echo "=============================================="