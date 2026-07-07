#!/bin/bash
# Check the Tron FullNode status on the remote server (systemd-aware).

REMOTE_USER="bisq"
REMOTE_HOST="${REMOTE_HOST:-186.246.12.181}"
LOG_FILE="/home/bisq/kpt/kpt-tron/logs/tron.log"

echo "=== kpt-tron status on $REMOTE_HOST ==="

ssh "$REMOTE_USER@$REMOTE_HOST" "bash -s" << EOF
    if systemctl cat kpt-tron.service >/dev/null 2>&1; then
        echo "--- systemd ---"
        systemctl status kpt-tron --no-pager -l | head -n 14
        ACTIVE=\$(systemctl is-active kpt-tron)
    else
        echo "⚠️  kpt-tron.service not installed (legacy nohup mode?)."
        if pgrep -f 'FullNode.jar' >/dev/null; then ACTIVE="active(legacy)"; else ACTIVE="inactive"; fi
    fi

    echo ""
    echo "--- HTTP API (port 8091) ---"
    HTTP_STATUS=\$(curl -s -o /dev/null -w "%{http_code}" -m 5 http://127.0.0.1:8091/wallet/getnowblock || echo "000")
    if [ "\$HTTP_STATUS" == "200" ]; then
        BLK=\$(curl -s -m 5 -X POST http://127.0.0.1:8091/wallet/getnowblock -d '{}' | grep -o '"number":[0-9]*' | head -1 | cut -d: -f2)
        echo "✅ HTTP API OK (200), local head block: \${BLK:-?}"
    else
        echo "⚠️  HTTP API check FAILED (status: \$HTTP_STATUS)"
    fi

    echo ""
    echo "--- Memory / Swap ---"
    free -h | grep -E 'Mem|Swap'

    echo ""
    echo "--- Last 10 app-log lines ($LOG_FILE) ---"
    tail -n 10 "$LOG_FILE" 2>/dev/null || echo "(no log file yet)"

    [ "\$ACTIVE" = "active" ] || [ "\$ACTIVE" = "active(legacy)" ] || exit 1
EOF
