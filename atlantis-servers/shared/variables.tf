variable "gitlab_url" {
  description = "GitLab instance URL"
  type        = string
  default     = "http://gitlab.127.0.0.1.nip.io"
}

variable "atlantis_bot_email" {
  description = "Email address for atlantis-bot user"
  type        = string
  default     = "atlantis-bot@localhost"
}

variable "minio_access_key" {
  description = "MinIO access key"
  type        = string
  default     = "terraform"
}

variable "minio_secret_key" {
  description = "MinIO secret key"
  type        = string
  default     = "terraform-secret-key-change-me"
  sensitive   = true
}
