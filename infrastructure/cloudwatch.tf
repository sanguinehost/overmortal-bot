resource "aws_ssm_parameter" "cloudwatch_config" {
  name  = "/AmazonCloudWatch/Config"
  type  = "String"
  value = jsonencode({
    agent = {
      run_as_user = "root"
    }
    logs = {
      logs_collected = {
        files = {
          collect_list = [
            {
              file_path = "/var/log/messages"
              log_group_name = "/sanguine-overmortal/system"
              log_stream_name = "{instance_id}"
              timezone = "UTC"
            },
            {
              file_path = "/var/log/cloud-init-output.log"
              log_group_name = "/sanguine-overmortal/cloud-init"
              log_stream_name = "{instance_id}"
              timezone = "UTC"
            },
            {
              file_path = "/var/log/discord-bot.log"
              log_group_name = "/sanguine-overmortal/discord-bot"
              log_stream_name = "{instance_id}"
              timezone = "UTC"
            }
          ]
        }
      }
    }
  })
} 