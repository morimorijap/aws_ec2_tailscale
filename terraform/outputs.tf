output "instance_id" {
  description = "EC2 instance ID of the exit node"
  value       = aws_instance.exit_node.id
}

output "aws_region" {
  description = "AWS region the exit node lives in"
  value       = var.aws_region
}

output "public_ip" {
  description = "Fixed public IP (Elastic IP) — the pseudo-static IP your traffic will exit from"
  value       = aws_eip.exit_node.public_ip
}

output "tailscale_hostname" {
  description = "Hostname registered in your tailnet"
  value       = var.tailscale_hostname
}

output "ssh_via_tailscale" {
  description = "SSH command via Tailscale SSH (no public port open)"
  value       = "tailscale ssh ec2-user@${var.tailscale_hostname}"
}

output "ssm_session_command" {
  description = "Emergency console via SSM Session Manager"
  value       = "aws ssm start-session --target ${aws_instance.exit_node.id} --region ${var.aws_region}"
}

output "approve_exit_node_url" {
  description = "Open this to approve / enable the exit node in the admin console"
  value       = "https://login.tailscale.com/admin/machines"
}
