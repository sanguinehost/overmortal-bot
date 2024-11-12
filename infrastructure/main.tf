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

# Launch Template for the bot instance
resource "aws_launch_template" "discord_bot" {
  name_prefix   = "discord-bot-"
  image_id      = data.aws_ami.amazon_linux_2023.id
  instance_type = "t2.micro"

  # Request spot instances
  instance_market_options {
    market_type = "spot"
    spot_options {
      max_price = "0.008" # ~70% of on-demand price
    }
  }

  # Network configuration
  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.discord_bot.id]
  }

  # IAM instance profile
  iam_instance_profile {
    name = aws_iam_instance_profile.bot_profile.name
  }

  # User data
  user_data = base64encode(<<-EOF
              #!/bin/bash
              set -e

              # System updates
              dnf update -y
              dnf install -y python3 python3-pip git amazon-cloudwatch-agent

              # Set AWS Region
              mkdir -p /root/.aws
              cat > /root/.aws/config <<EOL
              [default]
              region = ap-southeast-1
              EOL

              mkdir -p /home/ec2-user/.aws
              cat > /home/ec2-user/.aws/config <<EOL
              [default]
              region = ap-southeast-1
              EOL
              chown -R ec2-user:ec2-user /home/ec2-user/.aws

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
              ExecStart=/opt/overmortal-bot/venv/bin/python src/bot.py --quiet
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
  )

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"  # Require IMDSv2
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      encrypted   = true
      volume_size = 8
      volume_type = "gp3"
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "sanguine-overmortal-bot-server"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "discord_bot" {
  name                = "discord-bot-asg"
  desired_capacity    = 1
  max_size           = 1
  min_size           = 1
  health_check_type  = "EC2"
  health_check_grace_period = 300
  vpc_zone_identifier = [aws_subnet.bot_subnet.id]

  # Use launch template
  launch_template {
    id      = aws_launch_template.discord_bot.id
    version = "$Latest"
  }

  # Ignore changes to desired capacity so manual scaling doesn't conflict with Terraform
  lifecycle {
    ignore_changes = [desired_capacity]
  }

  tag {
    key                 = "Name"
    value              = "sanguine-overmortal-bot-server"
    propagate_at_launch = true
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

  # Allow HTTPS traffic to VPC endpoints
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.bot_vpc.cidr_block]
    description = "HTTPS for VPC endpoints"
  }

  tags = {
    Name = "sanguine-overmortal-bot-sg"
  }
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

# Private Subnet
resource "aws_subnet" "bot_subnet" {
  vpc_id                  = aws_vpc.bot_vpc.id
  cidr_block             = "10.0.1.0/24"
  availability_zone      = "ap-southeast-1a"
  map_public_ip_on_launch = false  # Changed to false for private subnet

  tags = {
    Name = "sanguine-overmortal-bot-private-subnet"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "bot_igw" {
  vpc_id = aws_vpc.bot_vpc.id

  tags = {
    Name = "sanguine-overmortal-bot-igw"
  }
}

# Public subnet route table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.bot_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.bot_igw.id
  }

  tags = {
    Name = "sanguine-overmortal-public-rt"
  }
}

# Route Table
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.bot_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.bot_nat.id
  }

  tags = {
    Name = "sanguine-overmortal-private-rt"
  }
}

# Route table associations
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.bot_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_cloudwatch_log_group" "discord_bot" {
  name              = "/sanguine-overmortal/discord-bot"
  retention_in_days = 3

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

# Add EC2 VPC Endpoint
resource "aws_vpc_endpoint" "ec2" {
  vpc_id              = aws_vpc.bot_vpc.id
  service_name        = "com.amazonaws.ap-southeast-1.ec2"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.discord_bot.id]
  subnet_ids          = [aws_subnet.bot_subnet.id]
  private_dns_enabled = true

  tags = {
    Name = "sanguine-overmortal-ec2-endpoint"
  }
}

# Add S3 VPC Endpoint (Gateway type)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.bot_vpc.id
  service_name      = "com.amazonaws.ap-southeast-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private_rt.id]

  depends_on = [aws_route_table.private_rt]

  tags = {
    Name = "sanguine-overmortal-s3-endpoint"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"
  tags = {
    Name = "sanguine-overmortal-nat-eip"
  }
}

# NAT Gateway
resource "aws_nat_gateway" "bot_nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_subnet.id  # Place NAT Gateway in public subnet

  tags = {
    Name = "sanguine-overmortal-nat"
  }
}

# Public subnet for NAT Gateway
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.bot_vpc.id
  cidr_block             = "10.0.2.0/24"
  availability_zone      = "ap-southeast-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "sanguine-overmortal-public-subnet"
  }
}