NODE="http://186.246.12.181:8091"
ADDR_BASE58="TWqVHerY7wAnNhsaq7Ky7iQada6bEN98Fe"

curl -s -X POST "$NODE/wallet/getaccount" \
  -H "Content-Type: application/json" \
  -d "{\"address\":\"$ADDR_BASE58\",\"visible\":true}"
 