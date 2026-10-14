variable "project" { type = string }
variable "environment" { type = string }
variable "vpc_id" { type = string }

variable "subnet_ids" {
  type        = list(string)
  description = "The isolated db tier. Redis needs no route out, same as RDS."
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "Pass BOTH the node SG and the EKS-managed cluster SG -- pod traffic leaves with the latter."
}

variable "node_type" {
  type    = string
  default = "cache.t4g.micro"
}

variable "engine_version" {
  type    = string
  default = "7.1"
}

variable "replicas" {
  type        = number
  default     = 0
  description = "Read replicas. 0 = single node, no failover. Cost lever -- see COST.md."

  validation {
    condition     = var.replicas >= 0 && var.replicas <= 5
    error_message = "ElastiCache allows 0-5 replicas per shard."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
