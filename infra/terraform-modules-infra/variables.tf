variable "aws_region" {
  type        = string
  description = "AWS region where resources will be provisioned"
  default     = "eu-central-1" 
}

# ----------------------------------------------------------------
# ---------------------- AWS Resource Tags -----------------------
# ----------------------------------------------------------------


# variable "ssh_allowed_ip" {
#   type    = string
#   default = "88.72.142.87/32"
# }


# ------------------    VPC    -----------------------

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zone" {
  description = "Availability zone"
  type        = string
  default     = "eu-central-1a"
}



# ----------------------------------------------------------------
# ---------------------- AWS Resource Tags -----------------------
# ----------------------------------------------------------------



variable "project_name" {
  type    = string
  default = "xx"
}

variable "environment" {
  type    = string
  default = "Production"
}

variable "account_id" {
  type    = string
  default = "366101697591"
}

variable "codepipeline_s3_bucket" {
  description = "S3 bucket name for CodePipeline artifacts"
  type        = string
  default     = "codepipeline-eu-central-1-fdd7ab796ddd-49eb-9554-347fb077325a"
}

# ----------------------------------------------------------------
# # --------------- AWS PARAMETER STORE VARIABLES ------------------
# # ----------------------------------------------------------------

variable "openai_api_key" {
  type        = string
  description = "Name of the AWS SSM Parameter Store"
  default     = "/project/be"
}
