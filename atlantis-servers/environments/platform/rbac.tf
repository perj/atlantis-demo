# --- Cluster-level RBAC for platform Atlantis ---
# The platform instance needs broad permissions: creating namespaces and
# editing resources across all of them. For the demo we simply grant
# cluster-admin rather than maintaining a per-namespace list.

resource "kubernetes_cluster_role_binding_v1" "platform_cluster_admin" {
  metadata {
    name = "atlantis-platform-cluster-admin"
    labels = {
      app                          = "atlantis-platform"
      "app.kubernetes.io/name"     = "atlantis"
      "app.kubernetes.io/instance" = "platform"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = module.platform_atlantis.service_account_name
    namespace = module.platform_atlantis.namespace
  }
}
