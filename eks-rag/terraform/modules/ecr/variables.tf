variable "repository_name" {
  description = "ECR repository name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "image_tag_mutability" {
  description = "Image tag mutability setting"
  type        = string
  default     = "MUTABLE"
}

variable "max_image_count" {
  description = "Maximum number of images to keep"
  type        = number
  default     = 10
}
