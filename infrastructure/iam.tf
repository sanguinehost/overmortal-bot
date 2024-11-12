resource "aws_iam_role_policy" "secrets_policy" {
  name = "secrets-policy"
  role = aws_iam_role.bot_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.discord_secrets.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "ssm_policy" {
  name = "ssm-policy"
  role = aws_iam_role.bot_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"
        ]
        Resource = [
          aws_ssm_parameter.cloudwatch_config.arn
        ]
      }
    ]
  })
} 