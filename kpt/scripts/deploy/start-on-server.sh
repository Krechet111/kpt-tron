#!/bin/bash
# Start the Tron FullNode via systemd on the remote server.
# Requires the kpt-tron.service unit + sudoers drop-in installed once via
# install-root.sh (see deploy/README.md).

REMOTE_USER="bisq"
REMOTE_HOST="${REMOTE_HOST:-186.246.12.181}"

echo "=== Starting kpt-tron service on $REMOTE_HOST ==="

ssh "$REMOTE_USER@$REMOTE_HOST" "bash -s" << 'EOF'
    if ! systemctl list-unit-files kpt-tron.service >/dev/null 2>&1 || \
       ! systemctl cat kpt-tron.service >/dev/null 2>&1; then
        echo "❌ kpt-tron.service is not installed. Run deploy/install-root.sh first."
        exit 1
    fi

    sudo systemctl start kpt-tron

    sleep 3
    if systemctl is-active --quiet kpt-tron; then
        echo "✅ kpt-tron is active."
        systemctl status kpt-tron --no-pager -l | head -n 12
    else
        echo "❌ kpt-tron failed to start. Recent journal:"
        journalctl -u kpt-tron --no-pager -n 30
        exit 1
    fi
EOF
