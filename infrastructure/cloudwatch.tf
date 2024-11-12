resource "aws_ssm_parameter" "cloudwatch_config" {
  name  = "/AmazonCloudWatch/Config"
  type  = "String"
  value = jsonencode({
    logs = {
      force_flush_interval = 5
      logs_collected = {
        files = {
          collect_list = [
            {
              file_path = "/var/log/messages"
              log_group_name = "/sanguine-overmortal/system"
              log_stream_name = "{instance_id}"
              timezone = "UTC"
            }
          ]
        }
      }
    }
    metrics = {
      metrics_collected = {
        mem = {
          measurement = ["mem_used_percent"]
        }
        swap = {
          measurement = ["swap_used_percent"]
        }
      }
    }
  })
} 