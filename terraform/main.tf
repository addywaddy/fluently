terraform {
  required_version = ">= 1.5.0, < 2.0.0"
  backend "local" {}

  required_providers {
    minio = {
      source  = "aminueza/minio"
      version = "~> 3.0"
    }
  }
}

provider "minio" {
  minio_server   = "nbg1.your-objectstorage.com"
  minio_user     = var.hetzner_s3_access_key
  minio_password = var.hetzner_s3_secret_key
  minio_region   = "nbg1"
  minio_ssl      = true
}

resource "minio_s3_bucket" "backups" {
  bucket        = var.backup_bucket_name
  acl           = "private"
  force_destroy = false

  lifecycle {
    prevent_destroy = true
  }
}
