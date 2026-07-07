#!/bin/bash

# Configuration
REMOTE_USER="bisq"
REMOTE_HOST="${REMOTE_HOST:-186.246.12.181}"
REMOTE_DIR="/home/bisq/kpt/kpt-tron"

echo "=== Removing FullNode from $REMOTE_HOST ==="
echo "Target: $REMOTE_DIR"

read -p "Are you sure you want to delete the FullNode application and all data from the server? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 1
fi

ssh "$REMOTE_USER@$REMOTE_HOST" "bash -s" << EOF
    # Stop first
    pkill -f 'FullNode.jar' || true

    if [ -d "$REMOTE_DIR" ]; then
        rm -rf "$REMOTE_DIR"
        echo "✅ Application files removed."
    else
        echo "ℹ️  Application directory not found."
    fi
EOF
