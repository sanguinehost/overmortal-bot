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
              pip3 install -r /opt/overmortal-bot/requirements.txt

              # CloudWatch setup
              /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c ssm:/AmazonCloudWatch/Config

              # Application setup
              cd /opt
              git clone https://github.com/sanguinehost/overmortal-bot
              cd overmortal-bot

              # Create service file
              cat > /etc/systemd/system/discord-bot.service <<EOL
              [Unit]
              Description=Discord Bot Service
              After=network.target

              [Service]
              Type=simple
              User=root
              WorkingDirectory=/opt/overmortal-bot
              ExecStart=/usr/bin/python3 src/bot.py --quiet
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

  # No inbound access needed since bot only makes outbound connections
  
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS outbound"
  }

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP outbound"
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