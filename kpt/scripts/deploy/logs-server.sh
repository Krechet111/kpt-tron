#!/bin/bash

# Configuration
REMOTE_USER="bisq"
REMOTE_HOST="89.23.100.234"
LOG_FILE="/home/bisq/kpt/kpt-tron/logs/tron.log"

echo "=== Last 20 Lines from $LOG_FILE on $REMOTE_HOST ==="

ssh "$REMOTE_USER@$REMOTE_HOST" "tail -n 20 $LOG_FILE"
