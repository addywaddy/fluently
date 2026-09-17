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

variable "backup_bucket_name" {
  description = "Globally unique, dedicated Fluently backup bucket in nbg1."
  type        = string
  default     = "fluently-backups"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.backup_bucket_name))
    error_message = "Use 3–63 lowercase letters, digits or hyphens, beginning and ending with a letter or digit."
  }
}
