provider "aws" {
  region = "ap-southeast-1"  # Singapore region (closest to GMT+7)
}

resource "aws_instance" "discord_bot" {
  ami           = "ami-0c55b159cbfafe1f0"  # Amazon Linux 2 AMI ID
  instance_type = "t2.micro"

  tags = {
    Name = "sanguine-overmortal-bot-server"
  }

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y python3 pip git
              pip3 install discord.py pytz boto3 python-dotenv
              
              # Set up CloudWatch agent for monitoring
              yum install -y amazon-cloudwatch-agent
              /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c ssm:/AmazonCloudWatch/Config
              
              # Clone repository and start bot
              git clone YOUR_REPOSITORY_URL
              cd your-repo-name
              python3 src/bot.py
              EOF

  iam_instance_profile = aws_iam_instance_profile.bot_profile.name
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