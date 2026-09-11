variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "owner" {
  type    = string
  default = "pratik"
}

variable "vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "app_instance_type" {
  type    = string
  default = "t3.small"
  validation {
    condition = contains(
      ["t3.micro", "t3.small", "c7i-flex.large", "m7i-flex.large"],
      var.app_instance_type
    )
    error_message = "Not available in this account. Use t3.micro, t3.small, c7i-flex.large or m7i-flex.large."
  }
}

variable "mon_instance_type" {
  type    = string
  default = "t3.small"
  validation {
    condition = contains(
      ["t3.small", "c7i-flex.large", "m7i-flex.large"],
      var.mon_instance_type
    )
    error_message = "Prometheus + Grafana need at least 2 GiB. t3.micro will be OOM-killed."
  }
}

variable "cpu_credits" {
  type        = string
  default     = "unlimited"
  description = <<-EOT
    t3 burstable credit mode. "standard" throttles to 20% baseline once credits
    run out, which silently caps your load test and gives a FALSE capacity
    number. "unlimited" pays a few cents instead. Ignored on non-t3 types.
  EOT
  validation {
    condition     = contains(["standard", "unlimited"], var.cpu_credits)
    error_message = "cpu_credits must be standard or unlimited."
  }
}

variable "asg_min" {
  type    = number
  default = 2
}

variable "asg_max" {
  type    = number
  default = 4
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "artifact_bucket" {
  type        = string
  description = "S3 bucket holding the app tarball, created by scripts/build-artifact.sh"
}
