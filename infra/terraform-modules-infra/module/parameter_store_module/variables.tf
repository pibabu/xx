variable "tags" {
  type    = map(string)
  default = {}
}

variable "openai_api_key" {
  description = "The OpenAI API key"
  type        = string
  sensitive   = true
}
