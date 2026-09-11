variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "env" {
  type    = string
  default = "bootstrap"
}

variable "owner" {
  type    = string
  default = "pratik"
}

variable "monthly_budget_usd" {
  type        = number
  default     = 150
  description = "Hard ceiling. Forecast alerts fire before you spend it."
  validation {
    condition     = var.monthly_budget_usd > 0 && var.monthly_budget_usd <= 1000
    error_message = "Budget must be between 1 and 1000 USD."
  }
}

variable "alert_email" {
  type        = string
  description = "Where budget alerts go."
}
