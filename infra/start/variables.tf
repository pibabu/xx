variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"  
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}