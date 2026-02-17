# atlantis-server module

Deploys an Atlantis server instance into a Kubernetes cluster.

Creates a Deployment, Service, Ingress, ServiceAccount, RBAC, and supporting
secrets/configmaps. All Atlantis configuration is passed via environment
variables.

## Prerequisites

The following must exist before using this module (created by the shared
resources Terraform in `atlantis-servers/shared/`):

- The `atlantis` namespace
- `gitlab-credentials` secret (GitLab token for atlantis-bot)
- `minio-credentials` secret (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY)

## Required variables

### `instance_name`

Unique identifier for this Atlantis instance.

Example: `"platform"`, `"system-alpha"`

### `atlantis_host`

Ingress hostname, handles webhook and user interface.

Example: `"atlantis-platform.127.0.0.1.nip.io`

### `repo_allowlist`

Repos this instance can manage.

Example: `["gitlab.127.0.0.1.nip.io/root/atlantis-demo"]`

### `target_namespaces`

Namespaces this instance can manage.

Example: `["atlantis"]`

## Usage

```hcl
module "platform" {
  source = "../../modules/atlantis-server"

  instance_name     = "platform"
  atlantis_host     = "atlantis-platform.127.0.0.1.nip.io"
  repo_allowlist    = ["gitlab.127.0.0.1.nip.io/root/atlantis-demo"]
  target_namespaces = ["atlantis"]
}
```

After apply, configure the GitLab webhook:

```
terraform output gitlab_webhook_setup
terraform output -raw webhook_secret
```

See [variables.tf](variables.tf) for all optional variables and their defaults.
