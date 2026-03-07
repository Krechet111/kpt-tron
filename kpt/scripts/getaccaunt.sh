NODE="http://89.23.100.234:8091"
FROM_HEX="41E4E4E8A24A5D18A9ACFEED19EC359498F068F59E"

curl -s -X POST "$NODE/wallet/getaccount" \
  -H "Content-Type: application/json" \
  -d "{\"address\":\"$FROM_HEX\",\"visible\":false}"
