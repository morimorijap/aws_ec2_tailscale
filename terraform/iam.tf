data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "exit_node" {
  name               = "${var.project_name}-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

# Least-privilege: read only the one SecureString parameter.
data "aws_iam_policy_document" "ssm_read_authkey" {
  statement {
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]
    resources = [aws_ssm_parameter.tailscale_authkey.arn]
  }
}

resource "aws_iam_role_policy" "ssm_read_authkey" {
  name   = "${var.project_name}-ssm-read"
  role   = aws_iam_role.exit_node.id
  policy = data.aws_iam_policy_document.ssm_read_authkey.json
}

# Optional: SSM Session Manager as emergency console (no port 22 needed).
resource "aws_iam_role_policy_attachment" "ssm_managed_core" {
  count      = var.allow_ssm_session ? 1 : 0
  role       = aws_iam_role.exit_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "exit_node" {
  name = "${var.project_name}-profile"
  role = aws_iam_role.exit_node.name
}
