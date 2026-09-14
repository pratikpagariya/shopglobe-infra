###############################################################################
# Secrets Manager Module — variables.tf
###############################################################################

variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "kms_key_id" {
  description = "KMS key ID/ARN for encrypting secrets (null = AWS-managed key)"
  type        = string
  default     = null
}

variable "secrets" {
  description = "Map of secrets to create in AWS Secrets Manager"
  type = map(object({
    description             = optional(string, "")
    generate                = optional(bool, false) # generate a random password
    length                  = optional(number, 24)
    special                 = optional(bool, true)
    username                = optional(string) # if set with generate, stores {username,password}
    secret_string           = optional(string) # explicit value (plain or JSON); wins over generate
    recovery_window_in_days = optional(number, 7)
  }))
  default = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
