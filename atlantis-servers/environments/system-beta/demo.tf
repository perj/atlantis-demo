# Demo re-run tracking (harmless label that triggers Atlantis auto-plan)
variable "demo_run_timestamp" {
  description = "Timestamp of demo run - used as a label to track deployments"
  type        = string
  default     = ""
}

resource "kubernetes_labels" "system_beta_timestamp" {
  api_version = "v1"
  kind        = "Namespace"
  metadata {
    name = "system-beta"
  }
  labels = {
    "demo-run" = var.demo_run_timestamp != "" ? var.demo_run_timestamp : "initial"
  }
  depends_on = [module.system_beta_atlantis]
}
