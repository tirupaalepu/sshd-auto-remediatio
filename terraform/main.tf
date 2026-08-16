terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "sshd-auto-remediation"
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_iam_role" "ec2_ssm" {
  name = "${var.project_name}-ec2-ssm"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cw_agent" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "${var.project_name}-ec2-ssm"
  role = aws_iam_role.ec2_ssm.name
}

resource "aws_security_group" "target" {
  name        = "${var.project_name}-target"
  description = "Lab target - prefer SSM; SSH optional"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-target"
  }
}

resource "aws_instance" "target" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.micro"
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm.name
  vpc_security_group_ids = [aws_security_group.target.id]

  user_data = <<-EOF
    #!/bin/bash
    set -eux
    dnf install -y amazon-ssm-agent || true
    systemctl enable --now amazon-ssm-agent
    # Publish sshd_up custom metric every minute
    cat >/usr/local/bin/sshd-metric.sh <<'SCRIPT'
    #!/bin/bash
    REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region || echo us-east-1)
    IID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
    if systemctl is-active --quiet sshd || systemctl is-active --quiet ssh; then VAL=1; else VAL=0; fi
    aws cloudwatch put-metric-data --region "$REGION" --namespace SshdLab --metric-name sshd_up --dimensions InstanceId="$IID" --value "$VAL" --unit Count
    SCRIPT
    chmod +x /usr/local/bin/sshd-metric.sh
    echo "* * * * * root /usr/local/bin/sshd-metric.sh" >/etc/cron.d/sshd-metric
  EOF

  tags = {
    Name    = "${var.project_name}-target"
    Role    = "sshd-target"
    Project = var.project_name
  }
}

resource "aws_sns_topic" "sshd_alarms" {
  name = "${var.project_name}-sshd-alarms"
}

resource "aws_cloudwatch_metric_alarm" "sshd_down" {
  alarm_name          = "${var.project_name}-sshd-down"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "sshd_up"
  namespace           = "SshdLab"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  alarm_description   = "sshd is down on target EC2"
  treat_missing_data  = "breaching"
  dimensions = {
    InstanceId = aws_instance.target.id
  }
  alarm_actions = [aws_sns_topic.sshd_alarms.arn]
  ok_actions    = [aws_sns_topic.sshd_alarms.arn]
}

output "target_instance_id" {
  value = aws_instance.target.id
}

output "sns_topic_arn" {
  value = aws_sns_topic.sshd_alarms.arn
}

output "alarm_name" {
  value = aws_cloudwatch_metric_alarm.sshd_down.alarm_name
}
