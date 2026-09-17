output "backup_bucket_name" {
  description = "Set LITESTREAM_BUCKET to this bucket name."
  value       = minio_s3_bucket.backups.bucket
}

output "backup_endpoint" {
  value = "https://nbg1.your-objectstorage.com"
}
