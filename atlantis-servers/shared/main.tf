terraform {
  required_version = ">= 1.14"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    gitlab = {
      source  = "gitlabhq/gitlab"
      version = "~> 18.8"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.8"
    }
  }
}

# Validation: Check that we're connected to the right cluster
# This will fail if the gitlab namespace doesn't exist, preventing
# accidental application to the wrong cluster
data "kubernetes_namespace_v1" "gitlab" {
  metadata {
    name = "gitlab"
  }
}

# Data source to fetch GitLab root token from Kubernetes secret
data "kubernetes_secret_v1" "gitlab_root_token" {
  metadata {
    name      = "gitlab-root-token"
    namespace = "gitlab"
  }

  # Ensure we validate cluster before reading secrets
  depends_on = [data.kubernetes_namespace_v1.gitlab]
}

# Configure Kubernetes provider
# When running locally: uses ~/.kube/config (default)
# When running in Atlantis pod: uses in-cluster config (service account)
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "kind-atlantis-demo"
}

# Configure GitLab provider using root token
provider "gitlab" {
  base_url = var.gitlab_url
  token    = data.kubernetes_secret_v1.gitlab_root_token.data["password"]
}

# Create atlantis namespace where all Atlantis servers will be deployed
resource "kubernetes_namespace_v1" "atlantis" {
  metadata {
    name = "atlantis"
    labels = {
      name    = "atlantis"
      purpose = "atlantis-servers"
    }
  }
}

# Create GitLab service account user for Atlantis
resource "gitlab_user" "atlantis_bot" {
  name             = "Atlantis Bot"
  username         = "atlantis-bot"
  email            = var.atlantis_bot_email
  is_admin         = false
  can_create_group = false

  # Set a strong random password (won't be used, we'll use token auth)
  password = random_password.atlantis_bot_password.result

  # Skip email confirmation
  skip_confirmation = true
}

# Generate random password for atlantis-bot user
resource "random_password" "atlantis_bot_password" {
  length  = 32
  special = true
}

# Create personal access token for atlantis-bot with api scope
resource "gitlab_personal_access_token" "atlantis_bot" {
  user_id = gitlab_user.atlantis_bot.id
  name    = "atlantis-automation-token"
  scopes  = ["api"]

  # Automatic token rotation configuration
  # Token will be rotated 7 days before expiry when terraform apply is run
  rotation_configuration = {
    expiration_days    = 360 # Just under a year, default limit in Gitlab
    rotate_before_days = 7
  }
}

# Store GitLab credentials in Kubernetes secret in atlantis namespace
# This will be used by Atlantis servers for GitLab authentication
resource "kubernetes_secret_v1" "gitlab_credentials" {
  metadata {
    name      = "gitlab-credentials"
    namespace = kubernetes_namespace_v1.atlantis.metadata[0].name
  }

  data = {
    token    = gitlab_personal_access_token.atlantis_bot.token
    username = gitlab_user.atlantis_bot.username
    url      = var.gitlab_url
  }

  type = "Opaque"
}

# Store MinIO credentials in atlantis namespace for Terraform backend access
resource "kubernetes_secret_v1" "minio_credentials" {
  metadata {
    name      = "minio-credentials"
    namespace = kubernetes_namespace_v1.atlantis.metadata[0].name
  }

  data = {
    AWS_ACCESS_KEY_ID     = var.minio_access_key
    AWS_SECRET_ACCESS_KEY = var.minio_secret_key
  }

  type = "Opaque"
}
