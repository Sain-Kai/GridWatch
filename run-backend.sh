#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT/backend"
command -v java >/dev/null || { echo "Java is required."; exit 1; }
command -v mvn >/dev/null || { echo "Maven is required: sudo apt install maven"; exit 1; }
if command -v ollama >/dev/null; then
  if ! curl -fsS http://localhost:11434/api/tags >/dev/null 2>&1; then
    echo "Starting Ollama..."
    (ollama serve >/tmp/gridwatch-ollama.log 2>&1 &)
    sleep 2
  fi
else
  echo "WARNING: Ollama is not installed. NVIDIA embeddings must be available for startup."
fi
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi
# User-level secrets win over an optional project .env so a blank template
# cannot accidentally erase the persistent NVIDIA_API_KEY.
if [[ -f "$HOME/.config/gridwatch/env" ]]; then
  # shellcheck disable=SC1090
  source "$HOME/.config/gridwatch/env"
fi
echo "Starting GridWatch backend on http://localhost:8080"
echo "NVIDIA key: $([[ -n "${NVIDIA_API_KEY:-}" ]] && echo configured || echo not configured)"
mvn spring-boot:run
