#!/bin/bash
# One-time setup: starts ollama, pulls the base model (~1GB), builds helpbot.
# Idempotent — safe to re-run. Takes a few minutes on first run.
set -euo pipefail
cd "$(dirname "$0")"

docker compose up -d
echo "[*] waiting for ollama..."
for _ in $(seq 1 30); do
  curl -s -m 2 http://localhost:11434/ >/dev/null && break
  sleep 2
done
curl -s -m 2 http://localhost:11434/ >/dev/null || { echo "ollama not up"; exit 1; }

CID=$(docker compose ps -q ollama)
docker compose exec -T ollama ollama pull qwen2.5:1.5b
docker cp Modelfile "$CID:/tmp/Modelfile"
docker compose exec -T ollama ollama create helpbot -f /tmp/Modelfile
docker compose exec -T ollama ollama list | grep -q helpbot && echo "[*] helpbot ready"
