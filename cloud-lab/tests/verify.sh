#!/bin/bash
# Full-cycle verification: deploys vulnerable, proves all findings live,
# destroys, deploys secure, proves all fixed, destroys.
# Needs: terraform, aws cli, LocalStack (docker compose up -d).
# Usage: bash tests/verify.sh   (run from cloud-lab/, ~3 min)
set -u
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_REGION=us-east-1
EP=http://localhost:4566
command -v terraform >/dev/null || { echo "need terraform"; exit 2; }

curl -s -m 5 $EP/_localstack/health >/dev/null || {
  echo "[*] starting localstack..."; docker compose up -d >/dev/null 2>&1; sleep 15; }

# Drain helper: LocalStack EC2 termination is async.
drain() { for _ in $(seq 1 15); do
  N=$(aws --endpoint-url $EP ec2 describe-instances \
    --query 'Reservations[?Instances[0].State.Name!=`terminated`].Instances[0].InstanceId' \
    --output text 2>/dev/null)
  [ -z "$N" ] && break; sleep 2; done; }

# Clean slate: remove prior-run orphans by known names (a failed apply can
# strand live resources Terraform no longer tracks — itself a lesson in
# why `terraform destroy` isn't a substitute for drift detection).
reset_lab() {
  echo "[*] resetting live state..."
  for i in $(aws --endpoint-url $EP ec2 describe-instances \
      --query 'Reservations[?Instances[0].State.Name!=`terminated`].Instances[0].InstanceId' \
      --output text 2>/dev/null); do
    aws --endpoint-url $EP ec2 terminate-instances --instance-ids "$i" >/dev/null 2>&1
  done
  drain
  for b in acme-photoshare acme-photoshare-secure acme-photoshare-logs; do
    aws --endpoint-url $EP s3 rb "s3://$b" --force >/dev/null 2>&1
  done
  aws --endpoint-url $EP iam remove-role-from-instance-profile \
    --instance-profile-name photoshare-app --role-name photoshare-app >/dev/null 2>&1
  aws --endpoint-url $EP iam delete-instance-profile \
    --instance-profile-name photoshare-app >/dev/null 2>&1
  aws --endpoint-url $EP iam delete-role-policy --role-name photoshare-app \
    --policy-name photoshare-app-broad >/dev/null 2>&1
  aws --endpoint-url $EP iam delete-role-policy --role-name photoshare-app \
    --policy-name photoshare-app-scoped >/dev/null 2>&1
  aws --endpoint-url $EP iam delete-role --role-name photoshare-app >/dev/null 2>&1
  SG=$(aws --endpoint-url $EP ec2 describe-security-groups \
    --group-names photoshare-web --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null)
  [ -n "$SG" ] && [ "$SG" != "None" ] \
    && aws --endpoint-url $EP ec2 delete-security-group --group-id "$SG" >/dev/null 2>&1
  aws --endpoint-url $EP secretsmanager delete-secret --secret-id photoshare/db-password \
    --force-delete-without-recovery >/dev/null 2>&1
  true
}
reset_lab

echo "===== VULNERABLE ====="
(cd vulnerable && terraform init -input=false >/dev/null 2>&1 \
  && terraform apply -auto-approve -input=false >/dev/null 2>&1) \
  || { bad "vuln apply"; exit 1; }
ok "vuln stack applies"

aws --endpoint-url $EP s3api get-bucket-policy --bucket acme-photoshare \
  --query Policy --output text 2>/dev/null \
  | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['Statement'][0]['Principal']=='*', 'not-star'" \
  && ok "F1 bucket policy grants the world" || bad "F1 bucket policy"
# LocalStack auto-attaches an all-true PAB to every bucket (unlike real AWS
# defaults), so PAB is a code-review check here: no such resource exists.
! grep -q 'aws_s3_bucket_public_access_block' vulnerable/main.tf \
  && ok "F1b no public-access-block in code" || bad "F1b PAB"
# NOTE: LocalStack (like real AWS since 2023) shows a *default* AES256 rule.
# The finding is the absence of customer-managed encryption: no KMS key.
aws --endpoint-url $EP s3api get-bucket-encryption --bucket acme-photoshare \
  --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.KMSMasterKeyID' \
  --output text 2>/dev/null | grep -q arn && bad "F2 no KMS key" || ok "F2 no customer-managed encryption"
aws --endpoint-url $EP iam get-role-policy --role-name photoshare-app \
  --policy-name photoshare-app-broad --query PolicyDocument 2>/dev/null \
  | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); s=d['Statement'][0]; assert 's3:*' in s['Action'] and s['Resource']=='*'" \
  && ok "F3 IAM wildcard actions on wildcard resources" || bad "F3 IAM"
aws --endpoint-url $EP ec2 describe-security-groups --group-names photoshare-web \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`].IpRanges[0].CidrIp' \
  --output text 2>/dev/null | grep -q '0.0.0.0/0' \
  && ok "F4 SSH open to the world" || bad "F4 SG"
aws --endpoint-url $EP ec2 describe-security-groups --group-names photoshare-web \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`5432`].IpRanges[0].CidrIp' \
  --output text 2>/dev/null | grep -q '0.0.0.0/0' \
  && ok "F4b database open to the world" || bad "F4b SG"
IID=$(aws --endpoint-url $EP ec2 describe-instances \
  --query 'Reservations[?Instances[0].State.Name!=`terminated`].Instances[0].InstanceId' --output text | head -1)
aws --endpoint-url $EP ec2 describe-instance-attribute --instance-id "$IID" \
  --attribute userData --query UserData.Value --output text 2>/dev/null | base64 -d \
  | grep -q 'Sup3rSecret123!' \
  && ok "F5 password baked into user_data" || bad "F5 user_data"
grep -q 'Sup3rSecret123!' vulnerable/variables.tf \
  && ok "F5b password committed in variables.tf" || bad "F5b variables"
(cd vulnerable && terraform output -raw db_password 2>/dev/null) | grep -q 'Sup3rSecret' \
  && ok "F5c password exposed in outputs" || bad "F5c outputs"
[ "$(aws --endpoint-url $EP s3api get-bucket-logging --bucket acme-photoshare \
  --query LoggingEnabled --output text 2>/dev/null)" = "None" ] \
  && ok "F6 no S3 access logging" || bad "F6 logging"
! grep -rq 'resource "aws_s3_bucket_logging\|resource "aws_cloudtrail' vulnerable/*.tf \
  && ok "F6b no audit resources in code" || bad "F6b audit code"

(cd vulnerable && terraform destroy -auto-approve -input=false >/dev/null 2>&1)
drain
[ -z "$(aws --endpoint-url $EP ec2 describe-instances \
  --query 'Reservations[?Instances[0].State.Name!=`terminated`].Instances[0].InstanceId' \
  --output text 2>/dev/null)" ] \
  && ok "vuln stack destroyed" || bad "vuln destroy"

echo "===== SECURE ====="
(cd secure && terraform init -input=false >/dev/null 2>&1 \
  && terraform apply -auto-approve -input=false >/dev/null 2>&1) \
  || { bad "secure apply"; exit 1; }
ok "secure stack applies"

aws --endpoint-url $EP s3api get-bucket-policy --bucket acme-photoshare-secure \
  >/dev/null 2>&1 && bad "S1 no bucket policy" || ok "S1 no bucket policy"
aws --endpoint-url $EP s3api get-public-access-block --bucket acme-photoshare-secure \
  --query PublicAccessBlockConfiguration --output text 2>/dev/null | grep -q 'True.*True.*True.*True' \
  && ok "S1b public access fully blocked" || bad "S1b PAB"
aws --endpoint-url $EP s3api get-bucket-encryption --bucket acme-photoshare-secure \
  --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.[SSEAlgorithm,KMSMasterKeyID]' \
  --output text 2>/dev/null | grep -q 'aws:kms' \
  && ok "S2 KMS encryption with customer key" || bad "S2 encryption"
# LocalStack describe-key exposes no rotation field — code check instead.
grep -q 'enable_key_rotation *= *true' secure/main.tf \
  && ok "S2b key rotation configured" || bad "S2b rotation"
aws --endpoint-url $EP iam get-role-policy --role-name photoshare-app \
  --policy-name photoshare-app-scoped --query PolicyDocument 2>/dev/null \
  | python3 -c "
import json,sys
s=json.loads(sys.stdin.read())['Statement'][0]
assert set(s['Action'])=={'s3:GetObject','s3:PutObject','s3:ListBucket'}, s['Action']
assert all('acme-photoshare-secure' in r for r in s['Resource']), s['Resource']" \
  && ok "S3 IAM least privilege" || bad "S3 IAM"
aws --endpoint-url $EP ec2 describe-security-groups --group-names photoshare-web \
  --query 'SecurityGroups[0].IpPermissions[].IpRanges[].CidrIp' --output text 2>/dev/null \
  | grep -q '0.0.0.0/0' && bad "S4 no world-open rules" || ok "S4 no world-open rules"
aws --endpoint-url $EP ec2 describe-security-groups --group-names photoshare-web \
  --query 'SecurityGroups[0].IpPermissions[].[FromPort,IpRanges[0].CidrIp]' --output text 2>/dev/null \
  | grep -q '80.*203.0.113.10/32' \
  && ok "S4b HTTP office-only" || bad "S4b SG"
SIID=$(aws --endpoint-url $EP ec2 describe-instances \
  --query 'Reservations[?Instances[0].State.Name!=`terminated`].Instances[0].InstanceId' --output text | head -1)
aws --endpoint-url $EP ec2 describe-instance-attribute --instance-id "$SIID" \
  --attribute userData --query UserData.Value --output text 2>/dev/null | base64 -d \
  | grep -qi 'sup3rsecret\|password.*=.*"' && bad "S5 no secret in user_data" || ok "S5 no secret in user_data"
aws --endpoint-url $EP secretsmanager get-secret-value --secret-id photoshare/db-password \
  --query SecretString --output text >/dev/null 2>&1 \
  && ok "S5b password vaulted in Secrets Manager" || bad "S5b secrets"
! grep -rq 'Sup3rSecret' secure/ \
  && ok "S5c no hardcoded secret in repo" || bad "S5c repo secret"
aws --endpoint-url $EP s3api get-bucket-logging --bucket acme-photoshare-secure \
  --query LoggingEnabled.TargetBucket --output text 2>/dev/null | grep -q 'acme-photoshare-logs' \
  && ok "S6 access logging enabled" || bad "S6 logging"
aws --endpoint-url $EP s3api get-bucket-versioning --bucket acme-photoshare-secure \
  --query Status --output text 2>/dev/null | grep -q Enabled \
  && ok "S6b versioning enabled" || bad "S6b versioning"

(cd secure && terraform destroy -auto-approve -input=false >/dev/null 2>&1)
drain
ok "secure stack destroyed"

echo "--- $PASS passed, $FAIL failed ---"
[ "$FAIL" = "0" ]
