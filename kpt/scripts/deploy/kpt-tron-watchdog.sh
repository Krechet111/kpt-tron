#!/usr/bin/env bash
# Block-height watchdog for the kpt-tron node.
#
# Restart=on-failure in the unit catches CRASHES and OOM-kills (the process
# exits). But a *consensus stall* — the JVM is alive and the HTTP API still
# answers, yet the local head block stops advancing — does NOT exit the process,
# so systemd never notices. This watchdog covers exactly that gap: if the node is
# active and past its startup grace period, but its local head block fails to
# advance across several consecutive checks (or the API stops answering), it
# forces a graceful `systemctl restart`.
#
# Run periodically by kpt-tron-watchdog.timer (every ~2 min) as root, so it can
# restart the service directly (no sudo needed).
#
# NOTE: deliberately no `set -e` — a watchdog must survive transient errors
# (a single failed curl, a missing state file) and keep supervising, not die.

SERVICE="kpt-tron"
API="http://127.0.0.1:8091/wallet/getnowblock"
STATE_DIR="${STATE_DIR:-/var/lib/kpt-tron-watchdog}"   # override for a rootless test run
STATE_FILE="${STATE_DIR}/state"                 # "last_height last_restart_ts strikes"

STALL_STRIKES_MAX="${STALL_STRIKES_MAX:-3}"     # consecutive bad checks before restart (~6 min @ 2 min tick)
STARTUP_GRACE="${STARTUP_GRACE:-180}"           # s to let the DB load after (re)start / boot
COOLDOWN="${COOLDOWN:-600}"                      # s to wait after a restart before judging again

log() { echo "[watchdog] $*"; }

mkdir -p "$STATE_DIR"
now=$(date +%s)

# 1. Only supervise a service that is supposed to be running. Respect a manual
#    `systemctl stop` (inactive) and let Restart=on-failure own crash recovery.
if ! systemctl is-active --quiet "$SERVICE"; then
    log "service not active — nothing to supervise."
    : > "$STATE_FILE" 2>/dev/null   # reset so a later fresh start isn't judged on stale data
    exit 0
fi

# 2. Load previous state (default zeros).
last_height=0; last_restart_ts=0; strikes=0
if [ -s "$STATE_FILE" ]; then
    read -r last_height last_restart_ts strikes < "$STATE_FILE"
fi
[ -n "$last_height" ]     || last_height=0
[ -n "$last_restart_ts" ] || last_restart_ts=0
[ -n "$strikes" ]         || strikes=0

# 3. Grace/cooldown: give the node time to load the DB and start advancing before
#    we judge it — right after boot and right after a restart we trigger.
active_since=$(date -d "$(systemctl show "$SERVICE" -p ActiveEnterTimestamp --value)" +%s 2>/dev/null || echo 0)
if [ "$active_since" -gt 0 ] && [ $((now - active_since)) -lt "$STARTUP_GRACE" ]; then
    log "within startup grace ($((now - active_since))s < ${STARTUP_GRACE}s) — skip."
    exit 0
fi
if [ "$last_restart_ts" -gt 0 ] && [ $((now - last_restart_ts)) -lt "$COOLDOWN" ]; then
    log "within post-restart cooldown ($((now - last_restart_ts))s < ${COOLDOWN}s) — skip."
    exit 0
fi

# 4. Query the local head block (a few quick retries against a transient blip).
height=""
for _ in 1 2 3; do
    height=$(curl -s -m 5 -X POST "$API" -d '{}' 2>/dev/null | grep -o '"number":[0-9]*' | head -1 | cut -d: -f2)
    if [ -n "$height" ]; then break; fi
    sleep 2
done

healthy=0
if [ -z "$height" ]; then
    log "API unreachable on an active node — strike ($((strikes + 1))/${STALL_STRIKES_MAX})."
elif [ "$last_height" -eq 0 ]; then
    log "baseline head=$height recorded."
    last_height="$height"; strikes=0; healthy=1
elif [ "$height" -gt "$last_height" ]; then
    log "head advancing ($last_height -> $height) — healthy."
    last_height="$height"; strikes=0; healthy=1
else
    log "head FROZEN at $height (prev $last_height) — strike ($((strikes + 1))/${STALL_STRIKES_MAX})."
fi

# 5. Count strikes; restart once the node has been stuck long enough.
if [ "$healthy" -eq 0 ]; then
    strikes=$((strikes + 1))
    if [ "$strikes" -ge "$STALL_STRIKES_MAX" ]; then
        log "STALL confirmed ($strikes consecutive bad checks) — restarting $SERVICE (graceful)."
        systemctl restart "$SERVICE"
        echo "0 $now 0" > "$STATE_FILE"   # reset baseline height, arm the cooldown
        exit 0
    fi
fi

# Persist: on a strike keep the frozen last_height; on health it was just updated.
echo "$last_height $last_restart_ts $strikes" > "$STATE_FILE"
