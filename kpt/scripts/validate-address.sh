NODE="https://api.trongrid.io"
ADDR="TWqVHerY7wAnNhsaq7Ky7iQada6bEN98Fe"

curl -s -X POST "$NODE/wallet/validateaddress" \
  -H "Content-Type: application/json" \
  -d "{\"address\":\"$ADDR\",\"visible\":true}"
