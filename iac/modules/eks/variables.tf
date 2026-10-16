###############################################################################
# EKS Module — variables.tf
###############################################################################

variable "project" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where EKS will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for EKS nodes and control plane"
  type        = list(string)
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.36"
}

variable "endpoint_private_access" {
  description = "Enable private API endpoint"
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Enable public API endpoint"
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to access the public endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_log_types" {
  description = "EKS cluster log types to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "cluster_encryption_key_arn" {
  description = "KMS key ARN for encrypting Kubernetes secrets (null = disabled)"
  type        = string
  default     = null
}

variable "node_groups" {
  description = "Map of managed node group configurations"
  type = map(object({
    instance_types             = list(string)
    capacity_type              = string # ON_DEMAND or SPOT
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
  default = {}
}

variable "addon_versions" {
  description = "Override addon versions (null = use latest compatible)"
  type        = map(string)
  default     = {}
}

variable "additional_addons" {
  description = "Additional EKS addons beyond the defaults"
  type = map(object({
    addon_version        = optional(string)
    configuration_values = optional(string) # JSON, as the add-on's schema defines it
  }))
  default = {}
}

variable "enable_network_policy" {
  description = "Enforce Kubernetes NetworkPolicy via the VPC CNI's network policy agent. Off, NetworkPolicy objects are accepted by the API server and then silently ignored."
  type        = bool
  default     = false
}

variable "pod_identity_associations" {
  description = "Map of Pod Identity associations (EKS Pod Identity, not IRSA)"
  type = map(object({
    namespace           = string
    service_account     = string
    managed_policy_arns = optional(list(string), [])
    inline_policy       = optional(string)
  }))
  default = {}
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}

variable "authentication_mode" {
  type        = string
  default     = "API"
  description = <<-EOT
    API                = Access Entries only (what you want)
    API_AND_CONFIG_MAP = both, for migrating an existing cluster
    CONFIG_MAP         = legacy aws-auth only
    Migration is one-way: CONFIG_MAP -> API_AND_CONFIG_MAP -> API. You cannot
    go back, which is why you pick API on a new cluster.
  EOT
  validation {
    condition     = contains(["API", "API_AND_CONFIG_MAP", "CONFIG_MAP"], var.authentication_mode)
    error_message = "Must be API, API_AND_CONFIG_MAP or CONFIG_MAP."
  }
}

variable "bootstrap_creator_admin" {
  type        = bool
  default     = true
  description = "Grants cluster-admin to whoever runs apply. Set at CREATION ONLY -- changing it replaces the cluster."
}

variable "access_entries" {
  description = "IAM principal -> Kubernetes RBAC, via the EKS Access Entry API."
  type = map(object({
    principal_arn     = string
    type              = optional(string, "STANDARD")
    kubernetes_groups = optional(list(string), [])
    policies = optional(map(object({
      policy_arn        = string
      access_scope_type = optional(string, "cluster")
      namespaces        = optional(list(string))
    })), {})
  }))
  default = {}
}
