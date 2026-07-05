#!/bin/bash
# Stop the Tron FullNode via systemd on the remote server.
# systemd sends SIGTERM and waits up to TimeoutStopSec (300s) for java-tron to
# flush its RocksDB checkpoint — this is the SAFE stop. Do NOT pkill -9.

REMOTE_USER="bisq"
REMOTE_HOST="89.23.100.234"

echo "=== Stopping kpt-tron service on $REMOTE_HOST ==="

ssh "$REMOTE_USER@$REMOTE_HOST" "bash -s" << 'EOF'
    if systemctl cat kpt-tron.service >/dev/null 2>&1; then
        # `is-active` returns non-'active' during transient states — 'deactivating'
        # (graceful flush in progress) or 'activating (auto-restart)' (the RestartSec
        # window after a crash). Do NOT gate the stop on it, or those states look
        # stopped and we skip the actual stop. `systemctl stop` is idempotent, blocks
        # until the unit is down (SIGTERM + up to 300s for the checkpoint flush) AND
        # cancels any pending auto-restart, so we issue it unconditionally.
        echo "Current unit state: $(systemctl is-active kpt-tron)"
        echo "Sending graceful stop (SIGTERM, waits for checkpoint flush, up to 300s)..."
        sudo systemctl stop kpt-tron

        if systemctl is-active --quiet kpt-tron; then
            echo "⚠️  Still active after stop request."
            exit 1
        fi
        echo "✅ kpt-tron stopped (unit inactive)."
    else
        echo "⚠️  kpt-tron.service not installed (legacy nohup mode?)."
    fi

    # Safety net regardless of unit state: no java-tron process should survive a stop.
    # A stray one was started outside systemd (legacy nohup) — SIGTERM it gracefully.
    if pgrep -f 'FullNode.jar' >/dev/null; then
        echo "⚠️  A FullNode.jar process is still alive outside systemd — sending SIGTERM (graceful)."
        pkill -TERM -f 'FullNode.jar'
    fi
EOF
