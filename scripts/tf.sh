#!/usr/bin/env bash
# Wrapper that loads ../.env, maps lowercase keys to TF_VAR_* and runs terraform.
#
# Usage:
#   ./scripts/tf.sh init
#   ./scripts/tf.sh plan
#   ./scripts/tf.sh apply
#   ./scripts/tf.sh destroy
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
TF_DIR="${ROOT_DIR}/terraform"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env not found at $ENV_FILE" >&2
  exit 1
fi

# Load .env (KEY=value lines) without exporting them globally to children that
# don't need them.
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

# Map .env keys (lowercase) -> TF_VAR_* env vars Terraform expects.
: "${tailscale_authkey:?tailscale_authkey is not set in .env}"
export TF_VAR_tailscale_authkey="$tailscale_authkey"

# Bridge AWS CLI v2 `aws login` (Builder ID / root) credentials into env vars
# that the Go SDK / Terraform AWS provider can read.
# `aws configure export-credentials --format env` emits `export VAR=...` lines.
if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
  if creds="$(aws configure export-credentials --format env 2>/dev/null)"; then
    eval "$creds"
  else
    echo "WARN: aws configure export-credentials failed. Make sure 'aws login' session is valid." >&2
  fi
fi

cd "$TF_DIR"
exec terraform "$@"
