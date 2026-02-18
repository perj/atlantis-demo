output "config_map_name" {
  description = "Name of the created ConfigMap"
  value       = kubernetes_config_map.app_config.metadata[0].name
}

output "secret_name" {
  description = "Name of the created Secret"
  value       = kubernetes_secret.app_secret.metadata[0].name
}

output "service_account_name" {
  description = "Name of the created ServiceAccount"
  value       = kubernetes_service_account.app_sa.metadata[0].name
}
