provider "aws" {
  region = "ap-southeast-1"  # Singapore region (closest to GMT+7)
}

# Use SSM Parameter Store to get the latest AL2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
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
              dnf install -y python3 python3-pip git amazon-cloudwatch-agent

              # Application setup
              cd /opt
              git clone https://github.com/sanguinehost/overmortal-bot
              cd overmortal-bot

              # Set proper ownership and permissions
              chown -R ec2-user:ec2-user /opt/overmortal-bot
              chmod 755 /opt/overmortal-bot

              # Create and configure venv
              python3 -m venv /opt/overmortal-bot/venv
              chown -R ec2-user:ec2-user /opt/overmortal-bot/venv

              # Create log directory with proper permissions
              mkdir -p /opt/overmortal-bot/logs
              chown -R ec2-user:ec2-user /opt/overmortal-bot/logs
              chmod 755 /opt/overmortal-bot/logs

              # Install dependencies in venv
              sudo -u ec2-user /opt/overmortal-bot/venv/bin/pip install -r requirements.txt

              # CloudWatch setup
              /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c ssm:/AmazonCloudWatch/Config

              # Create service file
              cat > /etc/systemd/system/discord-bot.service <<EOL
              [Unit]
              Description=Discord Bot Service
              After=network.target

              [Service]
              Type=simple
              User=ec2-user
              Group=ec2-user
              WorkingDirectory=/opt/overmortal-bot
              ExecStart=/opt/overmortal-bot/venv/bin/python src/bot.py
              StandardOutput=append:/opt/overmortal-bot/logs/bot.log
              StandardError=append:/opt/overmortal-bot/logs/bot.log
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

  subnet_id = aws_subnet.bot_subnet.id

  # Add IMDSv2 requirement
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"  # Require IMDSv2
  }

  # Add root volume encryption
  root_block_device {
    encrypted = true
  }

  vpc_security_group_ids = [aws_security_group.discord_bot.id]
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
  vpc_id      = aws_vpc.bot_vpc.id

  # No inbound access needed except for SSM
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS inbound for SSM"
  }

  # Egress rules
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS outbound (CloudWatch, SSM, Discord API)"
  }

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP outbound (package installation)"
  }

  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "DNS (UDP)"
  }

  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "DNS (TCP)"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["3.0.5.32/29"]  # EC2 Instance Connect IP range for ap-southeast-1
    description = "EC2 Instance Connect"
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["3.0.5.32/29"]  # EC2 Instance Connect
    description = "EC2 Instance Connect HTTPS"
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["${aws_vpc.bot_vpc.cidr_block}"]  # Internal VPC CIDR
    description = "VPC Internal HTTPS"
  }

  tags = {
    Name = "sanguine-overmortal-bot-sg"
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

# VPC Configuration
resource "aws_vpc" "bot_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "sanguine-overmortal-bot-vpc"
  }
}

# Public Subnet (for outbound internet access)
resource "aws_subnet" "bot_subnet" {
  vpc_id                  = aws_vpc.bot_vpc.id
  cidr_block             = "10.0.1.0/24"
  availability_zone      = "ap-southeast-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "sanguine-overmortal-bot-subnet"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "bot_igw" {
  vpc_id = aws_vpc.bot_vpc.id

  tags = {
    Name = "sanguine-overmortal-bot-igw"
  }
}

# Route Table
resource "aws_route_table" "bot_rt" {
  vpc_id = aws_vpc.bot_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.bot_igw.id
  }

  tags = {
    Name = "sanguine-overmortal-bot-rt"
  }
}

resource "aws_route_table_association" "bot_rta" {
  subnet_id      = aws_subnet.bot_subnet.id
  route_table_id = aws_route_table.bot_rt.id
}

resource "aws_cloudwatch_log_group" "discord_bot" {
  name              = "/sanguine-overmortal/discord-bot"
  retention_in_days = 14

  tags = {
    Name = "sanguine-overmortal-bot-logs"
  }
}

# SSM VPC Endpoints
resource "aws_vpc_endpoint" "ssm" {
  vpc_id            = aws_vpc.bot_vpc.id
  service_name      = "com.amazonaws.ap-southeast-1.ssm"
  vpc_endpoint_type = "Interface"

  security_group_ids = [aws_security_group.discord_bot.id]
  subnet_ids         = [aws_subnet.bot_subnet.id]

  private_dns_enabled = true

  tags = {
    Name = "sanguine-overmortal-ssm-endpoint"
  }
}

resource "aws_vpc_endpoint" "ssm_messages" {
  vpc_id            = aws_vpc.bot_vpc.id
  service_name      = "com.amazonaws.ap-southeast-1.ssmmessages"
  vpc_endpoint_type = "Interface"

  security_group_ids = [aws_security_group.discord_bot.id]
  subnet_ids         = [aws_subnet.bot_subnet.id]

  private_dns_enabled = true

  tags = {
    Name = "sanguine-overmortal-ssm-messages-endpoint"
  }
}

resource "aws_vpc_endpoint" "ec2_messages" {
  vpc_id            = aws_vpc.bot_vpc.id
  service_name      = "com.amazonaws.ap-southeast-1.ec2messages"
  vpc_endpoint_type = "Interface"

  security_group_ids = [aws_security_group.discord_bot.id]
  subnet_ids         = [aws_subnet.bot_subnet.id]

  private_dns_enabled = true

  tags = {
    Name = "sanguine-overmortal-ec2-messages-endpoint"
  }
}

resource "aws_vpc_endpoint" "cloudwatch_logs" {
  vpc_id            = aws_vpc.bot_vpc.id
  service_name      = "com.amazonaws.ap-southeast-1.logs"
  vpc_endpoint_type = "Interface"

  security_group_ids = [aws_security_group.discord_bot.id]
  subnet_ids         = [aws_subnet.bot_subnet.id]

  private_dns_enabled = true

  tags = {
    Name = "sanguine-overmortal-cloudwatch-logs-endpoint"
  }
} 