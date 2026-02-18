# System Beta Infrastructure

This repository manages Kubernetes infrastructure for System Beta using Terraform with a **workspace-based project pattern**.

## Structure

```
system-beta-infra/
├── atlantis.yaml         # Defines dev & prod projects with workspaces
├── main.tf              # Shared K8s resources with workspace-based config
├── variables.tf         # Input variables
└── backend.tf           # State: system-beta-infra/${workspace}/terraform.tfstate
```

## Atlantis Workspace Pattern

This repo **has** an `atlantis.yaml` that explicitly defines two projects:
- `dev` project → uses `dev` workspace
- `prod` project → uses `prod` workspace

### How it works:
- Change **any** `.tf` file → Atlantis plans **both** dev and prod projects
- Same Terraform code, different workspaces for environment separation
- Environment-specific configuration via `locals` block based on `terraform.workspace`

### Applying changes:
```bash
# Apply to specific project (workspace)
atlantis apply -p dev
atlantis apply -p prod
```

## Resources Managed

Each workspace creates:
- ConfigMap (application configuration)
- Secret (credentials)
- ServiceAccount
- Role & RoleBinding (RBAC)
- ResourceQuota
- NetworkPolicy

All resources are prefixed with the workspace name (e.g., `dev-app-config`, `prod-app-config`).

## Environment Configuration

Environment-specific settings are defined in the `locals` block in [main.tf](main.tf):

| Resource | Dev | Prod |
|----------|-----|------|
| Replicas | 1 | 3 |
| Log Level | debug | info |
| CPU Request | 1 | 2 |
| Memory Request | 2Gi | 4Gi |
| Max Pods | 10 | 20 |

## When to Use This Pattern

Workspace-based patterns work well when:
- You want shared code across environments
- Environment differences are mainly configuration values
- You want all environments to stay in sync code-wise
- You prefer explicit project definitions over auto-detection
