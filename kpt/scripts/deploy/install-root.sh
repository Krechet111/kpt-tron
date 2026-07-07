#!/usr/bin/env bash
# One-shot ROOT installer for the kpt-tron node hardening.
# Run this ON THE SERVER as root, from the directory that contains the other
# deploy artifacts (kpt-tron.service, sudoers-kpt-tron):
#
#     sudo bash /home/bisq/kpt/kpt-tron/deploy/install-root.sh
#
# It does everything that needs root:
#   1. installs the systemd unit
#   2. installs a sudoers drop-in so bisq can start/stop/restart the service
#      without a password (used by the deploy scripts)
#   3. installs + enables the block-height watchdog timer (restarts the node if
#      it stalls without exiting — Restart=on-failure can't catch that)
#   4. reloads systemd
#
# It deliberately does NOT enable or start the service — do that only AFTER the
# DB snapshot has been extracted (see final instructions printed below).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: run as root:  sudo bash $0"; exit 1
fi

for f in kpt-tron.service sudoers-kpt-tron \
         kpt-tron-watchdog.sh kpt-tron-watchdog.service kpt-tron-watchdog.timer; do
    [ -f "$HERE/$f" ] || { echo "ERROR: missing $HERE/$f"; exit 1; }
done

echo "==================================================================="
echo " 1/4  systemd unit -> /etc/systemd/system/kpt-tron.service"
echo "==================================================================="
install -m 0644 "$HERE/kpt-tron.service" /etc/systemd/system/kpt-tron.service
echo "✅ installed"

echo
echo "==================================================================="
echo " 2/4  sudoers drop-in -> /etc/sudoers.d/kpt-tron"
echo "==================================================================="
install -m 0440 "$HERE/sudoers-kpt-tron" /etc/sudoers.d/kpt-tron
# Validate before it can lock anyone out.
if visudo -cf /etc/sudoers.d/kpt-tron; then
    echo "✅ sudoers syntax OK"
else
    echo "❌ sudoers syntax INVALID — removing to avoid breakage"
    rm -f /etc/sudoers.d/kpt-tron
    exit 1
fi

echo
echo "==================================================================="
echo " 3/4  block-height watchdog -> /etc/systemd/system/kpt-tron-watchdog.{service,timer}"
echo "==================================================================="
# The watchdog *script* stays in this deploy dir (the .service ExecStart points
# at it), so its logic can be updated via a normal deploy without root.
chmod +x "$HERE/kpt-tron-watchdog.sh"
install -m 0644 "$HERE/kpt-tron-watchdog.service" /etc/systemd/system/kpt-tron-watchdog.service
install -m 0644 "$HERE/kpt-tron-watchdog.timer"   /etc/systemd/system/kpt-tron-watchdog.timer
echo "✅ installed"

echo
echo "==================================================================="
echo " 4/4  systemctl daemon-reload + enable watchdog timer"
echo "==================================================================="
systemctl daemon-reload
systemctl enable --now kpt-tron-watchdog.timer
echo "✅ watchdog timer enabled:"
systemctl status kpt-tron-watchdog.timer --no-pager -l | head -n 6 || true
echo "✅ done"

echo
echo "==================================================================="
echo " NEXT (do NOT run yet if the DB snapshot is not extracted):"
echo "   After the snapshot is downloaded + extracted into output-directory,"
echo "   enable + start the node (both are passwordless for bisq):"
echo
echo "       sudo systemctl enable kpt-tron    # start on boot"
echo "       sudo systemctl start  kpt-tron    # start now"
echo
echo "   Then check:"
echo "       systemctl status kpt-tron"
echo "       tail -f /home/bisq/kpt/kpt-tron/logs/tron.log"
echo "==================================================================="
