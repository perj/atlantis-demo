# System Alpha Infrastructure

This repository manages Kubernetes infrastructure for System Alpha using Terraform with an **auto-detect project pattern**.

## Structure

```
system-alpha-infra/
├── modules/
│   └── environment/       # Reusable module for all environments
│       ├── main.tf        # K8s resources (ConfigMaps, Secrets, RBAC, etc.)
│       ├── variables.tf   # Module input variables
│       └── outputs.tf     # Module outputs
├── dev/
│   ├── main.tf           # Dev environment - calls module with dev params
│   └── backend.tf        # State: system-alpha-infra/dev/terraform.tfstate
└── prod/
    ├── main.tf           # Prod environment - calls module with prod params
    └── backend.tf        # State: system-alpha-infra/prod/terraform.tfstate
```

## Atlantis Auto-Detect Pattern

This repo **does not** have an `atlantis.yaml` file. Atlantis automatically discovers:
- `dev/` as one project
- `prod/` as another project

### How it works:
- Change a file in `dev/` → Atlantis plans only the dev project
- Change a file in `prod/` → Atlantis plans only the prod project
- Change a file in `modules/` → Atlantis plans both dev and prod projects
- Each directory with `.tf` files is treated as a separate project

### Applying changes:
```bash
# Apply to specific directory
atlantis apply -d dev
atlantis apply -d prod
```

## Resources Managed

Each environment creates:
- ConfigMap (application configuration)
- Secret (credentials)
- ServiceAccount
- Role & RoleBinding (RBAC)
- ResourceQuota
- NetworkPolicy

## Environment Differences

| Resource | Dev | Prod |
|----------|-----|------|
| Replicas | 1 | 3 |
| Log Level | debug | info |
| CPU Request | 2 | 4 |
| Memory Request | 4Gi | 8Gi |
| Max Pods | 10 | 20 |
