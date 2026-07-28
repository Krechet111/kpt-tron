#!/usr/bin/env bash
# Sends a server-resources snapshot (CPU/RAM/disk/IO, like resources-check.sh)
# as a Telegram message, plus the tail of the node log as a document, so a
# post-mortem can be done from the chat. Runs via cron alongside the sync report.
#
# Secrets: same env file as tron-sync-report.sh (/home/bisq/.config/tron-telegram.env).
# Telegram is reached via pinned IPv4 149.154.167.220 (see sync script for why).
set -uo pipefail

ENV_FILE="${TRON_TG_ENV:-/home/bisq/.config/tron-telegram.env}"
TG_IP="${TG_IP:-149.154.167.220}"
NODE_API="${NODE_API:-http://127.0.0.1:8091}"
LOG_FILE="${TRON_LOG:-/home/bisq/kpt/kpt-tron/logs/tron.log}"
OUT_LOG="${TRON_TG_LOG:-/home/bisq/kpt/kpt-tron/logs/tron-sync-report.log}"
NODE_DIR="/home/bisq/kpt/kpt-tron"
TAIL_LINES="${TAIL_LINES:-300}"

log() { echo "$(date '+%F %T') diag: $*" >> "$OUT_LOG" 2>/dev/null; }

[ -r "$ENV_FILE" ] || { log "env file $ENV_FILE missing — skip"; exit 0; }
# shellcheck disable=SC1090
source "$ENV_FILE"
if [ -z "${TG_BOT_TOKEN:-}" ] || [ -z "${TG_CHAT_ID:-}" ]; then
    log "token/chat_id empty — skip"; exit 0
fi
API="https://api.telegram.org/bot${TG_BOT_TOKEN}"

# api.telegram.org: prefer system DNS; only if it is unreachable fall back to
# the pinned IPv4 (the unrouted-IPv6 issue on this host has come and gone).
TG_RESOLVE=""
curl -s -m 5 -o /dev/null https://api.telegram.org 2>/dev/null \
    || TG_RESOLVE="--resolve api.telegram.org:443:${TG_IP}"

# --- node quick context + problem gate ---
# Only send the diag (resources + log) when something is wrong: the service is
# not active / API is down, OR the node is desynced by more than the threshold.
BEHIND_THRESHOLD="${BEHIND_THRESHOLD:-1000}"
active=$(systemctl is-active kpt-tron 2>/dev/null || echo unknown)
node=$(curl -s -m 8 -X POST "$NODE_API/wallet/getnowblock" -d '{}' 2>/dev/null | grep -o '"number":[0-9]*' | head -1 | cut -d: -f2)
ver=$(curl -s -m 8 "$NODE_API/wallet/getnodeinfo" 2>/dev/null | grep -oE '"codeVersion":"[^"]+"' | head -1 | cut -d'"' -f4)
main=$(curl -s -m 12 https://api.trongrid.io/wallet/getnowblock 2>/dev/null | grep -oE '"number":[0-9]+' | head -1 | cut -d: -f2)

behind=0
[ -n "${main:-}" ] && [ -n "${node:-}" ] && behind=$(( main > node ? main - node : 0 ))
reason=""
if [ "$active" != "active" ] || [ -z "${node:-}" ]; then
    reason="🔴 нода недоступна (service=${active}, API не отвечает)"
elif [ -n "${main:-}" ] && [ "$behind" -gt "$BEHIND_THRESHOLD" ]; then
    reason="⚠️ рассинхрон: отставание ${behind} блоков (порог ${BEHIND_THRESHOLD})"
fi
# FORCE=1 (ручной полный отчёт) — слать ресурсы+лог даже когда всё в порядке.
if [ "${FORCE:-0}" = "1" ] && [ -z "$reason" ]; then
    reason="ℹ️ ручной полный отчёт (behind=${behind})"
fi
if [ -z "$reason" ]; then
    log "healthy (active, behind=${behind}) — skip diag"
    exit 0
fi

# --- resources (mirrors resources-check.sh) ---
LOAD_AVG=$(awk '{print $1", "$2", "$3}' /proc/loadavg)
CPU_IDLE=$(vmstat 1 2 2>/dev/null | tail -1 | awk '{print $15}')
CPU_USAGE=$(( 100 - ${CPU_IDLE:-100} ))
RAM=$(free -h | awk '/^Mem:/ {printf "всего %s | занято %s | свободно %s", $2, $3, $7}')
SWAP=$(free -h | awk '/^Swap:/ {printf "всего %s | занято %s", $2, $3}')
DISK=$(df -h | grep -vE '^Filesystem|tmpfs|udev|loop|overlay|shm|devtmpfs' \
        | awk '{printf "   %-10s всего %5s | занято %5s (%s) | свободно %5s\n", $6, $2, $3, $5, $4}')
DBSIZE=$(du -sh "$NODE_DIR/output-directory" 2>/dev/null | cut -f1)
IO=$(iostat -d -m 1 2 2>/dev/null | awk '/Device/ {f++} f==2 {getline; while($1!="" && NF>0){printf "   %-6s чтение %5s MB/s | запись %5s MB/s\n", $1, $3, $4; getline}}' | grep -v loop)

MSG="📊 РЕСУРСЫ СЕРВЕРА (KPT Tron)
========================================
🕒 $(date '+%Y-%m-%d %H:%M:%S %Z')
kpt-tron: ${active} | head ${node:-?} | v${ver:-?}
${reason}
----------------------------------------
⚙️  CPU: ${CPU_USAGE}%   Load: ${LOAD_AVG}
🧠 RAM:  ${RAM}
   Swap: ${SWAP}
----------------------------------------
🗄️  Диск:
${DISK}   output-directory: ${DBSIZE:-?}
----------------------------------------
💾 I/O:
${IO:-   (нет данных)}
========================================"

esc=$(printf '%s' "$MSG" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')
http_msg=$(curl -s -o /dev/null -w '%{http_code}' -m 15 \
    $TG_RESOLVE \
    "${API}/sendMessage" \
    --data-urlencode "chat_id=${TG_CHAT_ID}" \
    --data-urlencode "text=<pre>${esc}</pre>" \
    --data "parse_mode=HTML" \
    --data "disable_web_page_preview=true" 2>/dev/null)

# --- node log tail as a document ---
TMP="/tmp/tron-log-tail.$$.log"
tail -n "$TAIL_LINES" "$LOG_FILE" > "$TMP" 2>/dev/null || echo "(no log)" > "$TMP"
http_doc=$(curl -s -o /dev/null -w '%{http_code}' -m 30 \
    $TG_RESOLVE \
    "${API}/sendDocument" \
    -F "chat_id=${TG_CHAT_ID}" \
    -F "caption=tron.log — последние ${TAIL_LINES} строк ($(date '+%H:%M %Z'))" \
    -F "document=@${TMP};filename=tron-tail-$(date '+%Y%m%d-%H%M').log" 2>/dev/null)
rm -f "$TMP"

log "resources http=${http_msg} logdoc http=${http_doc} active=${active} node=${node:-?}"
