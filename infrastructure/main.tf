provider "aws" {
  region = "ap-southeast-1"  # Singapore region (closest to GMT+7)
}

# Use SSM Parameter Store to get the latest AL2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-kernel-default-x86_64"]
  }
}

resource "aws_instance" "discord_bot" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t2.micro"

  tags = {
    Name = "sanguine-overmortal-bot-server"
  }

  user_data = <<-EOF
              #!/bin/bash
              set -e

              # System updates
              dnf update -y
              dnf install -y python3 pip git amazon-cloudwatch-agent

              # Python dependencies
              python3 -m pip install --upgrade pip
              pip3 install discord.py pytz boto3 python-dotenv

              # CloudWatch setup
              /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c ssm:/AmazonCloudWatch/Config

              # Application setup
              cd /opt
              git clone https://github.com/sanguinehost/overmortal-bot
              cd your-repo-name

              # Create service file
              cat > /etc/systemd/system/discord-bot.service <<EOL
              [Unit]
              Description=Discord Bot Service
              After=network.target

              [Service]
              Type=simple
              User=ec2-user
              WorkingDirectory=/opt/your-repo-name
              ExecStart=/usr/bin/python3 src/bot.py
              Restart=always
              RestartSec=3

              [Install]
              WantedBy=multi-user.target
              EOL

              # Start service
              systemctl daemon-reload
              systemctl enable discord-bot
              systemctl start discord-bot
              EOF

  iam_instance_profile = aws_iam_instance_profile.bot_profile.name

  lifecycle {
    ignore_changes = [ami]
  }
}

# Add IAM role for CloudWatch monitoring
resource "aws_iam_role" "bot_role" {
  name = "sanguine-overmortal-bot-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "bot_profile" {
  name = "sanguine-overmortal-bot-profile"
  role = aws_iam_role.bot_role.name
}

resource "aws_iam_role_policy_attachment" "cloudwatch_policy" {
  role       = aws_iam_role.bot_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_security_group" "discord_bot" {
  name        = "sanguine-overmortal-bot-sg"
  description = "Security group for Sanguine Overmortal bot"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Add this policy to your bot IAM role
resource "aws_iam_role_policy" "cloudwatch_logs" {
  name = "cloudwatch-logs-policy"
  role = aws_iam_role.bot_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "arn:aws:logs:*:*:log-group:/sanguine-overmortal/discord-bot:*"
        ]
      }
    ]
  })
} 