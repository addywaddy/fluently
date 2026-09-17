variable "hcloud_token" {
  description = "Hetzner Cloud API token for the target project; set via TF_VAR_hcloud_token."
  type        = string
  sensitive   = true
}

variable "hetzner_s3_access_key" {
  description = "Hetzner Object Storage access key; set via TF_VAR_hetzner_s3_access_key."
  type        = string
  sensitive   = true
}

variable "hetzner_s3_secret_key" {
  description = "Hetzner Object Storage secret key; set via TF_VAR_hetzner_s3_secret_key."
  type        = string
  sensitive   = true
}

variable "ssh_key_name" {
  description = "Existing public SSH key in the target Hetzner project. Defaults to the operator key used by Chronologs."
  type        = string
  default     = "adam@chronologs"
}

variable "ssh_source_cidrs" {
  description = "Allowed SSH source networks. Matches Chronologs by default; restrict to your stable admin/VPN CIDRs when available."
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]

  validation {
    condition     = length(var.ssh_source_cidrs) > 0 && alltrue([for cidr in var.ssh_source_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Provide at least one valid IPv4 or IPv6 CIDR for SSH access."
  }
}

variable "server_type" {
  description = "Hetzner x86 VPS type. If switching to ARM, also set FLUENTLY_ARCH=arm64 for Kamal."
  type        = string
  default     = "cpx22"
}

variable "backup_bucket_name" {
  description = "Globally unique, dedicated Fluently backup bucket in nbg1."
  type        = string
  default     = "fluently-backups"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.backup_bucket_name))
    error_message = "Use 3–63 lowercase letters, digits or hyphens, beginning and ending with a letter or digit."
  }
}
