variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "westeurope"
}

variable "environment" {
  description = "Environment name (dev, stg, prod)"
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project name prefix for all resources"
  type        = string
  default     = "talk"
}

variable "domain" {
  description = "Base domain (DNS zone will be created for <env>.<domain>)"
  type        = string
}

variable "postgres_admin_username" {
  description = "PostgreSQL admin username"
  type        = string
  default     = "talkadmin"
}

variable "postgres_admin_password" {
  description = "PostgreSQL admin password"
  type        = string
  sensitive   = true
}

variable "aks_node_count" {
  description = "Number of nodes in the default AKS node pool"
  type        = number
  default     = 2
}

variable "aks_vm_size" {
  description = "VM size for AKS default node pool"
  type        = string
  default     = "Standard_B4s_v2"
}

variable "aks_kubernetes_version" {
  description = "Kubernetes version for AKS (null = latest stable)"
  type        = string
  default     = null
}

variable "github_repo" {
  description = "GitHub org/repo for the talk app (used for OIDC federation)"
  type        = string
}
