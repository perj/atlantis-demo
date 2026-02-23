output "atlantis_url" {
  description = "External URL for this Atlantis instance"
  value       = local.atlantis_url
}

output "webhook_url" {
  description = "Webhook URL to configure in GitLab"
  value       = "${local.atlantis_url}/events"
}

output "webhook_secret" {
  description = "Webhook secret to configure in GitLab"
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
