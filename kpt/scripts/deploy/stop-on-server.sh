#!/bin/bash

# Configuration
REMOTE_USER="bisq"
REMOTE_HOST="89.23.100.234"

echo "=== Stopping FullNode on $REMOTE_HOST ==="

ssh "$REMOTE_USER@$REMOTE_HOST" "bash -s" << 'EOF'
    if pgrep -f 'FullNode.jar' > /dev/null; then
        pkill -f 'FullNode.jar'
        echo "✅ Signal sent to stop FullNode."

        sleep 5
        if pgrep -f 'FullNode.jar' > /dev/null; then
            echo "⚠️  Process still running, forcing kill..."
            pkill -9 -f 'FullNode.jar'
        fi
        echo "✅ FullNode stopped."
    else
        echo "ℹ️  FullNode was not running."
    fi
EOF
