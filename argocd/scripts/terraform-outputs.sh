#!/usr/bin/env bash
# terraform-outputs.sh — print Terraform outputs to the Octopus task log
#
# Run this as a final "Run a Script" step after a successful Terraform Apply.
# Initialises Terraform, then prints all non-sensitive outputs so values are
# visible in the Octopus task log.
#
# Requires: terraform, jq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${TF_DIR:-$SCRIPT_DIR/../terraform}"

cd "$TF_DIR"

# Redirect init output to verbose — it's noisy and not useful in the task log
echo ">>> Initialising Terraform..."
terraform init -input=false -no-color 2>&1 | while IFS= read -r line; do
  write_verbose "$line"
done

echo ""
echo "================================================================"
echo "  Terraform Outputs"
echo "================================================================"
echo ""

outputs=$(terraform output -json)

# Use write_highlight so values appear in Task Summary as well as the log
while IFS= read -r line; do
  write_highlight "$line"
done < <(echo "$outputs" | jq -r '
  to_entries[]
  | select(.value.sensitive == false)
  | "\(.key): \(.value.value)"
')

# List sensitive outputs by name so their existence is visible
sensitive=$(echo "$outputs" | jq -r '[to_entries[] | select(.value.sensitive == true) | .key] | join(", ")')
if [ -n "$sensitive" ]; then
  echo ""
  echo "  (skipped sensitive outputs: $sensitive)"
fi

echo ""
echo "================================================================"
