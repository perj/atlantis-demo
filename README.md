# Atlantis Demo Environment

A complete, self-contained demonstration of [Atlantis](https://www.runatlantis.io/) for GitOps-driven Terraform workflows. This project showcases the **"Atlantis manages Atlantis"** bootstrap pattern, multi-tenancy, RBAC isolation, and best practices for infrastructure-as-code automation.

## What This Demonstrates

- **Bootstrap Pattern**: Platform Atlantis deploys and manages other Atlantis instances via GitLab merge requests
- **Multi-Tenancy**: Isolated Atlantis instances for different systems with RBAC boundaries
- **Two Workflow Patterns**:
  - **Auto-detect**: Directory-based project discovery (no `atlantis.yaml` needed)
  - **Workspace-based**: Explicit project definitions with Terraform workspaces
- **Security & Isolation**: Namespace-level RBAC, separate state storage, no developer access to infrastructure
- **Approval Workflows**: GitLab approval rules enforce separation of duties
- **State Management**: Centralized S3-compatible storage (MinIO) with isolated state files
- **Complete Local Setup**: Runs entirely on your machine using Kind (Kubernetes in Docker)

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                           Local Machine                                  │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │                        Kind Cluster                                │  │
│  │                                                                    │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌──────────────────────────┐    │  │
│  │  │ Namespace:  │  │ Namespace:  │  │     Namespace:           │    │  │
│  │  │   gitlab    │  │    minio    │  │      atlantis            │    │  │
│  │  │             │  │             │  │  (Platform Components)   │    │  │
│  │  │ - GitLab    │  │ - MinIO     │  │                          │    │  │
│  │  │   Server    │  │   (S3 API)  │  │  - Platform Atlantis     │    │  │
│  │  │             │  │ - TF State  │  │  - System-Alpha Atlantis │    │  │
│  │  │             │  │   Storage   │  │  - System-Beta Atlantis  │    │  │
│  │  └─────────────┘  └─────────────┘  └──────────────────────────┘    │  │
│  │                                                                    │  │
│  │  ┌──────────────┐  ┌──────────────┐                                │  │
│  │  │ Namespace:   │  │ Namespace:   │                                │  │
│  │  │ system-alpha │  │ system-beta  │                                │  │
│  │  │              │  │              │                                │  │
│  │  │ Demo         │  │ Demo         │                                │  │
│  │  │ Resources    │  │ Resources    │                                │  │
│  │  └──────────────┘  └──────────────┘                                │  │
│  └────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────┘
```

### Component Roles

| Component | Purpose | Managed By |
|-----------|---------|------------|
| **GitLab** | Source control & MR workflow | Manual setup |
| **MinIO** | S3-compatible Terraform state storage | Manual setup |
| **Platform Atlantis** | Manages all Atlantis deployments | Terraform (manual) |
| **System-Alpha Atlantis** | Manages system-alpha namespace | Platform Atlantis (via MR) |
| **System-Beta Atlantis** | Manages system-beta namespace | Platform Atlantis (via MR) |
| **system-alpha-infra** | Demo repo (auto-detect pattern) | System-Alpha Atlantis |
| **system-beta-infra** | Demo repo (workspace pattern) | System-Beta Atlantis |

## Prerequisites

- **Docker** (20.10+)
- **kubectl** (1.28+)
- **Terraform** (1.5+)
- **jq** (for JSON parsing)
- **curl**
- At least 8GB RAM available for Docker
- Linux or macOS (tested on Ubuntu 22.04+)

## Quick Start

### 1. Run Setup Scripts in Order

Execute each script and wait for it to complete before moving to the next:

```bash
# Phase 1: Create Kind cluster with ingress
./scripts/01-setup-kind.sh

# Phase 2: Deploy GitLab
./scripts/02-setup-gitlab.sh

# Phase 3: Deploy MinIO (state storage)
./scripts/03-setup-minio.sh

# Phase 4: Create atlantis-demo repository in GitLab
./scripts/04-create-repo.sh

# Phase 5: Configure shared resources (namespace, RBAC, secrets)
./scripts/05-configure-shared-resources.sh

# Phase 6: Deploy Platform Atlantis
./scripts/06-deploy-platform-atlantis.sh

# Phase 7: Deploy System Atlantis instances (Alpha & Beta)
./scripts/07-deploy-systems-atlantis.sh

# Phase 8: Create demo repositories
./scripts/08-create-demo-repos.sh
```

**Total setup time:** ~15-20 minutes (depends on download speeds)

### 2. Verify Installation

```bash
# Check all pods are running
kubectl get pods -n gitlab
kubectl get pods -n minio
kubectl get pods -n atlantis

# Should see:
# - gitlab pod (Running)
# - minio pod (Running)
# - atlantis-platform pod (Running)
# - atlantis-system-alpha pod (Running)
# - atlantis-system-beta pod (Running)
```

### 3. Access the Demo

Note: You can also use `./scripts/demo-workflow.sh` and choose option 8 to show all URLs.

Get credentials and URLs:

```bash
# GitLab root password
kubectl get secret -n gitlab gitlab-root-password -o jsonpath='{.data.password}' | base64 -d
echo

# MinIO credentials
kubectl get secret -n minio minio-secret -o jsonpath='{.data.root-user}' | base64 -d
echo
kubectl get secret -n minio minio-secret -o jsonpath='{.data.root-password}' | base64 -d
echo
```

**Access URLs:**
- GitLab: http://gitlab.127.0.0.1.nip.io
- Platform Atlantis: http://atlantis-platform.127.0.0.1.nip.io
- System-Alpha Atlantis: http://atlantis-alpha.127.0.0.1.nip.io
- System-Beta Atlantis: http://atlantis-beta.127.0.0.1.nip.io
- MinIO Console: http://minio-console.127.0.0.1.nip.io

**GitLab Users:**
- `root` - Administrator (use kubectl command above for password)
- `developer` - Standard developer (password: `Dem0!@#DevUser`)

### 4. Run Interactive Demo

```bash
./scripts/demo-workflow.sh
```

This interactive script guides you through all demo scenarios with step-by-step instructions.

## Demo Scenarios

### 1. Bootstrap Flow: Atlantis Manages Atlantis

**What it shows:** Platform Atlantis deploys new Atlantis instances via MRs

**Steps:**
1. Create MR adding `atlantis-servers/environments/system-<number>/`
2. Platform Atlantis auto-plans the deployment
3. Comment `atlantis apply -p system-<number>-atlantis`
4. New System-Gamma Atlantis pod appears in cluster
5. Configure it to watch `system-<number>-infra` repo

**Key insight:** Infrastructure deployment follows same code review process as application code

---

### 2. Auto-Detect Projects (System-Alpha)

**What it shows:** Atlantis automatically discovers projects from directory structure

**Repo structure:**
```
system-alpha-infra/
├── dev/          <- Auto-detected as project "dev"
│   ├── main.tf
│   └── backend.tf
└── prod/         <- Auto-detected as project "prod"
    ├── main.tf
    └── backend.tf
```

**Steps:**
1. Modify file in `dev/` directory
2. Create MR
3. Atlantis auto-plans **only** the `dev` project
4. Apply with: `atlantis apply -d dev`
5. Then modify `modules/` (shared code)
6. Atlantis plans **both** `dev` and `prod` projects

**Key insight:** No `atlantis.yaml` needed; great for simple directory-per-environment patterns

---

### 3. Workspace Environments (System-Beta)

**What it shows:** Single codebase managing multiple environments via Terraform workspaces

**Repo structure:**
```
system-beta-infra/
├── atlantis.yaml  <- Explicit project definitions
├── main.tf        <- Shared code
└── backend.tf     <- Workspace-based state keys
```

**Steps:**
1. Modify `main.tf` (shared code)
2. Create MR
3. Atlantis auto-plans **both** `dev` and `prod` workspace projects
4. Each uses workspace-specific config (different replica counts, etc.)
5. Apply selectively: `atlantis apply -p dev` then `atlantis apply -p prod`

**Key insight:** Shared code across environments with configuration via `terraform.workspace`

---

### 4. System Isolation & RBAC

**What it shows:** Atlantis instances have scoped RBAC permissions

**Steps:**
1. Try to create resource in wrong namespace (System-Alpha → system-beta)
2. Plan succeeds (shows intent)
3. Apply **fails** with permission error
4. Verify RBAC: `kubectl describe role -n system-alpha atlantis-system-alpha`

**Security boundaries:**
- ✅ System-Alpha Atlantis: only `system-alpha` namespace
- ✅ System-Beta Atlantis: only `system-beta` namespace
- ✅ Platform Atlantis: only `atlantis` namespace
- ❌ Developers: NO kubectl access
- ❌ Developers: NO MinIO console access
- ❌ Developers: NO Atlantis pod logs

---

### 5. Approval Workflow

**What it shows:** Separation of duties via GitLab approval rules

**Workflow:**
1. `developer` creates MR
2. Atlantis auto-plans (comments on MR)
3. `developer` tries `atlantis apply` → **BLOCKED** (MR not approved)
4. `root` (maintainer) reviews and approves MR
5. `developer` tries `atlantis apply` again → **SUCCESS**

**Configuration:**
- 1 approval required before merge
- Author cannot approve own MR
- All discussions must be resolved
- Pipeline (Atlantis) must succeed

---

### 6. Locking Mechanism

**What it shows:** Prevents concurrent changes to same project

**Scenario:**
1. MR #1 starts apply on `dev` project
2. Atlantis acquires lock
3. MR #2 tries to apply same `dev` project → **BLOCKED**
4. Atlantis: "This project is currently locked by MR !1"
5. After MR #1 completes, lock releases
6. MR #2 can now apply

**Manual unlock:**
```
atlantis unlock
```

---

### 7. State Management

**What it shows:** Centralized state storage in MinIO

**State organization:**
```
minio://terraform-states/
├── atlantis-servers/
│   ├── platform/terraform.tfstate
│   ├── system-alpha/terraform.tfstate
│   └── system-beta/terraform.tfstate
├── system-alpha-infra/
│   ├── dev/terraform.tfstate
│   └── prod/terraform.tfstate
└── env:/
    ├── dev/system-beta-infra/terraform.tfstate
    └── prod/system-beta-infra/terraform.tfstate
```

**Access MinIO console:**
1. Open http://minio-console.127.0.0.1.nip.io
2. Login with credentials from kubectl (see Quick Start section)
3. Browse `terraform-states` bucket
4. View state files (JSON format)

## Common Operations

### View Atlantis Logs

```bash
# Platform Atlantis
kubectl logs -n atlantis -l app=atlantis-platform -f

# System-Alpha Atlantis
kubectl logs -n atlantis -l app=atlantis-system-alpha -f

# System-Beta Atlantis
kubectl logs -n atlantis -l app=atlantis-system-beta -f
```

### Restart Atlantis

```bash
kubectl rollout restart deployment/atlantis-platform -n atlantis
kubectl rollout restart deployment/atlantis-system-alpha -n atlantis
kubectl rollout restart deployment/atlantis-system-beta -n atlantis
```

### View Atlantis Configuration

```bash
# Platform Atlantis
kubectl get configmap -n atlantis atlantis-platform-repo-config -o yaml

# System-Alpha Atlantis
kubectl get configmap -n atlantis atlantis-system-alpha-repo-config -o yaml
```

### Check Webhook Configuration

```bash
# Get webhook secret for System-Alpha
kubectl get secret -n atlantis atlantis-system-alpha-webhook -o jsonpath='{.data.secret}' | base64 -d
echo
```

### Manual Terraform Operations (if needed)

```bash
# Deploy Platform Atlantis manually
cd atlantis-servers/environments/platform
terraform init
terraform apply

# Deploy System-Alpha Atlantis manually
cd atlantis-servers/environments/system-alpha
terraform init
terraform apply
```

## Troubleshooting

### Atlantis not responding to MR comments

1. Check Atlantis pod is running:
   ```bash
   kubectl get pods -n atlantis
   ```

2. Check Atlantis logs for errors:
   ```bash
   kubectl logs -n atlantis -l app=atlantis-system-alpha
   ```

3. Verify webhook is configured in GitLab:
   - Go to project → Settings → Webhooks
   - Check URL is correct (e.g., http://atlantis-alpha.127.0.0.1.nip.io/events)
   - Test webhook and check for errors

4. Verify repo is in allowlist:
   ```bash
   kubectl get configmap -n atlantis atlantis-system-alpha-config -o yaml | grep repo-allowlist
   ```

### GitLab 502 Bad Gateway

GitLab takes 2-3 minutes to start up. Wait and try again:

```bash
kubectl get pods -n gitlab
# Wait until STATUS is "Running" and READY is "1/1"
```

### MinIO not accessible

Check MinIO service and ingress:

```bash
kubectl get svc -n minio
kubectl get ingress -n minio
```

### Atlantis plan fails with "403 Forbidden"

Check GitLab token is configured correctly:

```bash
kubectl get secret -n atlantis atlantis-gitlab-token -o jsonpath='{.data.token}' | base64 -d
```

### State locking errors

If Atlantis crashes during apply, state may remain locked. Access MinIO console and delete the `.tflock` file, or comment `atlantis unlock` on the MR.

### Kind cluster issues

Recreate the cluster:

```bash
kind delete cluster --name atlantis-demo
./scripts/01-setup-kind.sh
# Then re-run all setup scripts in order
```

## Cleanup

### Remove demo resources only

```bash
./scripts/demo-workflow.sh
# Select option 9: Cleanup Demo Resources
```

### Remove entire environment

```bash
kind delete cluster --name atlantis-demo
```

This removes everything: the Kind cluster, GitLab, MinIO, Atlantis instances, and all data.

## Learning Resources

### Atlantis Documentation
- Official Docs: https://www.runatlantis.io/docs/
- atlantis.yaml Reference: https://www.runatlantis.io/docs/repo-level-atlantis-yaml.html
- Server Configuration: https://www.runatlantis.io/docs/server-configuration.html

### Concepts Demonstrated
- **GitOps**: Infrastructure changes via git workflow (MRs)
- **Immutable Infrastructure**: Changes applied via code, not manual kubectl
- **Separation of Duties**: Code author ≠ code approver
- **Principle of Least Privilege**: Scoped RBAC per Atlantis instance
- **State Isolation**: Separate state files per environment
- **Bootstrap Pattern**: Infrastructure deploys infrastructure

### Related Tools
- [Kind](https://kind.sigs.k8s.io/) - Kubernetes in Docker
- [Terraform](https://www.terraform.io/) - Infrastructure as Code
- [GitLab](https://about.gitlab.com/) - Source control & CI/CD
- [MinIO](https://min.io/) - S3-compatible object storage

## License

[Your license here]
