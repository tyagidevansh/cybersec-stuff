# Detection & hardening (break the chain at every phase)

## Phase 1 — recon

- **Detect:** IDS rule on SYN-sweep tempo (many distinct ports, one source,
  seconds); firewall log reviews; the NSE user-agent in web logs is a free
  signature.
- **Harden:** default-deny firewall — expose 22/80 only to known sources;
  port-scan tarpits/rate-limits; don't banner exact versions (`ServerTokens
  Prod`, `sshd -T` banner minimal) to slow fingerprinting.

## Phase 2 — brute force

- **Detect:** `Failed password` velocity alert (e.g. ≥5/min from one IP);
  correlate with phase-1 source — same IP scanning then guessing is the
  escalation signal.
- **Harden:** **fail2ban** (temporary IP ban on N failures — kills this
  attack outright); disable `PasswordAuthentication`, require keys;
  non-obvious usernames; MFA for SSH.

## Phase 3 — initial access

- **Detect:** first-seen login from a new source IP; login at unusual hour;
  successful login immediately after failures from the same IP (the
  fail→success adjacency is the classic compromised-account signature).
- **Harden:** key-only + MFA means the guessed password alone is useless;
  alert on any interactive SSH to hosts that normally take none.

## Phase 4 — exfiltration

- **Detect:** egress alerting — internal server POSTing to an external/high
  port it never talks to; DLP on `salary_backup.csv` / `ACCT-44*` patterns;
  unusual `curl` user-agent leaving a server.
- **Harden:** egress firewall (servers initiate only to approved
  destinations); remove `curl`/compilers from production hosts; file
  integrity monitoring on sensitive files; backups of payroll data
  encrypted with access logging.

## Logging baseline (so the next investigation has evidence)

- sshd `LogLevel VERBOSE`, auth logs shipped off-host (attacker who owns
  the box edits local logs).
- nginx access logs retained with User-Agent.
- Full-packet capture is expensive — NetFlow/IPFIX + NIDS (Suricata/Zeek)
  gives 90% of this lab's visibility at 1% of the storage.
