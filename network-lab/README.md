# Lab: The Noisy Intruder (Network Security Investigation)

Friday evening. Someone probed a dev server, guessed their way into SSH,
and uploaded something to an outside machine. The evidence is bagged:
one packet capture, two log files. Your job: reconstruct exactly what
happened, in order, with proof — the way a SOC analyst would.

*Time: ~60–90 min · Level: Beginner · Needs: Wireshark (or tshark), a terminal*

## What you'll learn

- How a port scan, a brute-force, a login, and an exfil each look *on the
  wire* — four shapes you'll recognize forever after
- Why encrypted protocols force you to correlate packets with logs (and how)
- How to Follow a TCP stream and read stolen data out of it
- How to build an incident timeline and write shareable IoCs
- Which control breaks each phase of the attack chain

## Key ideas

- **PCAP** — a packet capture file: every frame with timestamps. Ours is
  `artifacts/capture.pcap` (744 packets — small enough to read end to end).
- **SYN scan** — the scanner sends SYN to many ports without completing
  handshakes. Open ports reply SYN-ACK, closed reply RST. Fast, and
  invisible to application logs.
- **Brute force** — many logins, one account, steady cadence. In traffic:
  many short SSH sessions. In logs: `Failed password` lines.
- **Exfiltration** — data leaving. Here: an HTTP POST from the *victim* to
  the attacker. Direction matters — uploads from servers are the tell.
- **IoC** — indicator of compromise: an IP, URL, filename, or pattern you
  can share so others can hunt for the same attacker.

## Your case file

Two hosts on `10.89.0.0/24` (see `TOPOLOGY.md`): `devserver` (10.89.0.10,
SSH + intranet site) and an unknown second machine. Evidence in
`artifacts/`: `capture.pcap`, `auth.log` (SSH logins), `access.log` (web
requests). `QUESTIONS.md` is your assignment — 12 questions, hosts →
recon → brute force → exfil → timeline → IoCs → fixes.

## Setup

No containers needed — the attack already happened; the evidence is
shipped. Install Wireshark (GUI) and friends:

```bash
# Fedora
sudo dnf install -y wireshark wireshark-cli
sudo usermod -aG wireshark "$USER"   # then log out and back in
```

```bash
# Debian/Ubuntu
sudo apt install -y wireshark tshark nmap
sudo usermod -aG wireshark "$USER"   # then log out and back in
```

Verify the evidence reads:

```bash
tcpdump -r artifacts/capture.pcap -nn 2>/dev/null | wc -l
grep -c 'Failed password' artifacts/auth.log
```

```
744
12
```

744 packets, 12 failed logins. Open the capture:

```bash
wireshark artifacts/capture.pcap &
```

First move in Wireshark: View → Time Display Format → Date and Time of
Day. Timelines need real clocks. (Headless? Every Wireshark step below has
a `tshark` twin in `WALKTHROUGH.md`.)

## Task 1 — Who is here?

**Goal:** enumerate the network from the capture alone.

Statistics → Conversations → IPv4: how many speakers? Check the `arp`
filter too — address resolution shows who's asking for whom. Two IPs, one
subnet, no one else. Write them down with roles (server? unknown?).

## Task 2 — What is exposed?

**Goal:** find open ports two independent ways.

In Wireshark, isolate handshake replies from the victim:

```
tcp.flags.syn == 1 && tcp.flags.ack == 1 && ip.src == 10.89.0.10
```

SYN-ACKs mark open ports; RSTs mark closed. Then confirm from the logs:
what did the web server actually serve? If banners or logs name versions,
record them — version strings are the bridge to vulnerability research.

## Task 3 — Catch the scan

**Goal:** identify the recon phase and its source.

Look at the first seconds of the capture: a burst of packets to ~100
different ports. Filter them:

```
tcp.flags.syn == 1 && tcp.flags.ack == 0
```

Same source port sweeping destination ports, no handshakes completed —
that shape is a SYN scan. Who sent it? Then open `access.log`: several
requests carry a User-Agent that names the scanner's toolkit outright.
Two findings, same phase, different layers — note both.

## Task 4 — Count the guesses

**Goal:** prove brute force in logs *and* in traffic.

```bash
grep -E 'Failed|Accepted' artifacts/auth.log
```

One account, one source IP, failure after failure — then success. Now the
analyst's move: SSH is encrypted, so find the attempts in Wireshark
without reading a single password. Filter `tcp.port == 22` and open
Statistics → Conversations → TCP: ~14 short sessions where a normal day
would show one long one. Sessions, not secrets — and check the counts
match the log (12 failed + 2 accepted). Packets and logs agreeing is what
turns suspicion into a finding.

## Task 5 — Read the theft

**Goal:** find the exfil and recover what was stolen.

After the successful login, look for HTTP:

```
http.request.method == POST
```

One request — and check its *direction*: the victim is uploading to the
other machine. Right-click → Follow → TCP Stream: headers first
(`User-Agent: curl/8.5.0` — someone ran curl *on the server*), then the
body. Name the file and two of its rows. Ask yourself why this was
readable when the SSH guesses were not — that contrast is the lesson.

## Task 6 — Write it up

**Goal:** produce the three artifacts of a real investigation.

1. **Timeline** — four phases with timestamps and one evidence pointer
   each (packet cluster or log line). See Q10.
2. **IoCs** — five shareable indicators (Q11; compare with
   `INDICATORS.md` after).
3. **Recommendations** — three controls at three different phases (Q12;
   compare with `HARDENING.md` after).

Then read `WALKTHROUGH.md` and grade yourself honestly: which questions
did traffic answer, which needed logs, and where did you need both?

## What happened

One machine (10.89.0.20) SYN-scanned ~100 ports on devserver, fingerprinted
SSH and HTTP, brute-forced the `dev` account (12 guesses), logged in
twice, and curled the payroll backup out over plaintext HTTP to its own
receiver. Every phase announced itself somewhere: the scan in packet
shapes, the guessing in log velocity, the access in fail→success
adjacency, the theft in an upload no server should make.

For real systems:

- No single telemetry tells the story. Scans live in packets, guesses in
  logs, exfil in egress — collect all three or miss phases.
- Fail→success adjacency (failures then a success, same source) is the
  highest-value alert in authentication monitoring.
- Servers should never initiate uploads to strangers: egress filtering
  would have made phase 4 loud or impossible.

## Questions and answers

**Why couldn't I read the SSH passwords in Wireshark?**
Encryption. You get metadata (who, when, how many sessions, how big) and
the logs supply outcomes. Counting sessions is the standard substitute.

**Why was the CSV readable then?**
The attacker exfiltrated over plain HTTP. Different channel, different
visibility — analysts check both.

**Why didn't the scan appear in the web/SSH logs?**
A SYN scan never completes a connection, so applications never see it.
That's precisely why network capture exists as a separate telemetry layer.

**744 packets seems tiny — are real cases like this?**
Real cases are millions of packets, but the shapes are identical. Small
captures teach shapes; tools (filters, conversations, IO graphs) scale
them.

## Cleanup

Nothing runs — the lab is static evidence. To re-stage the attack from
scratch (regenerates all three artifact files):

```bash
bash generate.sh && bash tests/verify.sh
```
