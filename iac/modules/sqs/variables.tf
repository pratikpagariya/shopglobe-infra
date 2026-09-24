variable "project" { type = string }
variable "environment" { type = string }
variable "queue_name" { type = string }

variable "visibility_timeout_seconds" {
  type    = number
  default = 30
  validation {
    condition     = var.visibility_timeout_seconds >= 1 && var.visibility_timeout_seconds <= 43200
    error_message = "SQS allows 0-12 hours. Set it to roughly 6x your p99 processing time."
  }
}

variable "retention_seconds" {
  type    = number
  default = 345600 # 4 days
}

variable "dlq_retention_seconds" {
  type    = number
  default = 1209600 # 14 days -- longer than the main queue; you need time to investigate
}

variable "max_receive_count" {
  type    = number
  default = 3
}

variable "alarm_oldest_message_seconds" {
  type    = number
  default = 300
}

variable "tags" {
  type    = map(string)
  default = {}
}
