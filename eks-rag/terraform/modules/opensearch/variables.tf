variable "collection_name" {
  description = "OpenSearch Serverless collection name"
  type        = string
}

variable "iam_role_arn" {
  description = "IAM role ARN for data access policy"
  type        = string
}

variable "allow_public_access" {
  description = "Allow public access to the collection"
  type        = bool
  default     = true
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "additional_principals" {
  description = "Additional IAM principals (users/roles) to grant OpenSearch access for local development"
  type        = list(string)
  default     = []
}
