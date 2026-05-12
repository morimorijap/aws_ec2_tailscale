variable "aws_region" {
  description = "AWS region to deploy the exit node"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "Name prefix for created resources"
  type        = string
  default     = "tailscale-exit-node"
}

variable "instance_type" {
  description = "EC2 instance type (ARM/Graviton recommended for cost)"
  type        = string
  default     = "t4g.micro"
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GiB"
  type        = number
  default     = 8
}

variable "tailscale_authkey" {
  description = "Tailscale auth key (tskey-auth-...). Pass via TF_VAR_tailscale_authkey env var."
  type        = string
  sensitive   = true
}

variable "tailscale_hostname" {
  description = "Hostname registered in your tailnet"
  type        = string
  default     = "aws-exit-node"
}

variable "allow_ssm_session" {
  description = "Attach AmazonSSMManagedInstanceCore for emergency SSM Session Manager access (no port open needed)"
  type        = bool
  default     = true
}
