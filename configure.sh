#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"

cat <<'MSG'
GridWatch local configuration

1) Backend: copy backend/.env.example to backend/.env and put your NVIDIA key there (optional).
2) ESP8266: copy firmware/esp8266_gateway/secrets.h.example to firmware/esp8266_gateway/secrets.h and fill Wi-Fi password + laptop LAN IP + ThingSpeak key.
3) Keep both secrets files out of Git / final public uploads.
MSG

cp -n "$ROOT/backend/.env.example" "$ROOT/backend/.env" 2>/dev/null || true
cp -n "$ROOT/firmware/esp8266_gateway/secrets.h.example" "$ROOT/firmware/esp8266_gateway/secrets.h" 2>/dev/null || true
echo "Templates prepared. Edit backend/.env and firmware/esp8266_gateway/secrets.h."
