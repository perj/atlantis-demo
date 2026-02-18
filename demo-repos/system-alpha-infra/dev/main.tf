terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }
  required_version = ">= 1.14"
}

provider "kubernetes" {
  config_path = "~/.kube/config"
  config_context = "kind-atlantis-demo"
}

# Call the environment module with dev-specific parameters
module "environment" {
  source = "../modules/environment"

  environment = "dev"
  namespace   = "system-alpha"

  # Dev configuration - smaller resources
  replica_count  = 1
  log_level      = "debug"
  cpu_request    = "2"
  memory_request = "4Gi"
  cpu_limit      = "4"
  memory_limit   = "8Gi"
  max_pods       = 10
}
