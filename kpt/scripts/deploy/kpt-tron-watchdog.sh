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
# A JVM restart only heals in-process trouble. If the stall survives the restart
# (e.g. an on-disk DB corrupted by a hard reset — "Tapos failed, different block
# hash"), restarting forever is useless noise. So the watchdog also counts
# restarts that brought NO height progress: after RESTARTS_NO_PROGRESS_MAX of
# them it STOPS restarting and instead alerts a Telegram chat (re-sent every
# ALERT_INTERVAL until fixed). Any real height progress, an admin restart, or a
# reboot resets the counter and re-arms normal supervision.
#
# Run periodically by kpt-tron-watchdog.timer (every ~2 min) as root, so it can
# restart the service directly (no sudo needed).
#
# NOTE: deliberately no `set -e` — a watchdog must survive transient errors
# (a single failed curl, a missing state file) and keep supervising, not die.

SERVICE="kpt-tron"
API="http://127.0.0.1:8091/wallet/getnowblock"
STATE_DIR="${STATE_DIR:-/var/lib/kpt-tron-watchdog}"   # override for a rootless test run
STATE_FILE="${STATE_DIR}/state"   # "last_height last_restart_ts strikes restarts_np last_alert_ts"

STALL_STRIKES_MAX="${STALL_STRIKES_MAX:-3}"     # consecutive bad checks before restart (~6 min @ 2 min tick)
STARTUP_GRACE="${STARTUP_GRACE:-180}"           # s to let the DB load after (re)start / boot
COOLDOWN="${COOLDOWN:-600}"                      # s to wait after a restart before judging again

RESTARTS_NO_PROGRESS_MAX="${RESTARTS_NO_PROGRESS_MAX:-3}"  # give up restarting after this many fruitless restarts
ALERT_INTERVAL="${ALERT_INTERVAL:-21600}"        # s between repeated give-up alerts (6 h)
# Secrets live in the same env file the sync report uses (TG_BOT_TOKEN, TG_CHAT_ID);
# root can read it. api.telegram.org: system DNS first, pinned IPv4 as fallback
# (the unrouted-IPv6 DNS issue on this host has come and gone).
TG_ENV="${TRON_TG_ENV:-/home/bisq/.config/tron-telegram.env}"
TG_IP="${TG_IP:-149.154.167.220}"

log() { echo "[watchdog] $*"; }

# Send a give-up alert to Telegram. Returns non-zero if it could not be sent,
# so the caller can retry on the next tick instead of going silent.
send_alert() {
    # $1 = message body (plain text); wrapped in <pre> for monospace alignment
    [ -r "$TG_ENV" ] || { log "alert skipped: $TG_ENV missing/unreadable"; return 1; }
    # shellcheck disable=SC1090
    source "$TG_ENV"
    if [ -z "${TG_BOT_TOKEN:-}" ] || [ -z "${TG_CHAT_ID:-}" ]; then
        log "alert skipped: TG_BOT_TOKEN/TG_CHAT_ID empty in $TG_ENV"; return 1
    fi
    # Prefer system DNS; only if it is unreachable fall back to the pinned
    # IPv4 (the unrouted-IPv6 issue on this host has come and gone).
    local tg_resolve=""
    curl -s -m 5 -o /dev/null https://api.telegram.org 2>/dev/null \
        || tg_resolve="--resolve api.telegram.org:443:${TG_IP}"
    local esc http
    esc=$(printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')
    http=$(curl -s -o /dev/null -w '%{http_code}' -m 15 \
        $tg_resolve \
        "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${TG_CHAT_ID}" \
        --data-urlencode "text=<pre>${esc}</pre>" \
        --data "parse_mode=HTML" \
        --data "disable_web_page_preview=true" 2>/dev/null)
    log "alert sent http=${http}"
    [ "$http" = "200" ]
}

mkdir -p "$STATE_DIR"
now=$(date +%s)

# 1. Only supervise a service that is supposed to be running. Respect a manual
#    `systemctl stop` (inactive) and let Restart=on-failure own crash recovery.
if ! systemctl is-active --quiet "$SERVICE"; then
    log "service not active — nothing to supervise."
    : > "$STATE_FILE" 2>/dev/null   # reset so a later fresh start isn't judged on stale data
    exit 0
fi

# 2. Load previous state (default zeros; old 3-field state files read fine).
last_height=0; last_restart_ts=0; strikes=0; restarts_np=0; last_alert_ts=0
if [ -s "$STATE_FILE" ]; then
    read -r last_height last_restart_ts strikes restarts_np last_alert_ts < "$STATE_FILE"
fi
[ -n "$last_height" ]     || last_height=0
[ -n "$last_restart_ts" ] || last_restart_ts=0
[ -n "$strikes" ]         || strikes=0
[ -n "$restarts_np" ]     || restarts_np=0
[ -n "$last_alert_ts" ]   || last_alert_ts=0

active_since=$(date -d "$(systemctl show "$SERVICE" -p ActiveEnterTimestamp --value)" +%s 2>/dev/null || echo 0)

# 3. An admin restart (or a reboot) is a deliberate fresh chance: the service
#    became active well after OUR last restart, so somebody else started it —
#    re-arm restarts and the alert. 300 s margin absorbs a slow graceful stop.
if [ "$last_restart_ts" -gt 0 ] && [ "$active_since" -gt $((last_restart_ts + 300)) ] \
   && { [ "$restarts_np" -gt 0 ] || [ "$last_alert_ts" -gt 0 ]; }; then
    log "external (re)start detected — resetting no-progress restart counter."
    restarts_np=0; last_alert_ts=0
fi

# 4. Grace/cooldown: give the node time to load the DB and start advancing before
#    we judge it — right after boot and right after a restart we trigger.
if [ "$active_since" -gt 0 ] && [ $((now - active_since)) -lt "$STARTUP_GRACE" ]; then
    log "within startup grace ($((now - active_since))s < ${STARTUP_GRACE}s) — skip."
    exit 0
fi
if [ "$last_restart_ts" -gt 0 ] && [ $((now - last_restart_ts)) -lt "$COOLDOWN" ]; then
    log "within post-restart cooldown ($((now - last_restart_ts))s < ${COOLDOWN}s) — skip."
    exit 0
fi

# 5. Query the local head block (a few quick retries against a transient blip).
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
    # Baseline is NOT progress: a node stuck on a bad block reports the same
    # height forever, so only an actual advance clears the no-progress counter.
    log "baseline head=$height recorded."
    last_height="$height"; strikes=0; healthy=1
elif [ "$height" -gt "$last_height" ]; then
    log "head advancing ($last_height -> $height) — healthy."
    last_height="$height"; strikes=0; healthy=1
    restarts_np=0; last_alert_ts=0
else
    log "head FROZEN at $height (prev $last_height) — strike ($((strikes + 1))/${STALL_STRIKES_MAX})."
fi

# 6. Count strikes; once the node has been stuck long enough, restart — unless
#    previous restarts brought no progress, then alert instead of flapping.
if [ "$healthy" -eq 0 ]; then
    strikes=$((strikes + 1))
    if [ "$strikes" -ge "$STALL_STRIKES_MAX" ]; then
        if [ "$restarts_np" -ge "$RESTARTS_NO_PROGRESS_MAX" ]; then
            log "STALL persists after ${restarts_np} fruitless restarts — NOT restarting; alerting instead."
            if [ "$last_alert_ts" -eq 0 ] || [ $((now - last_alert_ts)) -ge "$ALERT_INTERVAL" ]; then
                MSG="🚨 TRON NODE: ВОТЧДОГ СДАЛСЯ
========================================
🕒 $(date '+%Y-%m-%d %H:%M:%S')  ($(hostname))
----------------------------------------
Нода стоит на блоке: ${height:-API недоступен}
Рестартов без прогресса: ${restarts_np}
----------------------------------------
Перезапуски НЕ помогают — вероятно,
повреждена БД или проблема вне JVM.
Вотчдог больше НЕ рестартует сервис.
Требуется ручное вмешательство.
(повтор алерта каждые $((ALERT_INTERVAL / 3600)) ч;
ручной systemctl restart kpt-tron
возобновит обычный надзор)
========================================"
                if send_alert "$MSG"; then
                    last_alert_ts="$now"
                fi   # on failure keep old ts so the next tick retries
            fi
            echo "$last_height $last_restart_ts $strikes $restarts_np $last_alert_ts" > "$STATE_FILE"
            exit 0
        fi
        restarts_np=$((restarts_np + 1))
        log "STALL confirmed ($strikes consecutive bad checks) — restarting $SERVICE (graceful, no-progress restart ${restarts_np}/${RESTARTS_NO_PROGRESS_MAX})."
        systemctl restart "$SERVICE"
        echo "0 $now 0 $restarts_np $last_alert_ts" > "$STATE_FILE"   # reset baseline height, arm the cooldown
        exit 0
    fi
fi

# Persist: on a strike keep the frozen last_height; on health it was just updated.
echo "$last_height $last_restart_ts $strikes $restarts_np $last_alert_ts" > "$STATE_FILE"
