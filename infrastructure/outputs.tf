output "instance_ip" {
  description = "Public IP of the Discord bot EC2 instance"
  value       = aws_instance.discord_bot.public_ip
}

output "cloudwatch_log_group" {
  description = "CloudWatch Log Group name"
  value       = aws_cloudwatch_log_group.discord_bot.name
} 