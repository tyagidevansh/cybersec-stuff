# Topology — "Acme dev network" incident

```
                    10.89.0.0/24 (bridge: labnet)
   ┌──────────────────────────────┬──────────────────────────────┐
   │                              │                              │
   │  devserver                   │  attacker-01                 │
   │  10.89.0.10                  │  10.89.0.20                  │
   │                              │                              │
   │  • SSH 22 (OpenSSH,          │  • nmap, sshpass, curl       │
   │    user dev / weak pw)       │  • exfil receiver :8000      │
   │  • nginx 80 (intranet +      │                              │
   │    salary_backup.csv)        │                              │
   │  • tcpdump -i any →          │                              │
   │    /captures/capture.pcap    │                              │
   └──────────────────────────────┴──────────────────────────────┘
```

## Roles

| host | role in scenario | your role toward it |
|---|---|---|
| `devserver` (10.89.0.10) | victim: dev box with SSH + intranet | analyze its traffic + logs |
| `attacker-01` (10.89.0.20) | unknown at start — you identify it | attribute the attack to it |

## Evidence collected (all in `artifacts/`)

| file | source | covers |
|---|---|---|
| `capture.pcap` (744 pkts) | tcpdump inside victim, `-i any`, from boot | every phase on the wire |
| `auth.log` | victim sshd (`-E` file logging) | 12 failed + 2 successful SSH logins |
| `access.log` | victim nginx | service-scan probes + fingerprints |

The capture starts before the attack and runs throughout, so the first
packets are idle noise — your timeline starts with the first SYN burst.

## Regenerating

```bash
bash generate.sh   # ~3-4 min: rebuilds, re-attacks, recaptures
bash tests/verify.sh
```

`docker/attacker/attack.sh` is the scenario script. It is the answer key:
don't read it until you've answered `QUESTIONS.md`. (Instructors: it is
also the methodology record — how the evidence was produced.)
