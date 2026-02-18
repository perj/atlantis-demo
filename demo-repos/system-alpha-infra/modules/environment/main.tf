terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }
  required_version = ">= 1.14"
}

# ConfigMap for application configuration
resource "kubernetes_config_map" "app_config" {
  metadata {
    name      = "${var.environment}-app-config"
    namespace = var.namespace
    labels = {
      environment = var.environment
      managed-by  = "terraform"
    }
  }

  data = {
    app_name      = "system-alpha-app"
    environment   = var.environment
    replica_count = tostring(var.replica_count)
    log_level     = var.log_level
  }
}

# Secret for application credentials
resource "kubernetes_secret" "app_secret" {
  metadata {
    name      = "${var.environment}-app-secret"
    namespace = var.namespace
    labels = {
      environment = var.environment
      managed-by  = "terraform"
    }
  }

  type = "Opaque"

  data = {
    api_key     = base64encode("${var.environment}-api-key-placeholder")
    db_password = base64encode("${var.environment}-db-pass-placeholder")
  }
}

# ServiceAccount for the application
resource "kubernetes_service_account" "app_sa" {
  metadata {
    name      = "${var.environment}-app-sa"
    namespace = var.namespace
    labels = {
      environment = var.environment
      managed-by  = "terraform"
    }
  }
}

# Role with read-only permissions
resource "kubernetes_role" "app_role" {
  metadata {
    name      = "${var.environment}-app-role"
    namespace = var.namespace
    labels = {
      environment = var.environment
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
    name      = "${var.environment}-app-role-binding"
    namespace = var.namespace
    labels = {
      environment = var.environment
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
    namespace = var.namespace
  }
}

# Resource Quota for the environment
resource "kubernetes_resource_quota" "env_quota" {
  metadata {
    name      = "${var.environment}-quota"
    namespace = var.namespace
    labels = {
      environment = var.environment
      managed-by  = "terraform"
    }
  }

  spec {
    hard = {
      "requests.cpu"    = var.cpu_request
      "requests.memory" = var.memory_request
      "limits.cpu"      = var.cpu_limit
      "limits.memory"   = var.memory_limit
      "pods"            = tostring(var.max_pods)
    }
  }
}

# Network Policy - allow ingress from same namespace
resource "kubernetes_network_policy" "app_netpol" {
  metadata {
    name      = "${var.environment}-app-netpol"
    namespace = var.namespace
    labels = {
      environment = var.environment
      managed-by  = "terraform"
    }
  }

  spec {
    pod_selector {
      match_labels = {
        environment = var.environment
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
