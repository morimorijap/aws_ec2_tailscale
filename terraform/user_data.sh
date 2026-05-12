#!/bin/bash
# cloud-init / user_data executed as root on first boot.
set -euxo pipefail

# --- System update ------------------------------------------------------
dnf -y update

# --- Enable IP forwarding (required for exit node) ----------------------
cat >/etc/sysctl.d/99-tailscale.conf <<'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sysctl --system

# --- Install Tailscale from the official AL2023 repo --------------------
dnf -y config-manager --add-repo https://pkgs.tailscale.com/stable/amazon-linux/2023/tailscale.repo
dnf -y install tailscale
systemctl enable --now tailscaled

# --- Fetch auth key from SSM Parameter Store ----------------------------
AUTHKEY=$(aws ssm get-parameter \
  --name "${ssm_param_name}" \
  --with-decryption \
  --region "${aws_region}" \
  --query 'Parameter.Value' \
  --output text)

# --- Bring up Tailscale as exit node + Tailscale SSH --------------------
tailscale up \
  --authkey="$AUTHKEY" \
  --hostname="${tailscale_hostname}" \
  --advertise-exit-node \
  --ssh \
  --accept-dns=false

unset AUTHKEY

# --- Automatic security updates -----------------------------------------
dnf -y install dnf-automatic
sed -i 's/^apply_updates = no/apply_updates = yes/' /etc/dnf/automatic.conf || true
systemctl enable --now dnf-automatic.timer
