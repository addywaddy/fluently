output "app_ip" {
  description = "Set FLUENTLY_SERVER to this IPv4 address and point the app domain's A record here."
  value       = hcloud_server.app.ipv4_address
}

output "backup_bucket_name" {
  description = "Set LITESTREAM_BUCKET to this bucket name."
  value       = minio_s3_bucket.backups.bucket
}

output "backup_endpoint" {
  value = "https://nbg1.your-objectstorage.com"
}
