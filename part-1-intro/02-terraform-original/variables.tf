variable "subscription_id" {
  description = "Target Azure subscription ID. Required; no default so you can't accidentally deploy to the wrong tenant. Pass with -var=subscription_id=<id> or set TF_VAR_subscription_id."
  type        = string
}

variable "workload" {
  description = "Workload name (used in resource naming, e.g. tf-demo)."
  type        = string
  default     = "tf-demo"
}

variable "environment" {
  description = "Environment short name."
  type        = string
  default     = "dev"
}

variable "instance" {
  description = "Instance number for the stack. Three digits."
  type        = string
  default     = "002"

  validation {
    condition     = can(regex("^\\d{3}$", var.instance))
    error_message = "instance must be exactly three digits, e.g. \"001\"."
  }
}

variable "location" {
  description = "Azure region. Restricted to the demo's approved set."
  type        = string
  default     = "westeurope"

  validation {
    condition     = contains(["westeurope", "northeurope", "francecentral"], var.location)
    error_message = "location must be one of: westeurope, northeurope, francecentral."
  }
}

variable "db_sku_name" {
  description = "Azure SQL Database SKU name."
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "S0", "S1"], var.db_sku_name)
    error_message = "db_sku_name must be one of: Basic, S0, S1."
  }
}

locals {
  suffix      = "${var.workload}-${var.environment}-${var.instance}"
  db_sku_tier = var.db_sku_name == "Basic" ? "Basic" : "Standard"

  built_in_role_ids = {
    Reader      = "acdd72a7-3385-48ef-bd42-f606fba81ae7"
    Contributor = "b24988ac-6180-42a0-ab88-20f7382dd24c"
    Owner       = "8e3af657-a8ff-443c-a75c-2fe8c4bcb635"
  }
}
