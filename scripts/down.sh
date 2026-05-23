#!/usr/bin/env bash
# Stop the EC2 exit node (no compute charge while stopped).
# EBS and EIP keep their hourly charge.
#
# Usage: ./scripts/down.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF="${ROOT_DIR}/scripts/tf.sh"

INSTANCE_ID="$("$TF" output -raw instance_id)"
REGION="$("$TF" output -raw aws_region 2>/dev/null || echo "ap-northeast-1")"

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

echo
echo "tip: on your client, clear the exit node so traffic doesn't black-hole:"
echo "  tailscale set --exit-node="
