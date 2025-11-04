variable "aws_region" {
  type        = string
  description = "AWS region where resources will be provisioned"
  default     = "eu-central-1" 
}

# ----------------------------------------------------------------
# ---------------------- AWS Resource Tags -----------------------
# ----------------------------------------------------------------


variable "ssh_allowed_ip" {
  type    = string
  default = "88.72.142.87/32"
}



# ----------------------------------------------------------------
# ---------------------- AWS Resource Tags -----------------------
# ----------------------------------------------------------------



variable "project_name" {
  type    = string
  default = "xx"
}

variable "environment" {
  type    = string
  default = "Production"
}

variable "account_id" {
  type    = string
  default = "366101697591"
}



# ----------------------------------------------------------------
# # --------------- AWS PARAMETER STORE VARIABLES ------------------
# # ----------------------------------------------------------------

# variable "parameter_store_name" {
#   type        = string
#   description = "Name of the AWS SSM Parameter Store"
#   default     = "/project/be"
# }

# # ----------------------------------------------------------------
# --------------- AWS CodePipeline VARIABLES ---------------------
# ----------------------------------------------------------------

# variable "FullRepositoryId" {
#   type        = string
#   description = "Repository used in code pipeline"
#   default     = "rafay-tariq/ProjectBackend"
# }

# variable "BranchName" {
#   type        = string
#   description = "Select branch from repository "
#   default     = "main"
# }

# variable "s3BucketNameForArtifacts" {
#   type        = string
#   description = "S3 bucket to store the source code artifacts"
#   default     = "example-artifact-bucket-some-more-me-random-meeeee"
# }

# variable "CodeStarConnectionArn" {
#   type        = string
#   description = "Existing connection of github/bitbucket with AWS Coestart"
#   default     = "arn:aws:codestar-connections:us-east-1:553723657971:connection/99b23235-d2be-482b-b00c-c449716f1cde"
# }
