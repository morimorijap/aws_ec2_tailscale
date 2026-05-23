#!/usr/bin/env bash
# Start the EC2 exit node and wait until it's running.
#
# Usage: ./scripts/up.sh
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

PUBLIC_IP="$("$TF" output -raw public_ip)"
HOSTNAME="$("$TF" output -raw tailscale_hostname)"

echo
echo "public IP : $PUBLIC_IP"
echo "tailnet   : $HOSTNAME (give it ~30s to come online)"
echo
echo "use as exit node:"
echo "  tailscale set --exit-node=$HOSTNAME --exit-node-allow-lan-access=true"
