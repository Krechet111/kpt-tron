#!/bin/bash

# NODE_URL="http://89.23.100.234:8091"
NODE_URL="https://api.trongrid.io"

if [ -z "$1" ]; then
    echo "Использование: $0 <TRANSACTION_ID>"
    exit 1
fi

TX_ID=$1

# Функция конвертации HEX -> Base58 (нужен pip install base58)
convert_address() {
    local hex_addr=$1
    if [[ $hex_addr == "null" || -z "$hex_addr" ]]; then echo "N/A"; return; fi
    python3 -c "import base58; print(base58.b58encode_check(bytes.fromhex('$hex_addr')).decode())" 2>/dev/null || echo "$hex_addr"
}

echo "--- Поиск транзакции в вашей ноде ---"

# Получаем ответ и проверяем, что это JSON
RAW_RESPONSE=$(curl -s -X POST "${NODE_URL}/wallet/gettransactionbyid" \
  -H "Content-Type: application/json" \
  -d "{\"value\": \"$TX_ID\"}")

# Проверка на "Not Found" или пустой ответ
if [[ "$RAW_RESPONSE" == "Not Found" ]] || [[ -z "$RAW_RESPONSE" ]]; then
    echo "Ошибка: Сервер вернул 'Not Found'. Проверьте порт (8090 или 8091) и состояние ноды."
    exit 1
fi

# Проверка на пустой JSON объект
if [[ "$RAW_RESPONSE" == "{}" ]]; then
    echo "Транзакция не найдена. Нода еще не синхронизирована до этого блока."
    exit 1
fi

# Извлекаем данные через jq
OWNER_HEX=$(echo "$RAW_RESPONSE" | jq -r '.raw_data.contract[0].parameter.value.owner_address // empty')
TO_HEX=$(echo "$RAW_RESPONSE" | jq -r '.raw_data.contract[0].parameter.value.to_address // empty')
AMOUNT_SUN=$(echo "$RAW_RESPONSE" | jq -r '.raw_data.contract[0].parameter.value.amount // 0')

# Конвертируем
OWNER_T=$(convert_address "$OWNER_HEX")
TO_T=$(convert_address "$TO_HEX")
AMOUNT_TRX=$(echo "scale=6; $AMOUNT_SUN / 1000000" | bc)

echo "--------------------------------------"
echo "ID:      $TX_ID"
echo "Статус:  $(echo "$RAW_RESPONSE" | jq -r '.ret[0].contractRet // "SUCCESS"')"
echo "Блок:    $(echo "$RAW_RESPONSE" | jq -r '.raw_data.ref_block_num')"
echo "От кого: $OWNER_T"
echo "Кому:    $TO_T"
echo "Сумма:   $AMOUNT_TRX TRX"
echo "--------------------------------------"