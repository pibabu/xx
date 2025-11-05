
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_id" {
  description = "Public subnet ID"
  value       = module.vpc.public_subnet_id
}

# output "ec2_instance_id" {
#   description = "EC2 instance ID"
#   value       = module.ec2_instance_module.instance_id
# }

output "ec2_public_ip" {
  description = "EC2 public IP address"
  value       = module.ec2_instance_module.public_ip
}

output "ec2_elastic_ip" {
  description = "Elastic IP address"
  value       = module.ec2_instance_module.elastic_ip
}

output "ec2_private_key_pem" {
  description = "Private key for SSH (sensitive)"
  value       = module.ec2_instance_module.private_key_pem
  sensitive   = true
}