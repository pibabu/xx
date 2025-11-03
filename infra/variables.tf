variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"  
}

variable "app_name" {
  description = "Application name"
  type        = string
  default     = "fastapi-app"
}

variable "environment" {
  type    = string
  default = "production"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"  # free tier
}

variable "ssh_key_name" {
  description = "EC2 SSH key pair name"
  type        = string
}

variable "github_repo" {
  description = "GitHub repo (owner/repo)"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR blocks allowed to SSH"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # recherchiere
}