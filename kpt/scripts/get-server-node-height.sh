curl -s -X POST http://89.23.100.234:8091/wallet/getnowblock \
  -d '{}' | grep -o '"number":[0-9]*' | cut -d: -f2
