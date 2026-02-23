variable "instance_name" {
  description = "Identifier for this Atlantis instance (e.g. 'system-alpha')"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace to deploy into"
  type        = string
  default     = "atlantis"
}

variable "target_namespaces" {
  description = "Namespaces this instance manages. The main SA gets 'edit' access; the readonly SA gets 'view' access."
  type        = list(string)
}

variable "atlantis_host" {
  description = "Ingress hostname for this instance (e.g. 'atlantis-alpha.127.0.0.1.nip.io')"
  type        = string
}

variable "repo_allowlist" {
  description = "Repos this Atlantis instance is allowed to manage"
  type        = list(string)
}

variable "gitlab_hostname" {
  description = "GitLab server hostname (include scheme)"
  type        = string
  default     = "http://gitlab.127.0.0.1.nip.io"
}

variable "gitlab_user" {
  description = "GitLab username for the Atlantis bot account"
  type        = string
  default     = "atlantis-bot"
}

variable "gitlab_token_secret" {
  description = "Name of the K8s secret containing the GitLab token (key: 'token')"
  type        = string
  default     = "gitlab-credentials"
}

variable "atlantis_image" {
  description = "Atlantis container image"
  type        = string
  default     = "ghcr.io/runatlantis/atlantis:v0.40.0"
}

variable "storage_size" {
  description = "Size of the PVC used for the Atlantis workspace. Must be large enough for terraform providers and repo checkouts."
  type        = string
  default     = "10Gi"
}
