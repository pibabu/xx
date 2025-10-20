#!/bin/bash

# ============================================
# SHARED VOLUME STRUCTURE (/data_shared)
# ============================================
echo "Setting up /data_shared workspace..."

# Create root README in shared volume
if [ ! -f /data_shared/README.md ]; then
    cat > /data_shared/README.md << 'EOF'
# Shared Data Workspace

This is the shared volume accessible across containers.

## Directory Structure
- `shared_files/` - Common files accessible to all
- `cron/` - Scheduled task scripts and logs
- `capturetheflag/` - CTF challenges and solutions
- `messages/` - Inter-process communication files

Last initialized: $(date)
EOF
    echo "✓ Created /data_shared/README.md"
fi

# Create shared_files directory
mkdir -p /data_shared/shared_files
if [ ! -f /data_shared/shared_files/.gitkeep ]; then
    echo "# Shared files go here" > /data_shared/shared_files/.gitkeep
    echo "✓ Created /data_shared/shared_files/"
fi

# Create cron directory with subdirectories
mkdir -p /data_shared/cron/{scripts,logs}
if [ ! -f /data_shared/cron/README.md ]; then
    cat > /data_shared/cron/README.md << 'EOF'
# Cron Directory

Store scheduled task scripts and their logs here.

- `scripts/` - Executable cron scripts
- `logs/` - Output logs from cron jobs
EOF
    echo "✓ Created /data_shared/cron/ structure"
fi

# Create capturetheflag directory
mkdir -p /data_shared/capturetheflag/{challenges,solutions,flags}
if [ ! -f /data_shared/capturetheflag/README.md ]; then
    cat > /data_shared/capturetheflag/README.md << 'EOF'
# Capture The Flag

CTF workspace for security challenges.

- `challenges/` - Challenge descriptions and files
- `solutions/` - Your solution attempts
- `flags/` - Captured flags and notes
EOF
    echo "✓ Created /data_shared/capturetheflag/ structure"
fi

# Create messages directory
mkdir -p /data_shared/messages/{inbox,outbox,archive}
if [ ! -f /data_shared/messages/README.md ]; then
    cat > /data_shared/messages/README.md << 'EOF'
# Messages Directory

Inter-process communication and message queue.

- `inbox/` - Incoming messages
- `outbox/` - Outgoing messages
- `archive/` - Processed messages
EOF
    echo "✓ Created /data_shared/messages/ structure"
fi

# ============================================
# PRIVATE VOLUME STRUCTURE (/data_private)
# ============================================
echo "Setting up /data_private workspace..."

# Create root README in private volume
if [ ! -f /data_private/README.md ]; then
    cat > /data_private/README.md << 'EOF'
# Private Data Workspace

This is your private working directory.

## Purpose
- Temporary files and scratch work
- Local processing and computation
- Container-specific data

**Note:** Data here is not shared with other containers.
EOF
    echo "✓ Created /data_private/README.md"
fi

# Create basic workspace directories
mkdir -p /data_private/{temp,work,output}
echo "✓ Created /data_private/ structure"

# ============================================
# SUMMARY
# ============================================
echo ""
echo "======================================"
echo "Workspace initialization complete!"
echo "======================================"
echo "Working directory: /data_private"
echo ""
echo "Directory tree:"
echo "/data_shared/"
echo "  ├── README.md"
echo "  ├── shared_files/"
echo "  ├── cron/"
echo "  │   ├── scripts/"
echo "  │   └── logs/"
echo "  ├── capturetheflag/"
echo "  │   ├── challenges/"
echo "  │   ├── solutions/"
echo "  │   └── flags/"
echo "  └── messages/"
echo "      ├── inbox/"
echo "      ├── outbox/"
echo "      └── archive/"
echo ""
echo "/data_private/"
echo "  ├── README.md"
echo "  ├── temp/"
echo "  ├── work/"
echo "  └── output/"
echo ""

# Keep container running
exec sleep infinity