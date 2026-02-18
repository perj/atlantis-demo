terraform {
  required_version = ">= 1.14"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.8"
    }
  }
}

# Configure Kubernetes provider
# When running locally: uses ~/.kube/config (default)
# When running in Atlantis pod: uses in-cluster config via init container
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "kind-atlantis-demo"
}

module "system_beta_atlantis" {
  source = "../../modules/atlantis-server"

  instance_name = "system-beta"
  repo_allowlist = [
    "gitlab.127.0.0.1.nip.io/system-beta/system-beta-infra",
  ]
  atlantis_host     = "atlantis-beta.127.0.0.1.nip.io"
  target_namespaces = ["system-beta"]
}

# --- Outputs ---

output "atlantis_url" {
  description = "System Beta Atlantis URL"
  value       = module.system_beta_atlantis.atlantis_url
}

output "webhook_url" {
  description = "Webhook URL to configure in GitLab"
  value       = module.system_beta_atlantis.webhook_url
}

output "webhook_secret" {
  description = "Webhook secret to configure in GitLab"
  value       = module.system_beta_atlantis.webhook_secret
  sensitive   = true
}

output "gitlab_webhook_setup" {
  description = "Instructions for configuring the GitLab webhook"
  value       = module.system_beta_atlantis.gitlab_webhook_setup
}
