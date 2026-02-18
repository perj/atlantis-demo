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

locals {
  labels = {
    app                           = "atlantis-${var.instance_name}"
    instance                      = var.instance_name
    "app.kubernetes.io/name"      = "atlantis"
    "app.kubernetes.io/instance"  = var.instance_name
    "app.kubernetes.io/component" = "server"
  }

  atlantis_url = "http://${var.atlantis_host}"

}

# --- Target Namespaces (for system Atlantis instances) ---

# Creating namespaces here is perhaps "cheating" a bit.
# Normally they'd already be created by some other setup.
# But for this demo we create them here.
resource "kubernetes_namespace_v1" "target" {
  for_each = toset([for ns in var.target_namespaces : ns if ns != var.namespace])

  metadata {
    name = each.value
    labels = {
      name       = each.value
      managed-by = "atlantis-${var.instance_name}"
    }
  }
}

# --- ServiceAccount ---

resource "kubernetes_service_account_v1" "atlantis" {
  metadata {
    name      = "atlantis-${var.instance_name}"
    namespace = var.namespace
    labels    = local.labels
  }
}

resource "kubernetes_role_binding_v1" "atlantis" {
  for_each = toset(var.target_namespaces)

  metadata {
    name      = "atlantis-${var.namespace}-${var.instance_name}"
    namespace = each.value
    labels    = local.labels
  }

  # For the demo, just bind the edit cluster role.
  # For a real setup you might want a custom role with fine grained access.
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "edit"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.atlantis.metadata[0].name
    namespace = var.namespace
  }
}

# --- Secrets ---

resource "random_password" "webhook_secret" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "webhook" {
  metadata {
    name      = "atlantis-${var.instance_name}-webhook"
    namespace = var.namespace
    labels    = local.labels
  }

  data = {
    secret = random_password.webhook_secret.result
  }

  type = "Opaque"
}

# --- ConfigMap: Server-Side Repo Config ---

resource "kubernetes_config_map_v1" "repo_config" {
  count = var.repo_config != null ? 1 : 0

  metadata {
    name      = "atlantis-${var.instance_name}-repo-config"
    namespace = var.namespace
    labels    = local.labels
  }

  data = {
    "repos.yaml" = var.repo_config
  }
}

# --- Deployment ---

resource "kubernetes_deployment_v1" "atlantis" {
  metadata {
    name      = "atlantis-${var.instance_name}"
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "atlantis-${var.instance_name}"
      }
    }

    template {
      metadata {
        labels = local.labels
      }

      spec {
        service_account_name = kubernetes_service_account_v1.atlantis.metadata[0].name

        # Init container: create ~/.kube/config from in-cluster service account
        # Might not be needed in a real setup, it's here to allow
        # the kubernetes provider to work without server urls etc.
        init_container {
          name  = "setup-kubeconfig"
          image = "bitnami/kubectl:latest"

          command = [
            "sh", "-c",
            <<-EOT
            mkdir -p /home/atlantis/.kube
            export KUBECONFIG=/home/atlantis/.kube/config
            kubectl config set-cluster in-cluster \
              --server=https://kubernetes.default.svc \
              --certificate-authority=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
            kubectl config set-credentials atlantis \
              --token=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
            kubectl config set-context kind-atlantis-demo \
              --cluster=in-cluster \
              --user=atlantis
            kubectl config use-context kind-atlantis-demo
            chown atlantis:atlantis /home/atlantis/.kube/config
            chmod 644 /home/atlantis/.kube/config
            EOT
          ]

          volume_mount {
            name       = "atlantis-data"
            mount_path = "/home/atlantis"
          }
        }

        container {
          name    = "atlantis"
          image   = var.atlantis_image
          command = ["atlantis", "server"]

          port {
            name           = "http"
            container_port = 4141
          }

          # Atlantis configuration via ATLANTIS_* env vars
          env {
            name  = "ATLANTIS_ATLANTIS_URL"
            value = local.atlantis_url
          }

          env {
            name  = "ATLANTIS_GITLAB_HOSTNAME"
            value = var.gitlab_hostname
          }

          env {
            name  = "ATLANTIS_GITLAB_USER"
            value = var.gitlab_user
          }

          env {
            name  = "ATLANTIS_REPO_ALLOWLIST"
            value = join(",", var.repo_allowlist)
          }

          dynamic "env" {
            for_each = var.repo_config != null ? [1] : []
            content {
              name  = "ATLANTIS_REPO_CONFIG"
              value = "/etc/atlantis/repos.yaml"
            }
          }

          # Secrets from K8s secret refs
          env {
            name = "ATLANTIS_GITLAB_TOKEN"
            value_from {
              secret_key_ref {
                name = var.gitlab_token_secret
                key  = "token"
              }
            }
          }

          env {
            name = "ATLANTIS_GITLAB_WEBHOOK_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.webhook.metadata[0].name
                key  = "secret"
              }
            }
          }

          # MinIO/S3 credentials for Terraform backend (shared secret from shared resources)
          env {
            name = "AWS_ACCESS_KEY_ID"
            value_from {
              secret_key_ref {
                name = "minio-credentials"
                key  = "AWS_ACCESS_KEY_ID"
              }
            }
          }

          env {
            name = "AWS_SECRET_ACCESS_KEY"
            value_from {
              secret_key_ref {
                name = "minio-credentials"
                key  = "AWS_SECRET_ACCESS_KEY"
              }
            }
          }

          # Atlantis behavior settings
          env {
            name  = "ATLANTIS_EMOJI_REACTION"
            value = var.emoji_reaction
          }

          env {
            name  = "ATLANTIS_ALLOW_COMMANDS"
            value = var.allow_commands
          }

          env {
            name  = "ATLANTIS_AUTOMERGE"
            value = tostring(var.automerge)
          }

          env {
            name  = "ATLANTIS_AUTOPLAN_MODULES"
            value = tostring(var.autoplan_modules)
          }

          env {
            name  = "ATLANTIS_CHECKOUT_STRATEGY"
            value = var.checkout_strategy
          }

          env {
            name  = "ATLANTIS_ENABLE_REGEXP_CMD"
            value = tostring(var.enable_regexp_cmd)
          }

          env {
            name  = "ATLANTIS_FAIL_ON_PRE_WORKFLOW_HOOK_ERROR"
            value = tostring(var.fail_on_pre_workflow_hook_error)
          }

          env {
            name  = "ATLANTIS_PENDING_APPLY_STATUS"
            value = tostring(var.pending_apply_status)
          }

          env {
            name  = "ATLANTIS_LOG_LEVEL"
            value = var.log_level
          }

          env {
            name  = "ATLANTIS_RESTRICT_FILE_LIST"
            value = tostring(var.restrict_file_list)
          }

          env {
            name  = "ATLANTIS_SILENCE_ALLOWLIST_ERRORS"
            value = tostring(var.silence_allowlist_errors)
          }

          env {
            name  = "ATLANTIS_SILENCE_NO_PROJECTS"
            value = tostring(var.silence_no_projects)
          }

          env {
            name  = "ATLANTIS_WRITE_GIT_CREDS"
            value = tostring(var.write_git_creds)
          }

          dynamic "env" {
            for_each = var.gitlab_group_allowlist != null ? [1] : []
            content {
              name  = "ATLANTIS_GITLAB_GROUP_ALLOWLIST"
              value = var.gitlab_group_allowlist
            }
          }

          resources {
            requests = {
              cpu               = var.resource_requests.cpu
              memory            = var.resource_requests.memory
              ephemeral-storage = var.resource_requests.storage
            }
            limits = {
              cpu               = var.resource_limits.cpu
              memory            = var.resource_limits.memory
              ephemeral-storage = var.resource_limits.storage
            }
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = 4141
            }
            initial_delay_seconds = 30
            period_seconds        = 30
          }

          readiness_probe {
            http_get {
              path = "/healthz"
              port = 4141
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }

          volume_mount {
            name       = "atlantis-data"
            mount_path = "/home/atlantis"
          }

          dynamic "volume_mount" {
            for_each = var.repo_config != null ? [1] : []
            content {
              name       = "repo-config"
              mount_path = "/etc/atlantis"
              read_only  = true
            }
          }
        }

        volume {
          name = "atlantis-data"
          empty_dir {}
        }

        dynamic "volume" {
          for_each = var.repo_config != null ? [1] : []
          content {
            name = "repo-config"
            config_map {
              name = kubernetes_config_map_v1.repo_config[0].metadata[0].name
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_role_binding_v1.atlantis,
  ]
}

# --- Service ---

resource "kubernetes_service_v1" "atlantis" {
  metadata {
    name      = "atlantis-${var.instance_name}"
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    selector = {
      app = "atlantis-${var.instance_name}"
    }

    port {
      name        = "http"
      port        = 80
      target_port = 4141
    }

    type = "ClusterIP"
  }
}

# --- Ingress ---

resource "kubernetes_ingress_v1" "atlantis" {
  metadata {
    name      = "atlantis-${var.instance_name}"
    namespace = var.namespace
    labels    = local.labels
    annotations = {
      "nginx.ingress.kubernetes.io/proxy-body-size" = "0"
    }
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = var.atlantis_host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.atlantis.metadata[0].name
              port {
                name = "http"
              }
            }
          }
        }
      }
    }
  }
}
