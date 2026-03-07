#!/bin/bash
HOST="bisq@89.23.100.234"
REMOTE_DIR="/home/bisq/kpt/kpt-tron"

echo ">>> Starting service on $HOST..."
ssh $HOST "bash $REMOTE_DIR/scripts/start.sh"
