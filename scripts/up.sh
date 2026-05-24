#!/usr/bin/env bash
# Start the EC2 exit node and wait until it's running.
#
# Usage:    ./scripts/up.sh
# Requires: aws CLI, jq, opentofu (or terraform)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF="${ROOT_DIR}/scripts/tf.sh"

# Fetch all terraform outputs in one call. Each tf.sh invocation sources
# .env and refreshes AWS creds (~1-3s), so one -json call is much faster
# than four -raw calls.
OUTPUTS_JSON="$("$TF" output -json 2>/dev/null || true)"
if [[ -z "$OUTPUTS_JSON" || "$OUTPUTS_JSON" == "{}" ]]; then
  echo "ERROR: terraform state has no outputs. Run './scripts/tf.sh apply' first." >&2
  exit 1
fi

INSTANCE_ID="$(jq -r '.instance_id.value      // empty' <<<"$OUTPUTS_JSON")"
REGION="$(   jq -r '.aws_region.value         // empty' <<<"$OUTPUTS_JSON")"
PUBLIC_IP="$(jq -r '.public_ip.value          // empty' <<<"$OUTPUTS_JSON")"
HOSTNAME="$( jq -r '.tailscale_hostname.value // empty' <<<"$OUTPUTS_JSON")"

if [[ -z "$INSTANCE_ID" ]]; then
  echo "ERROR: instance_id not found in terraform state." >&2
  echo "       Run './scripts/tf.sh apply' first to create the instance." >&2
  exit 1
fi
if [[ -z "$REGION" ]]; then
  echo "WARN: aws_region output missing (old state file?)." >&2
  echo "      Run './scripts/tf.sh apply' to refresh; falling back to ap-northeast-1." >&2
  REGION="ap-northeast-1"
fi

STATE="$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query 'Reservations[0].Instances[0].State.Name' \
  --output text)"

echo "instance: $INSTANCE_ID ($REGION)  current state: $STATE"

case "$STATE" in
  running)
    echo "already running."
    ;;
  stopped)
    echo "starting..."
    aws ec2 start-instances --instance-ids "$INSTANCE_ID" --region "$REGION" >/dev/null
    aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"
    echo "running."
    ;;
  pending|stopping|shutting-down)
    echo "in transition ($STATE). re-run in a moment."
    exit 1
    ;;
  *)
    echo "unexpected state: $STATE" >&2
    exit 1
    ;;
esac

echo
echo "public IP : $PUBLIC_IP"
echo "tailnet   : $HOSTNAME (give it ~30s to come online)"
echo
echo "use as exit node:"
echo "  tailscale set --exit-node=$HOSTNAME --exit-node-allow-lan-access=true"
