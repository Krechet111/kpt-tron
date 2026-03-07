#!/bin/bash
HOST="bisq@89.23.100.234"
REMOTE_DIR="/home/bisq/kpt/kpt-tron"

echo ">>> Cleaning data on $HOST..."
read -p "Are you sure you want to delete ALL DATA on $HOST? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    # We send the clean logic directly via SSH to avoid keeping a persistent dangerous script if possible,
    # or just write and execute it. Using Here-Doc for safety and visibility.
    ssh $HOST "bash -s" << 'EOF'
    # Stop first - try both paths just in case
    if [ -f /home/bisq/kpt/kpt-tron/scripts/stop.sh ]; then
        bash /home/bisq/kpt/kpt-tron/scripts/stop.sh
    else
        # Manually kill if script missing
        PID=$(pgrep -f "FullNode.jar")
        if [ -n "$PID" ]; then kill -9 $PID; fi
    fi
    
    # Remove the entire project directory
    echo "Removing /home/bisq/kpt/kpt-tron..."
    rm -rf /home/bisq/kpt/kpt-tron
    echo "Clean complete. All files removed."
EOF
else
    echo "Aborted."
fi
