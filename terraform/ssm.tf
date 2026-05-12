resource "aws_ssm_parameter" "tailscale_authkey" {
  name        = "/${var.project_name}/tailscale_authkey"
  description = "Tailscale auth key consumed by the exit node at boot."
  type        = "SecureString"
  value       = var.tailscale_authkey
  tier        = "Standard" # Standard tier (<=4KB) is free.

  tags = {
    Name = "${var.project_name}-authkey"
  }
}
