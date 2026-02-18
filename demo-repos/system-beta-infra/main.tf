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

# Workspace-based environment configuration
locals {
  config = {
    dev = {
      replica_count    = 1
      log_level        = "debug"
      cpu_request      = "1"
      memory_request   = "2Gi"
      cpu_limit        = "2"
      memory_limit     = "4Gi"
      max_pods         = 10
    }
    prod = {
      replica_count    = 3
      log_level        = "info"
      cpu_request      = "2"
      memory_request   = "4Gi"
      cpu_limit        = "4"
      memory_limit     = "8Gi"
      max_pods         = 20
    }
  }[terraform.workspace]

  namespace = "system-beta"
}

# Namespace is assumed to exist (created during system setup)
# This file only manages resources within the namespace

# ConfigMap for application configuration
resource "kubernetes_config_map" "app_config" {
  metadata {
    name      = "${terraform.workspace}-app-config"
    namespace = local.namespace
    labels = {
      environment = terraform.workspace
      managed-by  = "terraform"
    }
  }

  data = {
    app_name      = "system-beta-app"
    environment   = terraform.workspace
    replica_count = local.config.replica_count
    log_level     = local.config.log_level
  }
}

# Secret for application credentials
resource "kubernetes_secret" "app_secret" {
  metadata {
    name      = "${terraform.workspace}-app-secret"
    namespace = local.namespace
    labels = {
      environment = terraform.workspace
      managed-by  = "terraform"
    }
  }

  type = "Opaque"

  data = {
    api_key     = base64encode("${terraform.workspace}-api-key-placeholder")
    db_password = base64encode("${terraform.workspace}-db-pass-placeholder")
  }
}

# ServiceAccount for the application
resource "kubernetes_service_account" "app_sa" {
  metadata {
    name      = "${terraform.workspace}-app-sa"
    namespace = local.namespace
    labels = {
      environment = terraform.workspace
      managed-by  = "terraform"
    }
  }
}

# Role with read-only permissions
resource "kubernetes_role" "app_role" {
  metadata {
    name      = "${terraform.workspace}-app-role"
    namespace = local.namespace
    labels = {
      environment = terraform.workspace
      managed-by  = "terraform"
    }
  }

  rule {
    api_groups = [""]
    resources  = ["configmaps", "secrets"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list"]
  }
}

# RoleBinding to attach role to service account
resource "kubernetes_role_binding" "app_role_binding" {
  metadata {
    name      = "${terraform.workspace}-app-role-binding"
    namespace = local.namespace
    labels = {
      environment = terraform.workspace
      managed-by  = "terraform"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.app_role.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.app_sa.metadata[0].name
    namespace = local.namespace
  }
}

# Resource Quota for the environment
resource "kubernetes_resource_quota" "env_quota" {
  metadata {
    name      = "${terraform.workspace}-quota"
    namespace = local.namespace
    labels = {
      environment = terraform.workspace
      managed-by  = "terraform"
    }
  }

  spec {
    hard = {
      "requests.cpu"    = local.config.cpu_request
      "requests.memory" = local.config.memory_request
      "limits.cpu"      = local.config.cpu_limit
      "limits.memory"   = local.config.memory_limit
      "pods"            = local.config.max_pods
    }
  }
}

# Network Policy - allow ingress from same namespace
resource "kubernetes_network_policy" "app_netpol" {
  metadata {
    name      = "${terraform.workspace}-app-netpol"
    namespace = local.namespace
    labels = {
      environment = terraform.workspace
      managed-by  = "terraform"
    }
  }

  spec {
    pod_selector {
      match_labels = {
        environment = terraform.workspace
      }
    }

    policy_types = ["Ingress", "Egress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = var.namespace
          }
        }
      }
    }

    egress {
      to {
        namespace_selector {}
      }

      ports {
        protocol = "TCP"
        port     = "443"
      }
      ports {
        protocol = "TCP"
        port     = "53"
      }
      ports {
        protocol = "UDP"
        port     = "53"
      }
    }
  }
}
