terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

# static IP

resource "aws_eip" "static_ip" {
  domain = "vpc"
  tags = {
    Name = "persistent-static-ip"
  }
}

# EBS

# resource "aws_ebs_volume" "user_data" {
#   availability_zone = aws_instance.app_server.availability_zone
#   size              = 100  # change
#   type              = "gp3"
#   encrypted         = true
  
#   iops       = 3000
#   throughput = 125  # MB/s

#   tags = {
#     Name = "user-container-storage"
#   }
# }

# resource "aws_volume_attachment" "user_data_attach" {
#   device_name = "/dev/sdf"
#   volume_id   = aws_ebs_volume.user_data.id
#   instance_id = aws_instance.app_server.id
# }