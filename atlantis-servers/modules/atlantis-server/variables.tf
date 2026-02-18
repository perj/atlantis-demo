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
  default     = <<-EOT
    repos:
      - id: /.*/
        plan_requirements: []
        apply_requirements: [approved, mergeable]
        import_requirements: [mergeable]
  EOT
}

# --- Atlantis behavior settings ---

variable "emoji_reaction" {
  description = "Emoji reaction to add to comments when Atlantis starts processing. Empty string disables reactions."
  type        = string
  default     = "eyes"
}

variable "allow_commands" {
  description = "Which commands are allowed. Comma-separated list or 'all'."
  type        = string
  default     = "all"
}

variable "automerge" {
  description = "Automatically merge pull requests after all plans are applied."
  type        = bool
  default     = true
}

variable "autoplan_modules" {
  description = "Automatically plan when module files change."
  type        = bool
  default     = true
}

variable "checkout_strategy" {
  description = "How to check out the PR code. Options: 'branch', 'merge'."
  type        = string
  default     = "merge"
}

variable "enable_regexp_cmd" {
  description = "Enable regular expressions in plan/apply commands."
  type        = bool
  default     = false
}

variable "fail_on_pre_workflow_hook_error" {
  description = "Fail the operation if a pre-workflow hook returns a non-zero exit code."
  type        = bool
  default     = true
}

variable "pending_apply_status" {
  description = "Set atlantis/apply commit status to pending after plan, blocking merge until apply completes. GitLab only."
  type        = bool
  default     = true
}

variable "log_level" {
  description = "Atlantis log level. Options: debug, info, warn, error."
  type        = string
  default     = "info"
}

variable "restrict_file_list" {
  description = "Restrict plan output to only show files within the project directory."
  type        = bool
  default     = true
}

variable "silence_allowlist_errors" {
  description = "Silence errors from repos not in the allowlist."
  type        = bool
  default     = false
}

variable "silence_no_projects" {
  description = "Silence 'no projects' comments when no projects match."
  type        = bool
  default     = false
}

variable "write_git_creds" {
  description = "Write out a .git-credentials file with the GitLab token."
  type        = bool
  default     = true
}

variable "gitlab_group_allowlist" {
  description = "Comma-separated list of GitLab groups and permission pairs. If null, the setting is not configured."
  type        = string
  default     = null
}
