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

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

generate_hash() {
    echo -n "$1" | sha256sum | cut -d' ' -f1 | cut -c1-16
}

usage() {
    echo "Usage: $0 <container_name> <tags> <seed_data_path> <user_info_path>"
    exit 1
}

if [ $# -ne 4 ]; then
    print_error "Invalid number of arguments"
    usage
fi

CONTAINER_NAME="$1"
TAGS="$2"
SEED_DATA_PATH="$3"
USER_INFO_PATH="$4"

if [ ! -d "$SEED_DATA_PATH" ]; then
    print_error "Seed data path '$SEED_DATA_PATH' does not exist"
    exit 1
fi

if [ ! -f "$USER_INFO_PATH" ]; then
    print_error "User info file '$USER_INFO_PATH' does not exist"
    exit 1
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
UNIQUE_HASH=$(generate_hash "${CONTAINER_NAME}${TIMESTAMP}")
USERNAME="${CONTAINER_NAME}"
PASSWORD=$(generate_password)

print_info "=============================================="
print_info "Container Setup: $CONTAINER_NAME"
print_info "Tags: $TAGS"
print_info "=============================================="

# Step 1: Shared volume
print_info "Step 1: Checking shared volume..."
if ! docker volume inspect "$SHARED_VOLUME" &>/dev/null; then
    docker volume create "$SHARED_VOLUME"
    print_success "Shared volume created"
else
    print_success "Shared volume exists"
fi

# Step 2: Private volume
print_info "Step 2: Setting up private volume..."
PRIVATE_VOLUME="${CONTAINER_NAME}_private"

if docker volume inspect "$PRIVATE_VOLUME" &>/dev/null; then
    print_warning "Volume '$PRIVATE_VOLUME' exists"
    read -p "Delete and recreate? (yes/no): " confirm
    if [ "$confirm" = "yes" ]; then
        docker volume rm "$PRIVATE_VOLUME"
        docker volume create "$PRIVATE_VOLUME"
        print_success "Volume recreated"
    else
        print_warning "Using existing volume"
    fi
else
    docker volume create "$PRIVATE_VOLUME"
    print_success "Private volume created"
fi

# Step 3: Copy seed data
print_info "Step 3: Copying seed data..."
docker run --rm \
  -v "$PRIVATE_VOLUME:/data_private" \
  -v "$(realpath "$SEED_DATA_PATH"):/seed_source:ro" \
  "$DEFAULT_IMAGE" \
  bash -c "
    apt-get update -qq && apt-get install -y -qq rsync > /dev/null 2>&1
    rsync -a --exclude='.venv' --exclude='.env' --exclude='__pycache__' \
             --exclude='.git' --exclude='node_modules' /seed_source/ /data_private/
    chown -R 1000:1000 /data_private
    find /data_private -type f | wc -l
  "
print_success "Seed data copied"

# Step 4: Copy user info
print_info "Step 4: Adding user info..."
docker run --rm \
  -v "$PRIVATE_VOLUME:/data_private" \
  -v "$(realpath "$USER_INFO_PATH"):/user_info_source:ro" \
  "$DEFAULT_IMAGE" \
  bash -c "
    mkdir -p /data_private/own
    cp /user_info_source /data_private/own/user_info.md
    chown -R 1000:1000 /data_private/own
  "
print_success "User info added"

# Step 5: Register in shared registry
print_info "Step 5: Registering container..."
ENTRY=$(cat <<EOF
{
  "timestamp": "$TIMESTAMP",
  "container_name": "$CONTAINER_NAME",
  "tags": "$TAGS",
  "private_volume": "$PRIVATE_VOLUME", ##whyy??
  "unique_hash": "$UNIQUE_HASH",   ####Why? thats priv data
  "username": "$USERNAME",
  "status": "active" ###just nanme and tag
}
EOF
)

docker run --rm \
  -v "$SHARED_VOLUME:/data_shared" \
  "$DEFAULT_IMAGE" \
  bash -c "
    mkdir -p /data_shared
    REGISTRY='/data_shared/$REGISTRY_FILE'
    if [ ! -f \"\$REGISTRY\" ]; then
      echo '[]' > \"\$REGISTRY\"
    fi
    echo '$ENTRY' >> \"\$REGISTRY\"
  "
print_success "Container registered"

# Step 6: Start container
print_info "Step 6: Starting container..."
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    print_warning "Container exists"
    read -p "Remove and recreate? (yes/no): " confirm
    if [ "$confirm" = "yes" ]; then
        docker rm -f "$CONTAINER_NAME"
    else
        print_error "Cannot proceed. Exiting."
        exit 1
    fi
fi

docker run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  -v "$PRIVATE_VOLUME:/data_private" \
  -v "$SHARED_VOLUME:/data_shared" \
  --hostname "$CONTAINER_NAME" \
  "$DEFAULT_IMAGE" \
  tail -f /dev/null

print_success "Container started"

echo ""
echo "=============================================="
print_success "SETUP COMPLETE"
echo "=============================================="
echo ""
echo "📦 Container Details:"
echo "   Name:           $CONTAINER_NAME"
echo "   Status:         Running"
echo "   Private Volume: $PRIVATE_VOLUME"
echo "   Shared Volume:  $SHARED_VOLUME"
echo ""
echo "🔐 Credentials:"
echo "   Username:       $USERNAME"
echo "   Password:       $PASSWORD"
echo "   Unique Hash:    $UNIQUE_HASH"
echo ""
echo "📂 Mounted Volumes:"
echo "   /data_private  -> Container-specific data"
echo "   /data_shared   -> Shared across all containers"
echo ""
echo "🏷️  Tags: $TAGS"
echo ""
echo "💡 Next Steps:"
echo "   - Access:  docker exec -it $CONTAINER_NAME bash"
echo "   - Logs:    docker logs $CONTAINER_NAME"
echo "   - Stop:    docker stop $CONTAINER_NAME"
echo ""
echo "⚠️  SAVE THESE CREDENTIALS!"
echo "=============================================="
