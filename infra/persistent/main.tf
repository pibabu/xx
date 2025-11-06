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

resource "aws_eip" "static_ip" {
  domain = "vpc"
  tags = {
    Name = "persistent-static-ip"
  }
}

