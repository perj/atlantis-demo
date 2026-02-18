variable "environment" {
  description = "Environment name (dev, prod, etc.)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
}

variable "replica_count" {
  description = "Number of replicas for the application"
  type        = number
}

variable "log_level" {
  description = "Application log level"
  type        = string
  default     = "info"
}

variable "cpu_request" {
  description = "CPU request for resource quota"
  type        = string
}

variable "memory_request" {
  description = "Memory request for resource quota"
  type        = string
}

variable "cpu_limit" {
  description = "CPU limit for resource quota"
  type        = string
}

variable "memory_limit" {
  description = "Memory limit for resource quota"
  type        = string
}

variable "max_pods" {
  description = "Maximum number of pods for resource quota"
  type        = number
}
