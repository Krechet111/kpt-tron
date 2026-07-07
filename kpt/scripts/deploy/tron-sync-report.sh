#!/usr/bin/env bash
# Posts kpt-tron node sync status to a Telegram group, formatted like
# block-height-diff.sh (speed + ETA). Intended to run via cron 4x/day.
#
# Secrets live in an env file (NOT committed), default /home/bisq/.config/tron-telegram.env:
#     TG_BOT_TOKEN="123456:ABC-..."
#     TG_CHAT_ID="-1001234567890"
# chmod 600 that file. If it's missing/empty the script no-ops.
#
# Speed/ETA need two samples, so they appear from the SECOND run onward. State
# (ts node mainnet) is kept in its own file, separate from the manual
# block-height-diff.sh state (/tmp/tron_sync_state.txt), so they don't clash.
#
# Note: this host reaches api.telegram.org only via IPv4 149.154.167.220
# (DNS returns IPv6 which is unrouted here), so we pin it with --resolve.
set -uo pipefail

ENV_FILE="${TRON_TG_ENV:-/home/bisq/.config/tron-telegram.env}"
NODE_API="${NODE_API:-http://127.0.0.1:8091}"
TG_IP="${TG_IP:-149.154.167.220}"
LOG="${TRON_TG_LOG:-/home/bisq/kpt/kpt-tron/logs/tron-sync-report.log}"
STATE_FILE="${TRON_TG_STATE:-/home/bisq/kpt/kpt-tron/logs/tron-sync-report.state}"

log() { echo "$(date '+%F %T') $*" >> "$LOG" 2>/dev/null; }

[ -r "$ENV_FILE" ] || { log "env file $ENV_FILE missing — skip"; exit 0; }
# shellcheck disable=SC1090
source "$ENV_FILE"
if [ -z "${TG_BOT_TOKEN:-}" ] || [ -z "${TG_CHAT_ID:-}" ]; then
    log "TG_BOT_TOKEN/TG_CHAT_ID empty in $ENV_FILE — skip"; exit 0
fi

# --- gather ---
active=$(systemctl is-active kpt-tron 2>/dev/null || echo unknown)
node=$(curl -s -m 8 -X POST "$NODE_API/wallet/getnowblock" -d '{}' 2>/dev/null | grep -o '"number":[0-9]*' | head -1 | cut -d: -f2)
main=$(curl -s -m 12 https://api.trongrid.io/wallet/getnowblock 2>/dev/null | grep -oE '"number":[0-9]+' | head -1 | cut -d: -f2)

NOW_TS=$(date +%s)
CHECK_TIME=$(date '+%Y-%m-%d %H:%M:%S')
SEP="----------------------------------------"
BAR="========================================"

send() {
    # $1 = message body (plain text); wrapped in <pre> for monospace alignment
    local body esc
    esc=$(printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')
    local http
    http=$(curl -s -o /tmp/tron-tg-report.out -w '%{http_code}' -m 15 \
        --resolve "api.telegram.org:443:${TG_IP}" \
        "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${TG_CHAT_ID}" \
        --data-urlencode "text=<pre>${esc}</pre>" \
        --data "parse_mode=HTML" \
        --data "disable_web_page_preview=true" 2>/dev/null)
    log "sent http=${http} node=${node:-?} main=${main:-?} resp=$(head -c 160 /tmp/tron-tg-report.out 2>/dev/null)"
    [ "$http" = "200" ]
}

# --- node/API down: alert and stop ---
if [ "$active" != "active" ] || [ -z "${node:-}" ]; then
    MSG="📊 СТАТУС СИНХРОНИЗАЦИИ TRON NODE
${BAR}
🕒 Время проверки:     ${CHECK_TIME}
${SEP}
🔴 Нода НЕДОСТУПНА (service=${active}, API не отвечает)
${BAR}"
    send "$MSG"
    exit 0
fi

main=${main:-0}
DIFFERENCE=$(( main - node ))

ETA_INFO=""
if [ "$DIFFERENCE" -gt 0 ]; then
    if [ -f "$STATE_FILE" ]; then
        read -r PREV_TS PREV_NODE PREV_MAIN < "$STATE_FILE" 2>/dev/null || true
        if [ -n "${PREV_MAIN:-}" ]; then
            TIME_ELAPSED=$(( NOW_TS - PREV_TS ))
            LOCAL_PROCESSED=$(( node - PREV_NODE ))
            MAIN_PROCESSED=$(( main - PREV_MAIN ))
            if [ "$TIME_ELAPSED" -gt 5 ]; then
                LOCAL_SPEED=$(( LOCAL_PROCESSED * 60 / TIME_ELAPSED ))
                MAIN_SPEED=$(( MAIN_PROCESSED * 60 / TIME_ELAPSED ))
                CATCH_UP=$(( LOCAL_SPEED - MAIN_SPEED ))
                SPEED_BLOCK="⚡ Скорость локальной ноды: ~${LOCAL_SPEED} блоков/мин
🌐 Скорость сети (Mainnet):  ~${MAIN_SPEED} блоков/мин
${SEP}"
                if [ "$CATCH_UP" -gt 0 ]; then
                    ETA_SECONDS=$(( DIFFERENCE * 60 / CATCH_UP ))
                    ETA_H=$(( ETA_SECONDS / 3600 ))
                    ETA_M=$(( (ETA_SECONDS % 3600) / 60 ))
                    FINISH=$(date -d "@$(( NOW_TS + ETA_SECONDS ))" '+%Y-%m-%d %H:%M' 2>/dev/null || echo '?')
                    ETA_INFO="${SPEED_BLOCK}
📈 Чистая скорость догона:  ~${CATCH_UP} блоков/мин
⏳ Осталось до финиша:      ${ETA_H} ч ${ETA_M} мин (Ориентировочно: ${FINISH})"
                else
                    ETA_INFO="${SPEED_BLOCK}
⚠️ Нода обрабатывает блоки медленнее, чем они появляются в сети. Отставание увеличивается."
                fi
            else
                ETA_INFO="⏳ Слишком быстрый повторный запуск — расчёт скорости при следующем."
            fi
        else
            ETA_INFO="⏳ Расчёт скорости появится при следующем запуске."
        fi
    else
        ETA_INFO="⏳ Это первый запуск. Расчёт скорости появится при следующем запуске."
    fi
    echo "$NOW_TS $node $main" > "$STATE_FILE"
else
    rm -f "$STATE_FILE"
fi

if [ "$DIFFERENCE" -gt 0 ]; then
    STATUS_LINE="⚠️ Нода отстает на: ${DIFFERENCE} блоков
${SEP}
${ETA_INFO}"
elif [ "$DIFFERENCE" -eq 0 ]; then
    STATUS_LINE="✅ Нода полностью синхронизирована (Full Sync)!"
else
    STATUS_LINE="✅ Синхронизировано (Разница: ${DIFFERENCE})"
fi

MSG="📊 СТАТУС СИНХРОНИЗАЦИИ TRON NODE
${BAR}
🕒 Время проверки:     ${CHECK_TIME}
${SEP}
Высота сети (Mainnet): ${main}
Высота вашей ноды:     ${node}
${SEP}
${STATUS_LINE}
${BAR}"

send "$MSG"
