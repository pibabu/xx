variable "parameter_store_name" {
  description = "parameter store name"
}

variable "tags" {
  type    = map(string)
  default = {}
}