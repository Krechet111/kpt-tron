#!/bin/bash

# Configuration
REMOTE_USER="bisq"
REMOTE_HOST="89.23.100.234"
LOG_FILE="/home/bisq/kpt/kpt-tron/logs/tron.log"

# Usage: ./logs-server.sh [full|tail|N]
#   full  - download and display the entire log
#   tail  - last 20 lines (default)
#   N     - last N lines

MODE="${1:-tail}"

case "$MODE" in
    full)
        echo "=== Full Log from $LOG_FILE on $REMOTE_HOST ==="
        ssh "$REMOTE_USER@$REMOTE_HOST" "cat $LOG_FILE"
        ;;
    tail)
        echo "=== Last 20 Lines from $LOG_FILE on $REMOTE_HOST ==="
        ssh "$REMOTE_USER@$REMOTE_HOST" "tail -n 20 $LOG_FILE"
        ;;
    *)
        if [[ "$MODE" =~ ^[0-9]+$ ]]; then
            echo "=== Last $MODE Lines from $LOG_FILE on $REMOTE_HOST ==="
            ssh "$REMOTE_USER@$REMOTE_HOST" "tail -n $MODE $LOG_FILE"
        else
            echo "Usage: $0 [full|tail|N]"
            echo "  full  - display the entire log"
            echo "  tail  - last 20 lines (default)"
            echo "  N     - last N lines"
            exit 1
        fi
        ;;
esac
