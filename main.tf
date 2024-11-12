terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "ap-southeast-1"  # Singapore region (closest to GMT+7)
}

module "discord_bot" {
  source = "./infrastructure"
  
  # Pass any variables needed by the module
  discord_bot_token    = var.discord_bot_token
  discord_channel_id   = var.discord_channel_id
} 