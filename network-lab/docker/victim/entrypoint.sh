#!/bin/bash
# Victim boot: intranet site, SSH with file logging, full packet capture.
set -e
mkdir -p /captures /run/sshd
nginx
/usr/sbin/sshd -E /var/log/auth.log
tcpdump -i any -U -s0 -w /captures/capture.pcap &
sleep infinity & wait
