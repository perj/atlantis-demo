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

# --- Readonly ServiceAccount (used for plan, inside bwrap) -------------------
#
# This SA gets only the "view" ClusterRole on the target namespaces.
# plan-bwrap.sh mints a short-lived token for this SA and injects it into the
# bwrap sandbox, replacing the rw token for the duration of terraform plan.
#
# In a real AWS/IRSA setup, swapping the SA token file alone is not sufficient.
# The pod already started with the rw SA, so the IRSA webhook already injected:
#   AWS_WEB_IDENTITY_TOKEN_FILE → path to the rw SA's projected token file
#   AWS_ROLE_ARN                → the rw IAM role ARN
# The AWS SDK uses that token file to call sts:AssumeRoleWithWebIdentity, so
# a provider running during plan could still assume the rw IAM role even with
# the Kubernetes SA token shadowed.
# plan-bwrap.sh would also need to:
#   1. Bind-mount the readonly token over $AWS_WEB_IDENTITY_TOKEN_FILE
#   2. Override AWS_ROLE_ARN via bwrap --setenv to the readonly IAM role ARN
# Unlike the Job variant (where pod identity handles everything at pod startup),
# bwrap requires both the k8s and cloud credential layers to be handled explicitly.

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

# --- Token-mint permission for the main SA -----------------------------------
#
# plan-bwrap.sh calls the Kubernetes TokenRequest API to mint a short-lived
# token for the readonly SA. This Role grants the main SA permission to do
# exactly that — scoped to the readonly SA only.

resource "kubernetes_role_v1" "mint_readonly_token" {
  metadata {
    name      = "atlantis-${var.instance_name}-mint-readonly-token"
    namespace = var.namespace
    labels    = local.labels
  }

  rule {
    api_groups     = [""]
    resources      = ["serviceaccounts/token"]
    verbs          = ["create"]
    resource_names = [local.ro_sa]
  }
}

resource "kubernetes_role_binding_v1" "mint_readonly_token" {
  metadata {
    name      = "atlantis-${var.instance_name}-mint-readonly-token"
    namespace = var.namespace
    labels    = local.labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.mint_readonly_token.metadata[0].name
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
              - init
              - run: /home/atlantis/.scripts/plan-bwrap.sh
          apply:
            steps:
              - apply
    EOT
  }
}

# --- ConfigMap: plan-bwrap.sh ------------------------------------------------
#
# The plan script is mounted into the Atlantis container at
# /home/atlantis/.scripts/plan-bwrap.sh and called by the custom workflow.

resource "kubernetes_config_map_v1" "plan_script" {
  metadata {
    name      = "atlantis-${var.instance_name}-plan-script"
    namespace = var.namespace
    labels    = local.labels
  }

  data = {
    "plan-bwrap.sh" = file("${path.module}/plan-bwrap.sh")
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

        # Builds ~/.kube/config from the in-cluster SA token so the kubernetes
        # terraform provider works without explicit server URLs.
        init_container {
          name  = "setup-kubeconfig"
          image = "bitnami/kubectl:latest"

          command = [
            "sh", "-c",
            <<-EOT
            mkdir -p /root/.kube
            export KUBECONFIG=/root/.kube/config
            kubectl config set-cluster in-cluster \
              --server=https://kubernetes.default.svc \
              --certificate-authority=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
            kubectl config set-credentials atlantis \
              --token=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
            kubectl config set-context kind-atlantis-demo \
              --cluster=in-cluster \
              --user=atlantis
            kubectl config use-context kind-atlantis-demo
            chmod 644 /root/.kube/config
            EOT
          ]

          volume_mount {
            name       = "atlantis-data"
            mount_path = "/root"
          }
        }

        container {
          name    = "atlantis"
          image   = var.atlantis_image
          command = ["atlantis", "server"]

          # Run as root so that CAP_SYS_ADMIN is in the effective capability set.
          #
          # bwrap requires CAP_SYS_ADMIN to call clone(CLONE_NEWNS) and mount()
          # to create the credential sandbox during plan. Kubernetes places added
          # capabilities in the permitted set, but for a non-root process they
          # are NOT automatically promoted to the effective set — so bwrap would
          # fail even with SYS_ADMIN in capabilities.add.
          #
          # Running as root (UID 0) keeps all permitted capabilities in the
          # effective set across exec(), giving bwrap the SYS_ADMIN it needs.
          # Setuid bwrap does not work in containers (the bounding set
          # restricts what setuid binaries can reclaim via capset()).
          #
          # The security property being demonstrated is credential isolation:
          # the rw SA token is bind-mounted away inside the bwrap sandbox, so
          # provider code physically cannot read it regardless of UID. For a
          # setup where UID-level isolation also matters, a user-namespace
          # mapping that drops the child to a non-root UID would be needed.
          security_context {
            run_as_user = 0
            capabilities {
              add = ["SYS_ADMIN"]
            }
          }

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

          # --- Addon-specific env var ---

          # Tells plan-bwrap.sh the readonly SA name to mint a token for.
          env {
            name  = "ATLANTIS_INSTANCE"
            value = var.instance_name
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
            mount_path = "/root"
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
          empty_dir {}
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
