output "atlantis_url" {
  description = "External URL for this Atlantis instance"
  value       = local.atlantis_url
}

output "webhook_url" {
  description = "Webhook URL for GitLab integration"
  value       = "${local.atlantis_url}/events"
}

output "namespace" {
  description = "Kubernetes namespace where Atlantis is deployed"
  value       = var.namespace
}

output "service_account_name" {
  description = "Name of the Kubernetes ServiceAccount used by this Atlantis instance"
  value       = kubernetes_service_account_v1.atlantis.metadata[0].name
}

output "deployment_name" {
  description = "Name of the Kubernetes Deployment"
  value       = kubernetes_deployment_v1.atlantis.metadata[0].name
}

output "webhook_secret" {
  description = "Generated webhook secret. Configure this in GitLab: Settings > Webhooks > Add webhook, set URL to the webhook_url output and paste this as the Secret Token."
  value       = random_password.webhook_secret.result
  sensitive   = true
}

output "gitlab_webhook_setup" {
  description = "Instructions for configuring the GitLab webhook"
  value       = <<-EOT
    Configure the GitLab webhook for this Atlantis instance:
      1. Retrieve the webhook secret:
         terraform output -raw webhook_secret
      2. In GitLab, go to the repository Settings > Webhooks
      3. Add webhook:
         URL:          ${local.atlantis_url}/events
         Secret Token: (paste the value from step 1)
         Trigger:      Push events, Comments, Merge request events
  EOT
}
