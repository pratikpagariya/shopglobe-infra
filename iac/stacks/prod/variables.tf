variable "region" { type = string }
variable "environment" { type = string }
variable "owner" { type = string }

variable "vpc_cidr" { type = string }
variable "availability_zones" { type = list(string) }
variable "public_subnet_cidrs" { type = list(string) }
variable "private_subnet_cidrs" { type = list(string) }
variable "db_subnet_cidrs" { type = list(string) }

# THE COST LEVERS. Daily driver runs lean; flip these for one full-fidelity
# weekend to prove per-AZ NAT failover, then flip back. See COST.md.
variable "single_nat_gateway" {
  type    = bool
  default = true
}
variable "enable_vpc_endpoints" {
  type    = bool
  default = false
}
variable "enable_flow_logs" {
  type    = bool
  default = false
}
variable "flow_log_retention_days" {
  type    = number
  default = 3
}

variable "cluster_version" { type = string }
variable "node_groups" {
  type = map(object({
    instance_types             = list(string)
    capacity_type              = string
    ami_type                   = optional(string, "AL2023_x86_64_STANDARD")
    disk_size                  = number
    min_size                   = number
    max_size                   = number
    desired_size               = number
    max_unavailable_percentage = optional(number, 33)
    labels                     = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string
    })), [])
  }))
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "rds_multi_az" {
  type    = bool
  default = false # cost lever. true for the one full-fidelity run.
}

variable "admin_role_name" {
  type        = string
  description = "IAM role that gets cluster-admin via an Access Entry."
}
