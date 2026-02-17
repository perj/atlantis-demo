output "atlantis_namespace" {
  description = "Name of the Kubernetes namespace for Atlantis servers"
  value       = kubernetes_namespace_v1.atlantis.metadata[0].name
}

output "atlantis_bot_username" {
  description = "Username of the GitLab Atlantis bot user"
  value       = gitlab_user.atlantis_bot.username
}

output "atlantis_bot_user_id" {
  description = "User ID of the GitLab Atlantis bot"
  value       = gitlab_user.atlantis_bot.id
}

output "atlantis_bot_token" {
  description = "Personal access token for atlantis-bot (sensitive)"
  value       = gitlab_personal_access_token.atlantis_bot.token
  sensitive   = true
}

output "gitlab_credentials_secret" {
  description = "Name of the Kubernetes secret containing GitLab credentials"
  value       = kubernetes_secret_v1.gitlab_credentials.metadata[0].name
}
