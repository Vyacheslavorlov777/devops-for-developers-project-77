output "deploy_trigger_hash" {
  description = "Hash of inputs that triggers ansible deploy"
  value       = local.config_hash
  sensitive   = true
}

output "application_url" {
  description = "Application URL via load balancer domain"
  value       = "https://${var.redmine_domain}"
}

