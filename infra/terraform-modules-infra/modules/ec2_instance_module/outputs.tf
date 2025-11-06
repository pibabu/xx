output "instance_details" {
  value = {
    instance_id   = aws_instance.ec2_instance.id
    instance_name = aws_instance.ec2_instance.tags["Name"]
  }
}
# output "elastic_ip" {
#   value = aws_eip.aws_instance_elastic_ip.public_ip
# } 


output "public_ip" {
  description = "EC2 public IP"
  value       = aws_instance.ec2_instance.public_ip
}

output "private_ip" {
  description = "EC2 private IP"
  value       = aws_instance.ec2_instance.private_ip
}

output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.ec2_instance.id
}
