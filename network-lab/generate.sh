#!/bin/bash
# Regenerates artifacts/capture.pcap, auth.log, access.log by staging the
# attack live and capturing it. Takes ~3-4 min (image build + staged sleeps).
# Run from the network-lab/ directory.
set -euo pipefail
cd "$(dirname "$0")"

docker compose down 2>/dev/null || true
rm -f artifacts/capture.pcap artifacts/auth.log artifacts/access.log
docker compose up -d --build
echo "[*] waiting for services + capture to settle..."
sleep 6

echo "[*] starting exfil receiver on attacker"
docker compose exec -T -d attacker python3 /opt/receiver.py
sleep 1

echo "[*] running staged attack"
docker compose exec -T attacker bash /opt/attack.sh

echo "[*] stopping capture, collecting logs"
sleep 2
docker compose exec -T victim pkill tcpdump
sleep 2
docker compose exec -T victim bash -c \
  'cp /var/log/auth.log /captures/auth.log; cp /var/log/nginx/access.log /captures/access.log; chmod 644 /captures/*; ls -l /captures'
docker compose down
echo "[*] artifacts ready in ./artifacts/"
