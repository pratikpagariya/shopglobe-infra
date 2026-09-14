###############################################################################
# RDS Module — variables.tf
###############################################################################

variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "identifier" {
  description = "Short name appended to the resource name prefix (e.g. 'postgres', 'mysql')"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the DB subnet group (should be private)"
  type        = list(string)
}

variable "engine" {
  description = "Database engine (e.g. postgres, mysql)"
  type        = string
  default     = "postgres"
}

variable "engine_version" {
  type    = string
  default = "17.10"
}

variable "instance_class" {
  type    = string
  default = "db.t3.medium"
}

variable "parameter_group_family" {
  description = "DB parameter group family (e.g. postgres17)"
  type        = string
  default     = "postgres17"
}

variable "db_parameters" {
  description = "List of DB parameter overrides"
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default = []
}

variable "option_group_name" {
  type    = string
  default = null
}

# Storage
variable "allocated_storage" {
  type    = number
  default = 20
}

variable "max_allocated_storage" {
  description = "Upper limit for storage autoscaling (0 = disabled)"
  type        = number
  default     = 100
}

variable "storage_type" {
  type    = string
  default = "gp3"
}

variable "storage_encrypted" {
  type    = bool
  default = true
}

variable "kms_key_arn" {
  type    = string
  default = null
}

# Database credentials
variable "db_name" {
  type = string
}

variable "db_username" {
  type = string
}

variable "db_password" {
  description = "Master password — use Secrets Manager in production; pass via TF_VAR"
  type        = string
  sensitive   = true
}

variable "db_port" {
  type    = number
  default = 5432
}

# Network access
variable "allowed_security_group_ids" {
  description = "Security group IDs allowed to connect to RDS"
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks" {
  type    = list(string)
  default = []
}

# HA
variable "multi_az" {
  type    = bool
  default = true
}

# Backups
variable "backup_retention_period" {
  type    = number
  default = 7
}

variable "backup_window" {
  type    = string
  default = "03:00-04:00"
}

variable "maintenance_window" {
  type    = string
  default = "Mon:04:00-Mon:05:00"
}

variable "delete_automated_backups" {
  type    = bool
  default = true
}

variable "skip_final_snapshot" {
  type    = bool
  default = false
}

# Monitoring
variable "monitoring_interval" {
  description = "Enhanced monitoring interval in seconds (0 = disabled)"
  type        = number
  default     = 60
}

variable "cloudwatch_logs_exports" {
  type    = list(string)
  default = ["postgresql", "upgrade"]
}

# Updates
variable "auto_minor_version_upgrade" {
  type    = bool
  default = true
}

variable "apply_immediately" {
  type    = bool
  default = false
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "performance_insights_enabled" {
  type    = bool
  default = true
}

variable "performance_insights_retention_period" {
  type    = number
  default = 7
}

variable "tags" {
  type    = map(string)
  default = {}
}
