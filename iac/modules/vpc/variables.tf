###############################################################################
# VPC Module — variables.tf
###############################################################################

variable "project" {
  description = "Project name used in resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones to deploy into"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway (cost saving) instead of one per AZ"
  type        = bool
  default     = false
}

variable "security_groups" {
  description = "Map of security groups to create"
  type = map(object({
    description = string
    ingress_rules = list(object({
      description     = string
      from_port       = number
      to_port         = number
      protocol        = string
      cidr_blocks     = optional(list(string), [])
      security_groups = optional(list(string), [])
      self            = optional(bool, false)
    }))
    egress_rules = list(object({
      description     = string
      from_port       = number
      to_port         = number
      protocol        = string
      cidr_blocks     = optional(list(string), [])
      security_groups = optional(list(string), [])
    }))
  }))
  default = {}
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}

variable "region" {
  type        = string
  description = "Needed to build VPC endpoint service names."
}

variable "db_subnet_cidrs" {
  type        = list(string)
  default     = []
  description = "Isolated tier for RDS and ElastiCache. No route to anywhere."
}

variable "enable_vpc_endpoints" {
  type    = bool
  default = false
}

variable "flow_log_retention_days" {
  type    = number
  default = 7
  validation {
    condition     = var.flow_log_retention_days > 0
    error_message = "Retention must be set. Unset means forever, and forever is billed."
  }
}

variable "enable_flow_logs" {
  type    = bool
  default = false
}
