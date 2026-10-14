#!/bin/bash
# Deploys the inherited (vulnerable) infrastructure. You are not supposed to
# read vulnerable/*.tf yet — Task 7 opens the blueprints. Just build it.
set -euo pipefail
cd "$(dirname "$0")/vulnerable"
export PATH="$HOME/.local/bin:$PATH"
terraform init -input=false >/dev/null
terraform apply -auto-approve -input=false >/dev/null
echo "inherited infrastructure deployed (8 resources). Start at Task 1."
