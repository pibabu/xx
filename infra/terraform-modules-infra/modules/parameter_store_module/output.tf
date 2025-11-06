output "parameter_store_name" {
  value = aws_ssm_parameter.secure_parameter.name
} 

output "openai_api_key_parameter_name" {
  value = aws_ssm_parameter.openai_api_key.name
}

output "openai_api_key_parameter_arn" {
  value       = aws_ssm_parameter.openai_api_key.arn
}