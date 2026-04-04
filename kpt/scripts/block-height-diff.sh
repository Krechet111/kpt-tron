#!/bin/bash

# Файл, в котором скрипт будет хранить данные прошлого запуска для расчета скорости
STATE_FILE="/tmp/tron_sync_state.txt"

echo "⏳ Опрашиваем локальную ноду (API)..."
NODE_HEIGHT=$(curl -s -X POST http://89.23.100.234:8091/wallet/getnowblock -d '{}' | grep -o '"number":[0-9]*' | cut -d: -f2)

if [ -z "$NODE_HEIGHT" ]; then
    echo "❌ Ошибка: Не удалось получить ответ от локальной ноды. Проверьте, запущена ли она и открыт ли порт 8091."
    exit 1
fi

echo "⏳ Запрашиваем высоту Tron Mainnet..."
MAINNET_JSON=$(curl -s https://api.trongrid.io/wallet/getnowblock)
MAINNET_HEIGHT=$(echo "$MAINNET_JSON" | jq -r '.block_header.raw_data.number')

if [ -z "$MAINNET_HEIGHT" ] || [ "$MAINNET_HEIGHT" == "null" ]; then
    echo "❌ Ошибка: Не удалось получить данные от Tron API."
    exit 1
fi

# Вычисляем текущую разницу
DIFFERENCE=$((MAINNET_HEIGHT - NODE_HEIGHT))

# Получаем текущее время (для красивого вывода и для вычислений в секундах)
CURRENT_TIME=$(date "+%Y-%m-%d %H:%M:%S")
CURRENT_TS=$(date +%s)

# --- БЛОК РАСЧЕТА ВРЕМЕНИ (ETA) ---
ETA_INFO=""
if [ "$DIFFERENCE" -gt 0 ]; then
    # Проверяем, есть ли данные от предыдущего запуска
    if [ -f "$STATE_FILE" ]; then
        read -r PREV_TS PREV_DIFF < "$STATE_FILE"

        TIME_ELAPSED=$((CURRENT_TS - PREV_TS))
        BLOCKS_CAUGHT_UP=$((PREV_DIFF - DIFFERENCE))

        # Защита от деления на ноль или слишком быстрых перезапусков (меньше 5 секунд)
        if [ "$TIME_ELAPSED" -gt 5 ]; then
            if [ "$BLOCKS_CAUGHT_UP" -gt 0 ]; then
                # Считаем скорость (догоняемых блоков в минуту)
                SPEED_PER_MIN=$(( BLOCKS_CAUGHT_UP * 60 / TIME_ELAPSED ))

                # Считаем, сколько секунд осталось до полной синхронизации
                ETA_SECONDS=$(( (DIFFERENCE * TIME_ELAPSED) / BLOCKS_CAUGHT_UP ))
                ETA_HOURS=$(( ETA_SECONDS / 3600 ))
                ETA_MINS=$(( (ETA_SECONDS % 3600) / 60 ))

                # Вычисляем точное время завершения
                FINISH_TIME=$(date -d "@$((CURRENT_TS + ETA_SECONDS))" "+%Y-%m-%d %H:%M" 2>/dev/null || date -r $((CURRENT_TS + ETA_SECONDS)) "+%Y-%m-%d %H:%M" 2>/dev/null)

                ETA_INFO="🚀 Скорость догона: ~$'${SPEED_PER_MIN}' блоков/мин\n⏳ Осталось до финиша: ${ETA_HOURS} ч ${ETA_MINS} мин (Ориентировочно: ${FINISH_TIME})"
            else
                ETA_INFO="⚠️ Нода отстает сильнее, чем догоняет (или стоит на месте). Сеть растет быстрее."
            fi
        else
            ETA_INFO="⏳ Нужно чуть больше времени для расчета. Запустите скрипт еще раз через минуту."
        fi
    else
        ETA_INFO="⏳ Это первый запуск. Расчет времени появится при следующем запуске."
    fi
    # Сохраняем текущие данные для следующего запуска
    echo "$CURRENT_TS $DIFFERENCE" > "$STATE_FILE"
else
    # Если синхронизировались, удаляем временный файл
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