terraform {
  required_version = ">= 1.5.0, < 2.0.0"
  backend "local" {}

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.49"
    }
    minio = {
      source  = "aminueza/minio"
      version = "~> 3.0"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

provider "minio" {
  minio_server   = "nbg1.your-objectstorage.com"
  minio_user     = var.hetzner_s3_access_key
  minio_password = var.hetzner_s3_secret_key
  minio_region   = "nbg1"
  minio_ssl      = true
}

# Reuse an existing public SSH key; never import or manage Chronologs' resources.
data "hcloud_ssh_key" "operator" {
  name = var.ssh_key_name
}

resource "hcloud_firewall" "app" {
  name = "fluently-app"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = var.ssh_source_cidrs
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  labels = { app = "fluently" }
}

resource "hcloud_server" "app" {
  name               = "fluently-app"
  server_type        = var.server_type
  image              = "ubuntu-24.04"
  location           = "nbg1"
  backups            = true
  delete_protection  = true
  rebuild_protection = true
  ssh_keys           = [data.hcloud_ssh_key.operator.id]
  firewall_ids       = [hcloud_firewall.app.id]
  labels             = { app = "fluently" }

  lifecycle {
    prevent_destroy = true
  }
}

resource "minio_s3_bucket" "backups" {
  bucket        = var.backup_bucket_name
  acl           = "private"
  force_destroy = false

  lifecycle {
    prevent_destroy = true
  }
}
