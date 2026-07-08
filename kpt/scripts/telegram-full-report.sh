#!/usr/bin/env bash
# On-demand full Telegram report for the kpt-tron node: triggers, in one shot,
#   1) sync status with lag/speed/ETA   (tron-sync-report.sh)
#   2) server resources                 (tron-diag-report.sh, forced)
#   3) node log tail as a document      (tron-diag-report.sh, forced)
#
# Unlike the cron diag (which only fires on a problem), this forces the
# resources+log to be sent even when the node is healthy (FORCE=1).
#
# Usage:
#   ./telegram-full-report.sh
#   REMOTE_HOST=other.host ./telegram-full-report.sh
set -euo pipefail

REMOTE_USER="${REMOTE_USER:-bisq}"
REMOTE_HOST="${REMOTE_HOST:-186.246.12.181}"
DEPLOY_DIR="/home/bisq/kpt/kpt-tron/deploy"
LOG="/home/bisq/kpt/kpt-tron/logs/tron-sync-report.log"

echo "Triggering full Telegram report on ${REMOTE_USER}@${REMOTE_HOST} ..."

ssh "${REMOTE_USER}@${REMOTE_HOST}" "bash -s" <<EOF
set -e
echo ">>> sync status"
"${DEPLOY_DIR}/tron-sync-report.sh"
echo ">>> resources + log (forced)"
FORCE=1 "${DEPLOY_DIR}/tron-diag-report.sh"
echo "--- last report-log lines ---"
tail -n 2 "${LOG}" 2>/dev/null || true
EOF

echo "Done. Check the Telegram group."
