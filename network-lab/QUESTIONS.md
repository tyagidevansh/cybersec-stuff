# Investigation questions

Answer from `artifacts/capture.pcap` + `auth.log` + `access.log` only.
Don't read `docker/attacker/attack.sh` (the answer key) or `WALKTHROUGH.md`
until you've written your answers down. Needed: Wireshark (or `tshark`).

Set Wireshark's time column first: View → Time Display Format → Date and
Time of Day. You'll need real timestamps for Q8.

## Hosts & services

1. How many hosts talk on the 10.89.0.0/24 network in the capture, and what
   are their IPs? (Hint: Statistics → Conversations, or filter `arp`.)
2. Which TCP ports are open on 10.89.0.10, and what services/versions run
   there? Name two places this is revealed — one in traffic, one in logs.

## Recon

3. An early burst of packets hits ~100 destination ports in a fraction of a
   second. What scan type is it, and what display filter isolates it?
   Which host is the scanner?
4. `access.log` contains requests with a distinctive User-Agent. What is it,
   and what phase-1 tool does it fingerprint?

## Brute force & access

5. How many failed SSH logins are in `auth.log`? Which account was targeted,
   and from which IP?
6. SSH is encrypted, so the passwords never appear in the PCAP. How can you
   still count the login *attempts* purely from Wireshark? (Hint: how many
   TCP sessions hit port 22, and what do their sizes/durations look like
   next to real session traffic?)
7. Was the attacker ever successful? Quote the exact log line(s) and give
   the timestamp(s).

## Exfiltration

8. After the successful login, one HTTP request carries the stolen data.
   What are its method, path, source, and destination? (Hint: `http.request`.)
9. Follow that TCP stream. What file was stolen, and name two rows of its
   contents. Why was this readable despite the earlier SSH encryption?

## Synthesis

10. Build the timeline: four phases with start times and one evidence
    pointer each (packet range or log line).
11. List five IoCs you'd share with another team (see `INDICATORS.md` only
    after answering).
12. Name three controls that would have broken this chain at three
    different phases — and say which phase each kills.
