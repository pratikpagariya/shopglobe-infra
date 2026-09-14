###############################################################################
# ECR Module — variables.tf
###############################################################################

variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "repositories" {
  description = "Map of ECR repository configurations"
  type = map(object({
    image_tag_mutability = optional(string, "MUTABLE")
    scan_on_push         = optional(bool, true)
    encryption_type      = optional(string, null) # AES256 or KMS
    kms_key_arn          = optional(string, null)
    force_delete         = optional(bool, false)
    lifecycle_policy     = optional(string, null) # JSON string; null = use default
    repository_policy    = optional(string, null) # JSON string; null = skip
  }))
}

variable "apply_default_lifecycle_policy" {
  description = "Apply a default lifecycle policy to repos without an explicit one"
  type        = bool
  default     = true
}

variable "default_untagged_image_count" {
  description = "Number of untagged images to retain in the default lifecycle policy"
  type        = number
  default     = 3
}

variable "default_tagged_image_count" {
  description = "Number of tagged images to retain in the default lifecycle policy"
  type        = number
  default     = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}
