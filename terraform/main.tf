provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}

# --- Networking: reuse default VPC / subnet to avoid extra cost ----------

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# --- AMI: latest Amazon Linux 2023 (arm64) -------------------------------

data "aws_ami" "al2023_arm64" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-arm64"]
  }
  filter {
    name   = "architecture"
    values = ["arm64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# --- Security Group: zero ingress, all egress ----------------------------

resource "aws_security_group" "exit_node" {
  name        = "${var.project_name}-sg"
  description = "No inbound ports. Egress for Tailscale + exit traffic."
  vpc_id      = data.aws_vpc.default.id

  # No ingress rules on purpose — all access goes through Tailscale.

  egress {
    description      = "All outbound IPv4"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    description      = "All outbound IPv6"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${var.project_name}-sg"
  }
}

# --- Elastic IP (fixed public IP) ----------------------------------------

resource "aws_eip" "exit_node" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-eip"
  }
}

resource "aws_eip_association" "exit_node" {
  instance_id   = aws_instance.exit_node.id
  allocation_id = aws_eip.exit_node.id
}

# --- EC2 instance ---------------------------------------------------------

resource "aws_instance" "exit_node" {
  ami                    = data.aws_ami.al2023_arm64.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.exit_node.id]
  iam_instance_profile   = aws_iam_instance_profile.exit_node.name

  # Disable source/dest check so the instance can act as an exit/subnet router.
  source_dest_check = false

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 2
  }

  user_data = templatefile("${path.module}/user_data.sh", {
    ssm_param_name     = aws_ssm_parameter.tailscale_authkey.name
    aws_region         = var.aws_region
    tailscale_hostname = var.tailscale_hostname
  })

  user_data_replace_on_change = true

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = var.project_name
  }
}
