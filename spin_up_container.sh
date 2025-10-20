#!/bin/bash

################################################################################
# Script: spin_up_container.sh
# Purpose: Create Docker container with registry tracking and seeded data
# Usage: ./spin_up_container.sh <container_name> <tags> <seed_data_path>
################################################################################

set -e  # Exit on any error

# Configuration
SHARED_VOLUME="shared_data"
REGISTRY_FILE="container_registry.json"
BASE_IMAGE="custom_user_base:latest"

# Function to display usage
usage() {
    echo "Usage: $0 <container_name> <tags> <seed_data_path>"
    echo ""
    echo "Arguments:"
    echo "  container_name  - Name for the container (e.g., 'bob', 'alice')"
    echo "  tags            - Comma-separated tags (e.g., 'dev,python,frontend')"
    echo "  seed_data_path  - Path to directory structure to copy into container"
    echo ""
    echo "Example:"
    echo "  $0 bob 'dev,backend' ./bob_initial_files"
    echo ""
    echo "The script will:"
    echo "  1. Create a private volume for the container"
    echo "  2. Copy your directory structure into the private volume"
    echo "  3. Register the container in shared_data/container_registry.json"
    echo "  4. Start the container"
    exit 1
}

# Validate arguments
if [ $# -ne 3 ]; then
    echo "❌ Error: Invalid number of arguments"
    usage
fi

CONTAINER_NAME="$1"
TAGS="$2"
SEED_DATA_PATH="$3"

# Validate seed data path exists
if [ ! -d "$SEED_DATA_PATH" ]; then
    echo "❌ Error: Seed data path '$SEED_DATA_PATH' does not exist"
    exit 1
fi

echo "🚀 Setting up container: $CONTAINER_NAME"
echo "🏷️  Tags: $TAGS"
echo "📁 Seed data: $SEED_DATA_PATH"

################################################################################
# Step 1: Create shared volume if it doesn't exist
# Why: This volume holds the registry and shared data across all containers
################################################################################
if ! docker volume inspect "$SHARED_VOLUME" &>/dev/null; then
    echo "💾 Creating shared volume: $SHARED_VOLUME"
    docker volume create "$SHARED_VOLUME"
    echo "   ✅ Shared volume created"
else
    echo "💾 Shared volume '$SHARED_VOLUME' already exists"
fi

################################################################################
# Step 2: Create container-specific private volume
# Why: Each container needs its own isolated storage
################################################################################
PRIVATE_VOLUME="${CONTAINER_NAME}_private"

if docker volume inspect "$PRIVATE_VOLUME" &>/dev/null; then
    echo "⚠️  Warning: Volume '$PRIVATE_VOLUME' already exists"
    read -p "   Do you want to DELETE and recreate it? (yes/no): " confirm
    if [ "$confirm" = "yes" ]; then
        docker volume rm "$PRIVATE_VOLUME"
        docker volume create "$PRIVATE_VOLUME"
        echo "   ✅ Volume recreated"
    else
        echo "   ⏭️  Skipping volume creation"
    fi
else
    echo "💾 Creating private volume: $PRIVATE_VOLUME"
    docker volume create "$PRIVATE_VOLUME"
    echo "   ✅ Private volume created"
fi

################################################################################
# Step 3: Seed the private volume with directory structure
# Why: We copy the entire directory tree from seed_data_path into the volume
################################################################################
echo "🌱 Copying directory structure to private volume..."
echo "   Source: $SEED_DATA_PATH"
echo "   Destination: /data_private in container"

# Use a temporary container to copy files into the volume
# Why this approach? Docker volumes are managed by Docker daemon, we can't 
# directly write to them from host filesystem without knowing their physical location
docker run --rm \
    -v "$PRIVATE_VOLUME:/data_private" \
    -v "$(realpath "$SEED_DATA_PATH"):/seed_source:ro" \
    "$BASE_IMAGE" \
    bash -c "cp -r /seed_source/. /data_private/ && chown -R 1000:1000 /data_private"

echo "   ✅ Directory structure copied successfully"

################################################################################
# Step 4: Register container in shared volume registry
# Why: Keeps track of all containers, their tags, and metadata in one place
################################################################################
echo "Registering container in shared registry..."

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
ENTRY="[$TIMESTAMP] Container: $CONTAINER_NAME | Tags: ${TAGS:-none} | Volume: $PRIVATE_VOLUME | Status: active"

docker run --rm \
    -v "$SHARED_VOLUME:/data_shared" \
    "$BASE_IMAGE" \
    bash -c "
        REGISTRY='/data_shared/$REGISTRY_FILE'
        echo \"$ENTRY\" >> \"\$REGISTRY\"
        echo 'Registry updated'
    "

echo "Container registered in $REGISTRY_FILE"

################################################################################
# Step 5: Start the container
# Why: Now that everything is prepared, launch the actual container
################################################################################

# Check if container already exists
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "⚠️  Container '$CONTAINER_NAME' already exists"
    read -p "   Do you want to REMOVE and recreate it? (yes/no): " confirm
    if [ "$confirm" = "yes" ]; then
        docker rm -f "$CONTAINER_NAME"
        echo "   ✅ Old container removed"
    else
        echo "   ❌ Cannot proceed with existing container. Exiting."
        exit 1
    fi
fi

echo "🐳 Starting container: $CONTAINER_NAME"
docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    -v "$PRIVATE_VOLUME:/data_private" \
    -v "$SHARED_VOLUME:/data_shared" \
    --hostname "$CONTAINER_NAME" \
    "$BASE_IMAGE"

echo "   ✅ Container started successfully"

################################################################################
# Step 6: Display summary
################################################################################
echo ""
echo "✨ Setup complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Container:       $CONTAINER_NAME"
echo "Tags:            $TAGS"
echo "Private volume:  $PRIVATE_VOLUME → /data_private"
echo "Shared volume:   $SHARED_VOLUME → /data_shared"
echo "Registry:        /data_shared/$REGISTRY_FILE"
echo ""
echo "🔧 Useful commands:"
echo "  Shell access:      docker exec -it $CONTAINER_NAME bash"
echo "  View files:        docker exec $CONTAINER_NAME ls -la /data_private"
echo "  View registry:     docker run --rm -v $SHARED_VOLUME:/data_shared $BASE_IMAGE cat /data_shared/$REGISTRY_FILE"
echo "  Stop:              docker stop $CONTAINER_NAME"
echo "  Remove:            docker rm -f $CONTAINER_NAME"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"