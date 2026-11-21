output "state_bucket_name" {
  description = "Pass this to `terraform init -backend-config` in infra/ and set it as the TF_STATE_BUCKET repo variable."
  value       = aws_s3_bucket.state.bucket
}
