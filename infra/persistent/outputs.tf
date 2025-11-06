output "eip_allocation_id" {
  value = aws_eip.static_ip.id
}

output "eip_public_ip" {
  value = aws_eip.static_ip.public_ip
}
