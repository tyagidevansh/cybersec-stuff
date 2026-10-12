# Walkthrough (solution — read after attempting QUESTIONS.md)

All commands assume `artifacts/` as context; `tshark` forms are given beside
each Wireshark move so headless students can follow identically.

## Q1 — hosts

Conversations (Statistics → Conversations → IPv4) shows exactly two
speakers: **10.89.0.10** (devserver) and **10.89.0.20** (attacker-01), plus
`arp` chatter (`arp` filter: who-has 10.89.0.10/20). No one else exists on
this /24 — a two-host universe keeps attribution unambiguous.

## Q2 — open ports & versions

In traffic: the scan burst gets SYN-ACK replies only on **22** and **80**
— everything else is RST (closed). Filter:

```
tcp.flags.syn == 1 && tcp.flags.ack == 1 && ip.src == 10.89.0.10
```

In logs: `access.log` shows HTTP served on 80 throughout. And the attacker's
own version scan (visible as follow-up connections) identified
`OpenSSH 9.6p1 Ubuntu` and `nginx 1.24.0` — the service banners are in the
clear before encryption / as HTTP Server headers. Two independent
confirmations: handshake behavior + banners.

## Q3 — the scan

```
tcp.flags.syn == 1 && tcp.flags.ack == 0 && ip.src == 10.89.0.20
```

~125 **SYN-only** packets from 10.89.0.20 to ~100 distinct ports on
10.89.0.10 within the same second (e.g. `…58791 > 10.89.0.10.135: Flags
[S]`, `….587: Flags [S]`, `….199: Flags [S]` — same source port, sweeping
destination ports). SYN without completing the handshake = **SYN / stealth
scan** (nmap `-sS`): open ports answer SYN-ACK, closed answer RST, and no
full connection is ever logged by the application layer. Scanner:
**10.89.0.20**. `tshark -r capture.pcap -Y 'tcp.flags.syn==1 && tcp.flags.ack==0' | wc -l`

## Q4 — the User-Agent fingerprint

```
"Mozilla/5.0 (compatible; Nmap Scripting Engine; https://nmap.org/book/nse.html)"
```

Eight hits in `access.log` (`GET /nmaplowercheck…`, `GET /HNAP1`, `POST
/sdk`…). These are nmap's **service/version probes** (`-sV`): harmless
looking HTTP requests whose UA confesses the tool. Lesson: phase-1 tooling
often signs its work in application logs even when the scan itself stays
below the log layer.

## Q5 — brute force

```bash
grep -c 'Failed password' artifacts/auth.log   # 12
grep 'Failed' artifacts/auth.log | head -2
```

```
Failed password for dev from 10.89.0.20 port 53114 ssh2
Failed password for dev from 10.89.0.20 port 53124 ssh2
```

12 failures, account **`dev`**, source **10.89.0.20**, one per source port
= one TCP connection per guess. Password-guessing leaves exactly this
shape: many short sessions, one username, steady cadence.

## Q6 — counting attempts without reading passwords

SSH encrypts, so filter `ssh` shows blobs — but *metadata* survives:

```
tcp.port == 22
```

then Statistics → Conversations → TCP: ~14 short conversations from
.20 to .10:22 (12 failed + 2 successful), each a few KB, versus normal SSH
which would be one long session. Count sessions, not secrets: every
connection attempt opens a new TCP session whether auth succeeds or not.
Cross-check: 12 `Failed` + 2 `Accepted` = 14 sessions in `auth.log` —
packets and logs agree, which is the verification habit this lab teaches.

## Q7 — success

```bash
grep 'Accepted' artifacts/auth.log
```

```
Accepted password for dev from 10.89.0.20 port 35496 ssh2
Accepted password for dev from 10.89.0.20 port 35502 ssh2
```

Two successful logins as `dev` from the attacker's IP. The weak password
fell; the second session is the working session (exfil runs inside it).

## Q8 — the exfil request

```
http.request.method == POST
```

One hit: `POST /upload` from **10.89.0.10 → 10.89.0.20:8000** — note the
*direction*: the victim uploads to the attacker's receiver. Headers show
`User-Agent: curl/8.5.0` — the attacker ran curl *on the victim* over their
SSH shell. Timestamp sits minutes after the second `Accepted` line: access
first, theft second.

## Q9 — the stolen file

Right-click the POST → Follow → TCP Stream (or
`tshark -r capture.pcap -Y 'tcp.port==8000' -T fields -e http.file_data`):
the body is **`salary_backup.csv`**, 8 employee rows in cleartext, e.g.

```
1001,Carter,Alice,Engineering,92000,ACCT-4410
1004,Reyes,Dan,Engineering,105000,ACCT-4413
```

Readable because HTTP (not HTTPS) carried it: the attacker chose the
plaintext channel, and lawful-capture sees all of it. Contrast with Q6 —
*this* is why analysts pray for unencrypted exfil and settle for metadata
on SSH. Both outcomes teach the same lesson from opposite sides.

## Q10 — timeline (your timestamps will match to the minute)

| # | phase | evidence |
|---|---|---|
| 1 | recon: SYN sweep ~100 ports + `-sV` probes | SYN burst packet cluster; `access.log` NSE UA lines |
| 2 | brute force: 12 failed `dev` logins | `auth.log` Failed lines; 12 short :22 sessions |
| 3 | access: 2 `Accepted` logins as dev | `auth.log` Accepted lines |
| 4 | exfil: `POST /upload` victim→attacker, CSV body | the POST packet + followed stream |

Gaps of seconds between phases are the scenario's pacing sleeps — real
attacks show human/tooling gaps too; note them, don't smooth them.

## Q11 — IoCs

See `INDICATORS.md` — compare yours before reading. Required five: attacker
IP, targeted account, exfil URL/path, stolen filename, NSE user-agent.

## Q12 — controls

See `HARDENING.md`. One correct set: firewall/restrict SSH exposure (kills
recon value) → fail2ban / key-only auth (kills brute force) → egress
filtering + no curl-on-servers / file monitoring (kills exfil).
