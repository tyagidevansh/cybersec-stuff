#!/bin/bash
# Verifies the shipped evidence contains the full staged attack:
# scan -> brute force -> login -> exfil, in order. Needs only tcpdump + grep.
# Usage: bash tests/verify.sh   (run from network-lab/)
set -u
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

cd "$(dirname "$0")/.."
[ -s artifacts/capture.pcap ] && ok "capture.pcap exists" || { bad "capture.pcap exists"; exit 1; }
[ -s artifacts/auth.log ] && ok "auth.log exists" || bad "auth.log exists"
[ -s artifacts/access.log ] && ok "access.log exists" || bad "access.log exists"

PKTS=$(tcpdump -r artifacts/capture.pcap -nn 2>/dev/null | wc -l)
[ "$PKTS" -gt 200 ] && ok "pcap has $PKTS packets" || bad "pcap too small ($PKTS)"

# Phase 1: SYN scan — many SYN-only packets to many distinct ports
SYNS=$(tcpdump -r artifacts/capture.pcap -nn 2>/dev/null | grep -c '10.89.0.20.*> 10.89.0.10.*Flags \[S\]')
[ "$SYNS" -ge 50 ] && ok "SYN scan present ($SYNS SYNs)" || bad "SYN scan ($SYNS)"
PORTS=$(tcpdump -r artifacts/capture.pcap -nn 2>/dev/null | grep -o '10.89.0.10\.[0-9]*: Flags \[S\]' | sort -u | wc -l)
[ "$PORTS" -ge 20 ] && ok "$PORTS distinct ports probed" || bad "ports probed ($PORTS)"

# Phase 2+3: brute force then success in auth.log
FAILED=$(grep -c 'Failed password' artifacts/auth.log)
[ "$FAILED" -ge 10 ] && ok "$FAILED failed logins" || bad "failed logins ($FAILED)"
ACCEPTED=$(grep -c 'Accepted' artifacts/auth.log)
[ "$ACCEPTED" -ge 1 ] && ok "$ACCEPTED successful login(s)" || bad "no Accepted login"
grep -q 'Accepted password for dev from 10.89.0.20' artifacts/auth.log \
  && ok "login attributed to 10.89.0.20" || bad "login attribution"

# Phase 4: HTTP POST exfil with the CSV inside
POSTS=$(tcpdump -r artifacts/capture.pcap -A -nn 2>/dev/null | grep -c 'POST /upload')
[ "$POSTS" -ge 1 ] && ok "POST /upload in traffic" || bad "no POST /upload"
ROWS=$(tcpdump -r artifacts/capture.pcap -A -nn 2>/dev/null | grep -c 'ACCT-44')
[ "$ROWS" -ge 8 ] && ok "exfiltrated CSV readable in pcap" || bad "CSV not found ($ROWS)"

# Nmap service-scan fingerprints in web log
grep -q 'Nmap Scripting Engine' artifacts/access.log \
  && ok "nmap fingerprints in access.log" || bad "no nmap fingerprint"

# Ordering: first SYN (line L1) precedes exfil POST (line L2)
L1=$(tcpdump -r artifacts/capture.pcap -nn 2>/dev/null | grep -n 'Flags \[S\]' | head -1 | cut -d: -f1)
L2=$(tcpdump -r artifacts/capture.pcap -A -nn 2>/dev/null | grep -n 'POST /upload' | head -1 | cut -d: -f1)
[ -n "$L1" ] && [ -n "$L2" ] && [ "$L1" -lt "$L2" ] \
  && ok "scan precedes exfil (line $L1 < $L2)" || bad "event ordering"

echo "--- $PASS passed, $FAIL failed ---"
[ "$FAIL" = "0" ]
