# ----------------------------------------------------------------
# ----------------- AWS CODE PIPELINE VARIABLES ------------------
# ----------------------------------------------------------------

# #https://us-east-1.console.aws.amazon.com/ec2/home?region=us-east-1#AMICatalog:
# variable "ami_ssm_parameter" {
#   description = "SSM parameter name for the AMI ID. For Amazon Linux AMI SSM parameters see [reference](https://docs.aws.amazon.com/systems-manager/latest/userguide/parameter-store-public-parameters-ami.html)"
#   type        = string
#   default     = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2" 
# } 

variable "ec2_role_permissions" { 
  type        = list(string)
  description = "List of permissions to attach to the EC2 role"
  default = [
    "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess",
    "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/AmazonSSMManagedEC2InstanceDefaultPolicy",
  ]
}

variable "ssh_allowed_ip" {
  type        = string
  description = "IP address allowed for SSH (e.g., '1.2.3.4/32')"
  validation {
    condition     = var.ssh_allowed_ip != "0.0.0.0/0"
    error_message = "SSH port must be specified and cannot be 0"
  }
}

variable "security_group_allowed_ports" {
  type        = list(number)
  description = "List of ports to allow in the security group"
  default     = [80, 443]
}

variable "instance_name" {
  description = "Name of the instance so that we can use this instance in deployment group in code pipeline"
  default     = "fastapi"     ## deploy zu EC2 mit Tag fastapi
}

variable "ami" {
  description = "AMI ID for the EC2 instance " 
}

variable "instance_type" {
  description = "Instance type for the EC2 instance"
}


variable "tags" {
  type    = map(string)
  default = {}
}