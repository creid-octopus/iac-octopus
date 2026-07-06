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

echo ">>> Initialising Terraform..."
terraform init -input=false

outputs=$(terraform output -json)

# If there are no outputs, print a message and exit
if [ -z "$outputs" ] || [ "$outputs" = "null" ]; then
  echo "  (no outputs)"
  echo ""
  echo "================================================================"
  exit 0
fi

echo ""
echo "================================================================"
echo "  Terraform Outputs"
echo "================================================================"
echo ""


# Print non-sensitive outputs
echo "$outputs" | jq -r '
  to_entries[]
  | select(.value.sensitive == false)
  | "  \(.key)\n    \(.value.value)\n"
'

# List sensitive output names so their existence is visible without exposing values
sensitive=$(echo "$outputs" | jq -r '[to_entries[] | select(.value.sensitive == true) | .key] | join(", ")')
if [ -n "$sensitive" ]; then
  echo "  (skipped sensitive outputs: $sensitive)"
fi

echo ""
echo "================================================================"
