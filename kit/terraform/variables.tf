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

variable "location" {
  type    = string
  default = "eastus"
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
    { name = "Allow-HTTPS-In", priority = 100, port = "443" },
  ]
}

variable "deploy_vm" {
  type    = bool
  default = true
}

variable "deploy_aks" {
  type    = bool
  default = false
}

variable "ssh_public_key" {
  type      = string
  sensitive = true
}

variable "db_password" {
  type      = string
  sensitive = true
}
