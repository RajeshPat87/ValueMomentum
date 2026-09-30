variable "subscription_id" {
  type = string
}

variable "env" {
  type    = string
  default = "dev"
  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be dev or prod."
  }
}

variable "resource_group_name" {
  description = "Existing RG to deploy into (like main-rg.bicep). Empty = create rg-demo-<env> (like main.bicep)."
  type        = string
  default     = ""
}

variable "location" {
  description = "Used only when this config creates the RG; an existing RG keeps its own location."
  type        = string
  default     = "eastus"
}

variable "subnets" {
  type = map(string)
  default = {
    web = "10.0.1.0/24"
    pe  = "10.0.2.0/24"
    aks = "10.0.4.0/22"
  }
}

variable "nsg_rules" {
  type = list(object({ name = string, priority = number, port = string }))
  default = [
    { name = "Allow-443-In", priority = 100, port = "443" },
  ]
}

variable "vm_size" {
  type    = string
  default = "Standard_B1s"
  validation {
    condition     = contains(["Standard_B1s", "Standard_B2s", "Standard_D2s_v5"], var.vm_size)
    error_message = "vm_size must be Standard_B1s, Standard_B2s or Standard_D2s_v5 (same list as 04-vm.bicep)."
  }
}

variable "deploy_vm" {
  type    = bool
  default = true
}

variable "deploy_aks" {
  type    = bool
  default = false
}

variable "deploy_rbac" {
  description = "Role assignments, custom role and policy assignment. False where the deployer lacks roleAssignments/write."
  type        = bool
  default     = true
}

variable "kv_purge_protection" {
  description = "Permanent once enabled; some policies forbid it."
  type        = bool
  default     = true
}

variable "kv_soft_delete_days" {
  type    = number
  default = 90
  validation {
    condition     = var.kv_soft_delete_days >= 7 && var.kv_soft_delete_days <= 90
    error_message = "kv_soft_delete_days must be 7-90."
  }
}

variable "ssh_public_key" {
  type      = string
  sensitive = true
}

variable "db_password" {
  description = "Optional; stored as secret db-password when set."
  type        = string
  sensitive   = true
  default     = ""
}
