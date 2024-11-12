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

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.bot_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

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
          "arn:aws:logs:ap-southeast-1:*:log-group:/sanguine-overmortal/discord-bot:*",
          "arn:aws:logs:ap-southeast-1:*:log-group:/sanguine-overmortal/discord-bot:*:*"
        ]
      }
    ]
  })
} 