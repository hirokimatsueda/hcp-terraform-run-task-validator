output "function_url" {
  description = "Lambda function URL for Run Task"
  value       = aws_lambda_function_url.run_task.function_url
}

output "hmac_secret_key" {
  description = "Generated HMAC secret key"
  value       = random_password.hmac_key.result
  sensitive   = true
}
