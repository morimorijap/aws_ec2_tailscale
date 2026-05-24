#!/usr/bin/env bash
# Stop the EC2 exit node (no compute charge while stopped).
# EBS and EIP keep their hourly charge.
#
# Usage:    ./scripts/down.sh
# Requires: aws CLI, jq, opentofu (or terraform)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF="${ROOT_DIR}/scripts/tf.sh"

# Fetch all terraform outputs in one call (see comment in up.sh).
OUTPUTS_JSON="$("$TF" output -json 2>/dev/null || true)"
if [[ -z "$OUTPUTS_JSON" || "$OUTPUTS_JSON" == "{}" ]]; then
  echo "ERROR: terraform state has no outputs. Run './scripts/tf.sh apply' first." >&2
  exit 1
fi

INSTANCE_ID="$(jq -r '.instance_id.value // empty' <<<"$OUTPUTS_JSON")"
REGION="$(   jq -r '.aws_region.value  // empty' <<<"$OUTPUTS_JSON")"

if [[ -z "$INSTANCE_ID" ]]; then
  echo "ERROR: instance_id not found in terraform state." >&2
  echo "       Run './scripts/tf.sh apply' first (or the instance was destroyed)." >&2
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
  stopped)
    echo "already stopped."
    exit 0
    ;;
  running)
    cat >&2 <<'WARN'

WARNING: about to stop the EC2 instance.
  If your Tailscale client is currently using this node as exit-node,
  the AWS API call below (and the 'wait' that follows) travels through
  this very node and will hang once it stops. Clear it FIRST on the
  client side:

      tailscale set --exit-node=

  Press Ctrl-C in the next 5 seconds to abort, otherwise continuing...

WARN
    sleep 5
    echo "stopping..."
    aws ec2 stop-instances --instance-ids "$INSTANCE_ID" --region "$REGION" >/dev/null
    aws ec2 wait instance-stopped --instance-ids "$INSTANCE_ID" --region "$REGION"
    echo "stopped."
    ;;
  stopping)
    echo "already stopping. waiting..."
    aws ec2 wait instance-stopped --instance-ids "$INSTANCE_ID" --region "$REGION"
    echo "stopped."
    ;;
  pending|shutting-down)
    echo "in transition ($STATE). re-run in a moment."
    exit 1
    ;;
  *)
    echo "unexpected state: $STATE" >&2
    exit 1
    ;;
esac
