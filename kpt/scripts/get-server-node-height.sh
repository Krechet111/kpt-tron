curl -s -X POST http://186.246.12.181:8091/wallet/getnowblock \
  -d '{}' | grep -o '"number":[0-9]*' | cut -d: -f2
