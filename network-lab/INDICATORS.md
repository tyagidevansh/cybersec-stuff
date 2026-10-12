# Indicators of compromise (shareable)

| # | type | value | context |
|---|---|---|---|
| 1 | IPv4 (attacker) | `10.89.0.20` | source of scan, brute force, exfil receiver |
| 2 | username targeted | `dev` | 12 failed + 2 successful SSH logins |
| 3 | exfil URL | `http://10.89.0.20:8000/upload` | POST destination, victim-initiated |
| 4 | file exfiltrated | `salary_backup.csv` (8 rows, `ACCT-44*`) | payroll data; match DLP/content rules |
| 5 | user-agent | `Mozilla/5.0 (compatible; Nmap Scripting Engine; …)` | service-scan probes in web logs |
| 6 | tool artifact | `User-Agent: curl/8.5.0` from server to outside | lateral/exfil pattern, not normal server egress |
| 7 | behavior | ~100-port SYN sweep + 14 short :22 sessions | scan-then-bruteforce tempo |

Notes for sharing: (1) is lab-scoped — in production, pair IP with time
window and destination before blocking. (4) doubles as a DLP signature:
alert on `ACCT-44` or `salary_backup.csv` leaving the network. (7) is the
behavioral rule worth keeping: port sweep from X followed within minutes by
repeated SSH failures from X is high-confidence hostile reconnaissance.
