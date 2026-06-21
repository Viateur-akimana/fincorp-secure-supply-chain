output "trail_arn" {
  description = "CloudTrail trail ARN"
  value       = aws_cloudtrail.this.arn
}

output "log_bucket_name" {
  description = "S3 bucket storing CloudTrail logs"
  value       = aws_s3_bucket.cloudtrail.id
}
