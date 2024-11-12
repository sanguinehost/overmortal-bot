resource "aws_secretsmanager_secret" "discord_secrets" {
  name                    = "/prod/sanguine-overmortal/discord-bot"
  description            = "Discord bot credentials"
  force_overwrite_replica_secret = true
  recovery_window_in_days = 0  # Immediate deletion

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_secretsmanager_secret_version" "discord_secrets_version" {
  secret_id = aws_secretsmanager_secret.discord_secrets.id
  secret_string = jsonencode({
    DISCORD_OVERMORTAL_BOT_TOKEN = var.discord_bot_token
    DISCORD_OVERMORTAL_CHANNEL_ID = var.discord_channel_id
  })
} 