#!/bin/bash

# Файл состояния
STATE_FILE="/tmp/tron_sync_state.txt"

echo "⏳ Опрашиваем локальную ноду (API)..."
NODE_HEIGHT=$(curl -s -m 5 -X POST http://186.246.12.181:8091/wallet/getnowblock -d '{}' | grep -o '"number":[0-9]*' | cut -d: -f2)

if [ -z "$NODE_HEIGHT" ]; then
    echo "❌ Ошибка: Не удалось получить ответ от локальной ноды."
    exit 1
fi

echo "⏳ Запрашиваем высоту Tron Mainnet..."
MAX_RETRIES=3
RETRY_COUNT=0
MAINNET_HEIGHT=""

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    MAINNET_JSON=$(curl -s -m 10 https://api.trongrid.io/wallet/getnowblock)
    MAINNET_HEIGHT=$(echo "$MAINNET_JSON" | jq -e -r '.block_header.raw_data.number' 2>/dev/null)

    if [[ "$MAINNET_HEIGHT" =~ ^[0-9]+$ ]]; then
        break
    fi

    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "⚠️ TronGrid API вернул неполный ответ. Попытка $RETRY_COUNT из $MAX_RETRIES..."
    sleep 2
done

if [ -z "$MAINNET_HEIGHT" ] || ! [[ "$MAINNET_HEIGHT" =~ ^[0-9]+$ ]]; then
    echo "❌ Ошибка: Tron API недоступен."
    exit 1
fi

# Вычисляем текущую разницу
DIFFERENCE=$((MAINNET_HEIGHT - NODE_HEIGHT))
CURRENT_TIME=$(date "+%Y-%m-%d %H:%M:%S")
CURRENT_TS=$(date +%s)

# --- БЛОК РАСЧЕТА ВРЕМЕНИ И СКОРОСТИ ---
ETA_INFO=""
if [ "$DIFFERENCE" -gt 0 ]; then
    if [ -f "$STATE_FILE" ]; then
        read -r PREV_TS PREV_NODE PREV_MAINNET < "$STATE_FILE"

        # Защита от старого формата файла состояния
        if [ -z "$PREV_MAINNET" ]; then
            ETA_INFO="⏳ Формат скрипта обновлен. Расчет скорости появится при следующем запуске."
        else
            TIME_ELAPSED=$((CURRENT_TS - PREV_TS))
            LOCAL_PROCESSED=$((NODE_HEIGHT - PREV_NODE))
            MAINNET_PROCESSED=$((MAINNET_HEIGHT - PREV_MAINNET))

            if [ "$TIME_ELAPSED" -gt 5 ]; then
                # Считаем скорости
                LOCAL_SPEED=$(( LOCAL_PROCESSED * 60 / TIME_ELAPSED ))
                MAINNET_SPEED=$(( MAINNET_PROCESSED * 60 / TIME_ELAPSED ))
                CATCH_UP_SPEED=$(( LOCAL_SPEED - MAINNET_SPEED ))

                SPEED_BLOCK="⚡ Скорость локальной ноды: ~${LOCAL_SPEED} блоков/мин\n🌐 Скорость сети (Mainnet):  ~${MAINNET_SPEED} блоков/мин\n----------------------------------------"

                if [ "$CATCH_UP_SPEED" -gt 0 ]; then
                    ETA_SECONDS=$(( DIFFERENCE * 60 / CATCH_UP_SPEED ))
                    ETA_HOURS=$(( ETA_SECONDS / 3600 ))
                    ETA_MINS=$(( (ETA_SECONDS % 3600) / 60 ))
                    FINISH_TIME=$(date -d "@$((CURRENT_TS + ETA_SECONDS))" "+%Y-%m-%d %H:%M" 2>/dev/null || date -r $((CURRENT_TS + ETA_SECONDS)) "+%Y-%m-%d %H:%M" 2>/dev/null)

                    ETA_INFO="${SPEED_BLOCK}\n📈 Чистая скорость догона:  ~${CATCH_UP_SPEED} блоков/мин\n⏳ Осталось до финиша:      ${ETA_HOURS} ч ${ETA_MINS} мин (Ориентировочно: ${FINISH_TIME})"
                else
                    ETA_INFO="${SPEED_BLOCK}\n⚠️ Нода обрабатывает блоки медленнее, чем они появляются в сети. Отставание увеличивается."
                fi
            else
                ETA_INFO="⏳ Слишком быстрый перезапуск. Запустите скрипт через минуту."
            fi
        fi
    else
        ETA_INFO="⏳ Это первый запуск. Расчет скорости появится при следующем запуске."
    fi

    # Сохраняем новые данные
    echo "$CURRENT_TS $NODE_HEIGHT $MAINNET_HEIGHT" > "$STATE_FILE"
else
    rm -f "$STATE_FILE"
fi
# -----------------------------------

# Выводим красивый результат
echo ""
echo "========================================"
echo "📊 СТАТУС СИНХРОНИЗАЦИИ TRON NODE"
echo "========================================"
echo "🕒 Время проверки:     $CURRENT_TIME"
echo "----------------------------------------"
echo "Высота сети (Mainnet): $MAINNET_HEIGHT"
echo "Высота вашей ноды:     $NODE_HEIGHT"
echo "----------------------------------------"

if [ "$DIFFERENCE" -gt 0 ]; then
    printf "⚠️ Нода отстает на: %'d блоков\n" "$DIFFERENCE"
    echo "----------------------------------------"
    echo -e "$ETA_INFO"
elif [ "$DIFFERENCE" -eq 0 ]; then
    echo "✅ Нода полностью синхронизирована (Full Sync)!"
else
    echo "✅ Синхронизировано (Разница: $DIFFERENCE)"
fi
echo "========================================"