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
  config_path    = "~/.kube/config"
  config_context = "kind-atlantis-demo"
}

# Call the environment module with prod-specific parameters
module "environment" {
  source = "../modules/environment"

  environment = "prod"
  namespace   = "system-alpha"

  # Prod configuration - larger resources
  replica_count  = 3
  log_level      = "info"
  cpu_request    = "4"
  memory_request = "8Gi"
  cpu_limit      = "8"
  memory_limit   = "16Gi"
  max_pods       = 20
}
