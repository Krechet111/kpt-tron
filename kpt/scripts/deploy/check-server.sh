#!/bin/bash
HOST="bisq@89.23.100.234"
REMOTE_DIR="/home/bisq/kpt/kpt-tron"

echo ">>> Checking Status on $HOST..."
# Executes the status script created during deploy
ssh $HOST "bash $REMOTE_DIR/scripts/status.sh"
