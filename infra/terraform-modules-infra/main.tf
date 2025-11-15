provider "aws" {
  region = var.aws_region
}

locals {
  common_tags = {
    Project_Name = var.project_name
    Environment  = var.environment
    Account_ID   = var.account_id
    Region       = var.aws_region
  }
}

module "vpc" {
  source = "./module/vpc"
  
  vpc_cidr             = var.vpc_cidr
  availability_zone    = var.availability_zone
  tags                 = local.common_tags
}

data "terraform_remote_state" "persistent" {
  backend = "local"  
  config = {
    path = "../persistent/terraform.tfstate"
  }
}

module "ec2_instance_module" {
  source                        = "./module/ec2_instance_module"
  vpc_id                        = module.vpc.vpc_id
  subnet_id                     = module.vpc.public_subnet_id
  ami                           = "ami-0a5b0d219e493191b"
  instance_type                 = "t3.micro"
  instance_name                 = "fastapi"
  codepipeline_s3_bucket        = var.codepipeline_s3_bucket  ## ??
  tags                          = local.common_tags
}

# resource "aws_eip" "static_ip" {
#   domain = "vpc"
#   tags   = local.common_tags
  
#   # lifecycle {
#   #   prevent_destroy = true
#   # }
# }


#  !!
# resource "aws_eip_association" "eip_assoc" {
#   instance_id   = module.ec2_instance_module.instance_id
#   allocation_id = data.terraform_remote_state.persistent.outputs.eip_allocation_id
# }

