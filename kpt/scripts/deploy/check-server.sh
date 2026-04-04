#!/bin/bash

# Configuration
REMOTE_USER="bisq"
REMOTE_HOST="89.23.100.234"
LOG_FILE="/home/bisq/kpt/kpt-tron/logs/tron.log"

echo "=== Checking FullNode Status on $REMOTE_HOST ==="

ssh "$REMOTE_USER@$REMOTE_HOST" "bash -s" << EOF
    if pgrep -f 'FullNode.jar' > /dev/null; then
        PID=\$(pgrep -f 'FullNode.jar')
        echo "✅ STATUS: RUNNING (PID: \$PID)"

        echo ""
        echo "--- HTTP API Status (Port 8091) ---"
        HTTP_STATUS=\$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8091/wallet/getnowblock)
        if [ "\$HTTP_STATUS" == "200" ]; then
            echo "✅ HTTP API is OK (200)"
        else
            echo "⚠️  HTTP API check FAILED (Status: \$HTTP_STATUS)"
        fi

        echo ""
        echo "--- Last 10 Log Lines ---"
        tail -n 10 $LOG_FILE
    else
        echo "❌ STATUS: NOT RUNNING"
        if [ -f "$LOG_FILE" ]; then
            echo ""
            echo "--- Last 10 Log Lines (Post-Mortem) ---"
            tail -n 10 $LOG_FILE
        fi
        exit 1
    fi
EOF
