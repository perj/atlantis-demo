variable "instance_name" {
  description = "Identifier for this Atlantis instance (e.g., 'platform', 'system-alpha')"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace where Atlantis runs"
  type        = string
  default     = "atlantis"
}

variable "gitlab_hostname" {
  description = "GitLab server address (include scheme, e.g. http://gitlab.example.com)"
  type        = string
  default     = "http://gitlab.127.0.0.1.nip.io"
}

variable "gitlab_user" {
  description = "GitLab username for Atlantis"
  type        = string
  default     = "atlantis-bot"
}

variable "gitlab_token_secret" {
  description = "Name of the K8s secret containing GitLab credentials"
  type        = string
  default     = "gitlab-credentials"
}

variable "repo_allowlist" {
  description = "List of repos this Atlantis can manage (e.g., ['gitlab.127.0.0.1.nip.io/root/atlantis-demo'])"
  type        = list(string)
}

variable "atlantis_host" {
  description = "Ingress host for this Atlantis instance"
  type        = string
}

variable "target_namespaces" {
  description = "List of namespaces this Atlantis can manage (for RBAC). If empty, RBAC targets the atlantis namespace itself."
  type        = list(string)
}

variable "resource_limits" {
  description = "CPU and memory limits for the Atlantis container"
  type = object({
    cpu     = string
    memory  = string
    storage = string
  })
  default = {
    cpu     = "1"
    memory  = "512Mi"
    storage = "10Gi"
  }
}

variable "resource_requests" {
  description = "CPU and memory requests for the Atlantis container"
  type = object({
    cpu     = string
    memory  = string
    storage = string
  })
  default = {
    cpu     = "100m"
    memory  = "256Mi"
    storage = "10Gi"
  }
}

variable "atlantis_image" {
  description = "Docker image for Atlantis"
  type        = string
  default     = "ghcr.io/runatlantis/atlantis:v0.40.0"
}

variable "repo_config" {
  description = "Server-side repo configuration YAML content. If null, no server-side config is created."
  type        = string
  default     = null
}
