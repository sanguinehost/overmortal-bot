output "asg_name" {
  description = "Name of the Auto Scaling Group running the Discord bot"
  value       = aws_autoscaling_group.discord_bot.name
}

output "cloudwatch_log_group" {
  description = "CloudWatch Log Group name"
  value       = aws_cloudwatch_log_group.discord_bot.name
} 