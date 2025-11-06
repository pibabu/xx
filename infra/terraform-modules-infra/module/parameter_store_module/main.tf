resource "aws_ssm_parameter" "openai_api_key" {
  name        = "/fastapi-app/openai-api-key"
  type        = "SecureString"
  value       = var.openai_api_key
  tags        = var.tags
}


### in parameter strore name :  /fastapi-app/openai-api-key  

