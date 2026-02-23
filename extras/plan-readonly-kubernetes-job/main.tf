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

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "kind-atlantis-demo"
}

locals {
  main_sa      = "atlantis-${var.instance_name}"
  ro_sa        = "atlantis-${var.instance_name}-readonly"
  atlantis_url = "http://${var.atlantis_host}"

  labels = {
    app                           = "atlantis-${var.instance_name}"
    instance                      = var.instance_name
    "app.kubernetes.io/name"      = "atlantis"
    "app.kubernetes.io/instance"  = var.instance_name
    "app.kubernetes.io/component" = "server"
  }
}

# --- Target Namespaces -------------------------------------------------------
#
# This module does NOT create target namespaces. It assumes they already
# exist, which is the case when the full base demo setup (scripts 01-08)
# has been completed before running setup.sh.

# --- Main ServiceAccount (read-write, used for apply) ------------------------

resource "kubernetes_service_account_v1" "atlantis" {
  metadata {
    name      = local.main_sa
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

# --- Readonly ServiceAccount (used for plan Jobs) ----------------------------
#
# This SA gets only the "view" ClusterRole on the target namespaces.
# The plan Job runs as this SA, so terraform plan cannot make write calls.
#
# In a real IRSA setup this SA would simply carry a different annotation:
#   eks.amazonaws.com/role-arn = <readonly IAM role ARN>
# and the EKS OIDC webhook would inject the matching AWS credentials
# automatically — no credential plumbing needed in the script at all.

resource "kubernetes_service_account_v1" "readonly" {
  metadata {
    name      = local.ro_sa
    namespace = var.namespace
    labels    = local.labels
  }
}

resource "kubernetes_role_binding_v1" "readonly" {
  for_each = toset(var.target_namespaces)

  metadata {
    name      = "atlantis-${var.instance_name}-readonly-view"
    namespace = each.value
    labels    = local.labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "view"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.readonly.metadata[0].name
    namespace = var.namespace
  }
}

# The built-in 'view' ClusterRole does not include RBAC resources.
# Terraform plan needs get/list on roles and rolebindings to refresh state
# for any configuration that manages them (e.g. the demo infra module).
resource "kubernetes_role_v1" "readonly_rbac" {
  for_each = toset(var.target_namespaces)

  metadata {
    name      = "atlantis-${var.instance_name}-readonly-rbac"
    namespace = each.value
    labels    = local.labels
  }

  rule {
    api_groups = ["rbac.authorization.k8s.io"]
    resources  = ["roles", "rolebindings"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_role_binding_v1" "readonly_rbac" {
  for_each = toset(var.target_namespaces)

  metadata {
    name      = "atlantis-${var.instance_name}-readonly-rbac"
    namespace = each.value
    labels    = local.labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.readonly_rbac[each.value].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.readonly.metadata[0].name
    namespace = var.namespace
  }
}

# --- Job management permissions for the main SA ------------------------------
#
# The Atlantis pod needs to create and watch the plan Jobs it spawns, and
# read their pod logs to stream output back into the PR comment.

resource "kubernetes_role_v1" "job_manager" {
  metadata {
    name      = "atlantis-${var.instance_name}-plan-job-manager"
    namespace = var.namespace
    labels    = local.labels
  }

  rule {
    api_groups = ["batch"]
    resources  = ["jobs"]
    verbs      = ["create", "get", "list", "watch", "delete"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/log"]
    verbs      = ["get"]
  }
}

resource "kubernetes_role_binding_v1" "job_manager" {
  metadata {
    name      = "atlantis-${var.instance_name}-plan-job-manager"
    namespace = var.namespace
    labels    = local.labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.job_manager.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = local.main_sa
    namespace = var.namespace
  }
}

# --- Secrets -----------------------------------------------------------------

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

# --- PVC for the Atlantis workspace ------------------------------------------
#
# Unlike the base module which uses an emptyDir, we use a PVC here so the
# plan Job pod can mount the same workspace directory. Both the Atlantis pod
# and the Job pod mount this PVC at /home/atlantis.

resource "kubernetes_persistent_volume_claim_v1" "workspace" {
  metadata {
    name      = "atlantis-${var.instance_name}-data"
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    # See plan-in-job.sh for why ReadWriteOnce.
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = var.storage_size
      }
    }
  }

  # Kind's local-path provisioner uses WaitForFirstConsumer, so the PVC
  # stays Pending until the first pod mounts it — that's expected.
  wait_until_bound = false
}

# --- ConfigMap: server-side repo config --------------------------------------

resource "kubernetes_config_map_v1" "repo_config" {
  metadata {
    name      = "atlantis-${var.instance_name}-repo-config"
    namespace = var.namespace
    labels    = local.labels
  }

  data = {
    "repos.yaml" = <<-EOT
      repos:
        - id: /.*/
          plan_requirements: []
          apply_requirements: [approved, mergeable]
          import_requirements: [mergeable]
          # Repos cannot define their own workflows or override settings.
          allow_custom_workflows: false
          allowed_overrides: []

      workflows:
        default:
          plan:
            steps:
              - run: /home/atlantis/.scripts/plan-in-job.sh
          apply:
            steps:
              - apply
    EOT
  }
}

# --- ConfigMap: plan-in-job.sh -----------------------------------------------
#
# The plan script is mounted into the Atlantis container at
# /home/atlantis/.scripts/plan-in-job.sh and called by the custom workflow.

resource "kubernetes_config_map_v1" "plan_script" {
  metadata {
    name      = "atlantis-${var.instance_name}-plan-script"
    namespace = var.namespace
    labels    = local.labels
  }

  data = {
    "plan-in-job.sh" = file("${path.module}/plan-in-job.sh")
  }
}

# --- Deployment --------------------------------------------------------------

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

        # Copies kubectl from the bitnami/kubectl image onto the shared PVC.
        # The Atlantis image doesn't bundle kubectl, but plan-in-job.sh needs
        # it to create and watch the plan Job.
        init_container {
          name  = "install-kubectl"
          image = "bitnami/kubectl:latest"

          command = [
            "sh", "-c",
            "mkdir -p /home/atlantis/.bin && cp $(which kubectl) /home/atlantis/.bin/kubectl && chmod +x /home/atlantis/.bin/kubectl",
          ]

          volume_mount {
            name       = "atlantis-data"
            mount_path = "/home/atlantis"
          }
        }

        # Builds ~/.kube/config from the in-cluster SA token so the kubernetes
        # terraform provider works without explicit server URLs.
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

          # --- Atlantis configuration ---

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
          env {
            name  = "ATLANTIS_REPO_CONFIG"
            value = "/etc/atlantis/repos.yaml"
          }
          env {
            name  = "ATLANTIS_CHECKOUT_STRATEGY"
            value = "merge"
          }
          env {
            name  = "ATLANTIS_AUTOMERGE"
            value = "true"
          }
          env {
            name  = "ATLANTIS_AUTOPLAN_MODULES"
            value = "true"
          }
          env {
            name  = "ATLANTIS_WRITE_GIT_CREDS"
            value = "true"
          }
          env {
            name  = "ATLANTIS_PENDING_APPLY_STATUS"
            value = "true"
          }
          env {
            name  = "ATLANTIS_EMOJI_REACTION"
            value = "eyes"
          }

          # --- Addon-specific env vars ---

          # Tells plan-in-job.sh which SA and PVC name to use.
          env {
            name  = "ATLANTIS_INSTANCE"
            value = var.instance_name
          }

          # Exposes the pod's namespace to plan-in-job.sh via the Downward API.
          env {
            name = "POD_NAMESPACE"
            value_from {
              field_ref {
                field_path = "metadata.namespace"
              }
            }
          }

          # --- Secrets ---

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
          volume_mount {
            name       = "repo-config"
            mount_path = "/etc/atlantis"
            read_only  = true
          }
          volume_mount {
            name       = "plan-script"
            mount_path = "/home/atlantis/.scripts"
          }
        }

        volume {
          name = "atlantis-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.workspace.metadata[0].name
          }
        }

        volume {
          name = "repo-config"
          config_map {
            name = kubernetes_config_map_v1.repo_config.metadata[0].name
          }
        }

        volume {
          name = "plan-script"
          config_map {
            name         = kubernetes_config_map_v1.plan_script.metadata[0].name
            default_mode = "0755"
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_role_binding_v1.atlantis,
  ]
}

# --- Service -----------------------------------------------------------------

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

# --- Ingress -----------------------------------------------------------------

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
