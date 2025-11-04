variable "tags" {
  type    = map(string)
  default = {}
}

variable "instance_name" {
  type        = string
  description = "Instance name that is included in deployment group"
}

variable "s3BucketNameForArtifacts" {
  type        = string
  description = "S3 bucket to store the source code artifacts"
}

variable "FullRepositoryId" {
  type        = string
  description = "Repository used in code pipeline"
}

variable "BranchName" {
  type        = string
  description = "Select branch from repository "
}


# aws code connect to github repo
variable "CodeStarConnectionArn" {  
  type        = string
  description = "Existing connection of github/bitbucket with AWS Coestart"
}