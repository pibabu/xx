data "aws_instance" "existing_ec2" {
  # Option 1: Find by instance ID
  instance_id = "i-08398c0c49763792d" 
  
  # Option 2: Find by tag (comment out instance_id above if using this)
  # filter {
  #   name   = "tag:Name"
  #   values = ["production_instance"]
  # }
}

# Fetch existing security group
data "aws_security_group" "existing_sg" {
  # Option 1: By ID
  id = "sg-0323eb49744458416"  # Replace with your SG ID
  
  # Option 2: By name
  # filter {
  #   name   = "group-name"
  #   values = ["ec2-security-group"]
  # }
}

# Fetch existing IAM role
data "aws_iam_role" "existing_role" {
  name = "EC2-deploy-pipeline-role"  # Replace with your role name
}




output "fetched_instance_info" {
  description = "Details of existing EC2 instance"
  value = {
    instance_id       = data.aws_instance.existing_ec2.id
    instance_type     = data.aws_instance.existing_ec2.instance_type
    ami               = data.aws_instance.existing_ec2.ami
    availability_zone = data.aws_instance.existing_ec2.availability_zone
    public_ip         = data.aws_instance.existing_ec2.public_ip
    private_ip        = data.aws_instance.existing_ec2.private_ip
    subnet_id         = data.aws_instance.existing_ec2.subnet_id
    vpc_id            = data.aws_instance.existing_ec2.vpc_security_group_ids
    key_name          = data.aws_instance.existing_ec2.key_name
    iam_role          = data.aws_instance.existing_ec2.iam_instance_profile
    tags              = data.aws_instance.existing_ec2.tags
  }
}

output "fetched_security_group_info" {
  description = "Security group rules"
  value = {
    id          = data.aws_security_group.existing_sg.id
    name        = data.aws_security_group.existing_sg.name
    description = data.aws_security_group.existing_sg.description
  }
}

output "fetched_iam_role_info" {
  description = "IAM role details"
  value = {
    name = data.aws_iam_role.existing_role.name
    arn  = data.aws_iam_role.existing_role.arn
  }
}

