# Lab: The Cloud Account With No Locks (Cloud Misconfiguration Audit)

Acme Corp hands you credentials to an AWS account and a one-line brief:
*"photo-share app, something's off, tell us what's wrong."* No
architecture doc, no code walkthrough — just a login. Your job: explore
the live account, find every misconfiguration empirically, trace each one
back to the Terraform that caused it, report like a consultant, then roll
out the hardened stack and prove each finding dead.

*Time: ~90–120 min · Level: Beginner (zero cloud experience assumed) · Needs: Docker + Terraform + AWS CLI*

## What you'll learn

- How to explore an unknown cloud account: inventory first, conclusions later
- The five classic misconfigs: public storage, wildcard IAM, open
  firewalls, hardcoded secrets, missing audit trails
- How to read an IAM policy (Effect/Action/Resource) and a firewall table
- How Terraform turns text into infrastructure — and how to diff intent vs reality
- The consultant's workflow: discover live → trace to code → report → fix → re-verify

## Key ideas (read this — everything later assumes it)

- **AWS** — rented computers (EC2), storage (S3), identities (IAM),
  firewalls (security groups). No real account needed: yours is emulated.
- **LocalStack** — a fake AWS in Docker. Same APIs, localhost only, zero
  bill. Two emulator quirks are flagged where they matter (Appendix C).
- **Your credentials:** `test` / `test`, region `us-east-1`. Set them once
  per terminal and alias the CLI at the fake cloud:
  ```bash
  export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_REGION=us-east-1
  alias awslocal='aws --endpoint-url http://localhost:4566'
  ```
- **S3 bucket** — a named cloud folder. A **bucket policy** is a JSON
  document granting API actions — `"Principal": "*"` means everyone on Earth.
- **IAM policy** — `Effect: Allow, Action: ["s3:*"], Resource: "*"` reads
  as "may do every S3 thing to everything." Least privilege = only what's
  needed, where needed.
- **Security group** — virtual firewall. `22/tcp from 0.0.0.0/0` = "SSH
  from the entire internet" (`0.0.0.0/0` = all IPv4).
- **user_data** — a server's boot script, run once as root, retrievable
  later via the API. Passwords in it are passwords on display.
- **Terraform** — the previous admin's tooling: `.tf` files declaring
  desired state, `apply` creating it. You'll meet it in Task 7, not before.

## Your target

One emulated account (`localhost:4566`) holding a photo-share app: storage,
an app role, a firewall, a server. A hardened twin of the same app exists
for the final task. Same names you already know from the A2 pattern:
attack the weak one, verify on the fixed one.

## Setup

```bash
docker compose up -d
for _ in $(seq 1 15); do
  curl -s -m 3 http://localhost:4566/_localstack/health 2>/dev/null | grep -q '"s3"' && break
  sleep 2   # empty replies mean "still booting", not "broken" — just wait
done
bash setup.sh   # builds the inherited infra. Do NOT open vulnerable/ yet.
```

## Task 1 — Inventory: what's even in this account?

**Goal:** list everything before judging anything. Auditors enumerate first.

```bash
awslocal s3 ls
awslocal iam list-roles --query 'Roles[].RoleName'
awslocal ec2 describe-security-groups --query 'SecurityGroups[].GroupName'
awslocal ec2 describe-instances --query 'Reservations[].Instances[0].InstanceId'
```

One bucket, one role, one firewall, one server. Small blast radius to map —
write it down. Every later task hangs evidence off this list.

## Task 2 — Storage: who can read the files?

**Goal:** find the bucket policy and test what it grants.

```bash
awslocal s3 ls s3://acme-photoshare --recursive
awslocal s3api get-bucket-policy --bucket acme-photoshare --query Policy --output text | python3 -m json.tool
```

An `exports/customers.csv` sits in the bucket, and the policy answers
`Principal: "*"` on `s3:GetObject` over everything. That sentence means
"the whole internet may read every file." Test the sentence:

```bash
curl -s http://localhost:4566/acme-photoshare/exports/customers.csv | head -3
```

Customer records, no credentials. (Emulator honesty: LocalStack serves all
S3 anonymously, so the curl alone proves nothing here — the *policy
document* is your evidence, exactly as a real auditor cites it. On real
AWS this curl downloads the file.) **Finding #1: public bucket.** Also ask
what protections exist: any encryption key of ours? Any access logging?
(`get-bucket-encryption` shows only the platform default — no key we own;
`get-bucket-logging` returns nothing. Note both; they're findings #2 and #6.)

## Task 3 — Identity: what can the app's role do?

**Goal:** expand the role's powers into one plain sentence.

```bash
awslocal iam list-role-policies --role-name photoshare-app --query PolicyNames
awslocal iam get-role-policy --role-name photoshare-app --policy-name photoshare-app-broad --query PolicyDocument
```

`s3:*` + `ec2:*` on `*`: whoever holds this role's credentials may do
nearly every storage and server action, on every resource in the account —
issued to an app that uploads thumbnails to one bucket. **Finding #3:
wildcard IAM.** Say the attacker sentence out loud: "one leaked key =
whole account." Blast-radius maximizers like this upgrade every other
finding.

## Task 4 — Network: what doors are open?

**Goal:** read the firewall table like a bouncer's guest list.

```bash
awslocal ec2 describe-security-groups --group-names photoshare-web \
  --query 'SecurityGroups[0].IpPermissions[].[FromPort,IpRanges[0].CidrIp]' --output text
```

```
5432    0.0.0.0/0
22      0.0.0.0/0
80      0.0.0.0/0
```

SSH *and the database* reachable from the entire planet. **Finding #4.**

## Task 5 — Secrets: what does the server carry?

**Goal:** extract what the running instance knows.

Servers tell on themselves: the boot script stays retrievable via the API.

```bash
IID=$(awslocal ec2 describe-instances \
  --query 'Reservations[?Instances[0].State.Name!=`terminated`].Instances[0].InstanceId' --output text | head -1)
awslocal ec2 describe-instance-attribute --instance-id $IID \
  --attribute userData --query UserData.Value --output text | base64 -d
```

A database password in cleartext (`PGPASSWORD="Sup3rSecret123!"`), baked
into a root-run boot script, readable by anyone with EC2 read access.
**Finding #5 (part 1).** Parts 2 and 3 live in the code — park that
thought for Task 7, where you'll follow this one string through the repo.

## Task 6 — The negative: what's missing?

**Goal:** prove the absences auditors fear most.

```bash
awslocal s3api get-bucket-logging --bucket acme-photoshare
```

Empty: nobody records who touches the files. And API-level audit
(CloudTrail)? The emulator doesn't offer that API — which itself teaches
the real-world lesson: you only discover logging gaps *when you go looking*,
usually during an incident. **Finding #6: no audit trail.** (The hardened
stack's answer plus the real-AWS CloudTrail pattern are in Appendix B.)

## Task 7 — Root cause: open the blueprints

**Goal:** trace every live finding to the exact lines that caused it —
now you may open `vulnerable/`.

Map them one by one: the policy block, the absent encryption/logging/
versioning blocks, the wildcard statement, the three ingress rules, and
the secret's journey through `variables.tf` (committed default) →
`user_data.sh` (boot script) → `outputs` (run `terraform output` inside
`vulnerable/` to see it printed). Then the meta-finding:
which of your six findings were *missing resources* rather than wrong
ones? Absence-review (`grep` for logging/trail/versioning across the
`.tf` files) is a distinct audit skill — practice it here deliberately.

Methodology to internalize (the reusable checklist): inventory → expand
every grant into a sentence → hunt absences → follow secrets end to end →
prove everything live (code says intent, live state says truth) → report,
then fix.

## Task 8 — Report, then check yourself

**Goal:** write the consultant's deliverable before reading the key.

Per finding: severity, evidence (command + output), impact as one attacker
sentence ("with X, an attacker can Y"), fix in one line. Calibrate severity
yourself (public data > open SSH > missing logs?), then compare against
**Appendix A**. Grade honestly — especially where your impact sentences
were vaguer than the key's.

## Task 9 — Fix and re-verify

**Goal:** roll out the hardened stack and invert every proof.

```bash
cd vulnerable && terraform destroy   # type: yes — same names can't exist twice
cd ../secure && terraform init && terraform apply   # type: yes
```

Replay Tasks 2–6 against the new names (`acme-photoshare-secure`,
`photoshare-app-scoped`): `NoSuchBucketPolicy` + all-true access block,
`aws:kms` encryption with a rotation-enabled key, exactly three actions on
exactly this bucket, HTTP from one office IP and nothing else, secret
readable only from Secrets Manager with zero secret strings in repo or
boot script, access logging on, versioning on. Then run the examiner:

```bash
bash tests/verify.sh   # 27 checks, live proofs both directions
```

## Appendix A — Findings key (read after Task 8)

| # | severity | finding | evidence | fix (in `secure/`) |
|---|---|---|---|---|
| F1 | CRITICAL | bucket policy grants `*` | policy doc; CSV over HTTP | no policy + full public-access block |
| F2 | MEDIUM | no customer-managed encryption (platform default only) | encryption output has no KMS key | KMS key (rotation on) + `aws:kms` rule |
| F3 | CRITICAL | IAM `s3:*`,`ec2:*` on `*` | live policy verbatim | 3 actions on this bucket's ARNs |
| F4 | HIGH | 22/80/5432 ← `0.0.0.0/0` | live ingress table | office-`/32` HTTP only; SSH/DB gone |
| F5 | HIGH | password in committed default + boot script + outputs | grep ×3; live user_data decode | generated + vaulted; boot-time lookup |
| F6 | MEDIUM | no access logging, no audit trail | empty logging response; no such resources | logging → logs bucket; versioning; CloudTrail pattern for real AWS |

## Cleanup

```bash
cd secure && terraform destroy   # type: yes
cd .. && docker compose down -v
```
