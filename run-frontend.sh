#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT/frontend"
command -v python3 >/dev/null || { echo "Python 3 is required."; exit 1; }
echo "GridWatch frontend: http://localhost:5500"
python3 -m http.server 5500
