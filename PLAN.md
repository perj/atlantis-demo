# Atlantis Demo Environment - Implementation Plan

## Overview

This plan creates a fully local, self-contained demo environment showcasing Atlantis for Terraform workflows. The setup runs entirely on your local machine using Kind (Kubernetes in Docker) and a local GitLab instance.

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
│  │  │             │  │ - TF State  │  │    (manages platform)    │    │  │
│  │  │             │  │   Storage   │  │  - System-Alpha Atlantis │    │  │
│  │  │             │  │             │  │    (manages system-alpha)│    │  │
│  │  │             │  │             │  │  - System-Beta Atlantis  │    │  │
│  │  │             │  │             │  │    (manages system-beta) │    │  │
│  │  └─────────────┘  └─────────────┘  └──────────────────────────┘    │  │
│  │                                                                    │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐  │  │
│  │  │ Namespace:   │  │ Namespace:   │  │   Shared Resources       │  │  │
│  │  │system-alpha  │  │system-beta   │  │                          │  │  │
│  │  │              │  │              │  │ - Ingress (nginx)        │  │  │
│  │  │ - Demo       │  │ - Demo       │  │ - GitLab ServiceAccount  │  │  │
│  │  │   Resources  │  │   Resources  │  │   (atlantis-bot)         │  │  │
│  │  │   (managed   │  │   (managed   │  │                          │  │  │
│  │  │   by System  │  │   by System  │  │ System developers have   │  │  │
│  │  │   Atlantis)  │  │   Atlantis)  │  │ NO access to:            │  │  │
│  │  │              │  │              │  │ - atlantis namespace     │  │  │
│  │  └──────────────┘  └──────────────┘  │ - minio namespace        │  │  │
│  │                                      │ - Terraform state        │  │  │
│  │                                      └──────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  Bootstrap Flow:                                                         │
│  1. Setup GitLab + MinIO (manual)                                        │
│  2. Deploy Platform Atlantis to atlantis namespace (terraform apply)     │
│  3. Deploy System Atlantis servers to atlantis namespace (via PRs)       │
│                                                                          │
│  Security Model:                                                         │
│  - Platform developers: Access to atlantis, minio, gitlab namespaces     │
│  - System developers: Only interact via GitLab PRs, no infra access      │
│  - Atlantis ServiceAccounts: RBAC permissions to manage target NS        │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

## Project Structure

**Key Changes from Original Plan:**
- Added MinIO for centralized state storage
- Renamed "team" → "system" (a system is a closely related set of services)
- Platform Atlantis config lives in this repo (`atlantis-servers/platform/`)
- Bootstrap pattern: Platform Atlantis → System Atlantis instances
- Only platform Atlantis is deployed manually; system Atlantis via PRs

```
atlantis-demo/
├── README.md
├── atlantis.yaml                    # Platform repo Atlantis config
├── scripts/
│   ├── 01-setup-kind.sh
│   ├── 02-setup-gitlab.sh
│   ├── 03-setup-minio.sh
│   ├── 04-configure-gitlab.sh
│   ├── 05-deploy-platform-atlantis.sh
│   ├── 06-create-demo-repos.sh
│   ├── cleanup.sh
│   └── demo-workflow.sh
├── kind/
│   └── cluster-config.yaml
├── kubernetes/
│   ├── gitlab/
│   │   ├── namespace.yaml
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── ingress.yaml
│   │   └── persistent-volumes.yaml
│   └── ingress-nginx/
│       └── values.yaml
├── atlantis-servers/
│   ├── modules/
│   │   └── atlantis-server/
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       ├── outputs.tf
│   │       └── templates/
│   │           ├── deployment.yaml.tpl
│   │           ├── service.yaml.tpl
│   │           ├── ingress.yaml.tpl
│   │           ├── configmap.yaml.tpl
│   │           └── secret.yaml.tpl
│   ├── environments/
│   │   ├── platform/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── terraform.tfvars
│   │   │   └── backend.tf
│   │   ├── system-alpha/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── terraform.tfvars
│   │   │   └── backend.tf
│   │   └── system-beta/
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       ├── terraform.tfvars
│   │       └── backend.tf
│   └── shared/
│       ├── main.tf
│       └── outputs.tf
└── demo-repos/
    ├── system-alpha-infra/
    │   ├── atlantis.yaml
    │   ├── main.tf
    │   ├── variables.tf
    │   └── envs/
    │       ├── dev/
    │       │   └── terraform.tfvars
    │       └── prod/
    │           └── terraform.tfvars
    └── system-beta-infra/
        ├── atlantis.yaml
        ├── main.tf
        ├── variables.tf
        └── envs/
            ├── dev/
            │   └── terraform.tfvars
            └── prod/
                └── terraform.tfvars
```

## Implementation Phases

### Phase 1: Local Infrastructure Setup

**Goal:** Create the Kind cluster and basic networking

**Tasks:**
1. Create Kind cluster configuration with:
   - Extra port mappings for ingress (80, 443)
   - Sufficient resources for GitLab
   - Local path provisioner for persistent volumes

2. Deploy ingress-nginx controller

3. Configure local DNS entries in `/etc/hosts`

**Files to create:**
- `kind/cluster-config.yaml`
- `scripts/01-setup-kind.sh`
- `kubernetes/ingress-nginx/values.yaml`

**Validation:**
- `kubectl get nodes` shows ready node
- Ingress controller pod is running

---

### Phase 2: GitLab Deployment

**Goal:** Deploy GitLab CE in the Kind cluster

**Tasks:**
1. Create GitLab namespace and RBAC

2. Deploy GitLab using the official Helm chart (simplified) or Docker image
   - Use `gitlab/gitlab-ce` image for simplicity
   - Configure for minimal resources (demo purposes)
   - Disable unnecessary features (registry, pages, etc.)

3. Create persistent volumes for GitLab data

4. Expose via ingress at `gitlab.127.0.0.1.nip.io`

5. Wait for GitLab to initialize and retrieve root password

**Files to create:**
- `kubernetes/gitlab/namespace.yaml`
- `kubernetes/gitlab/deployment.yaml`
- `kubernetes/gitlab/service.yaml`
- `kubernetes/gitlab/ingress.yaml`
- `kubernetes/gitlab/persistent-volumes.yaml`
- `scripts/02-setup-gitlab.sh`

**Validation:**
- GitLab accessible at `http://gitlab.127.0.0.1.nip.io`
- Can log in as root

---

### Phase 3: Terraform State Backend (MinIO)

**Goal:** Deploy MinIO as centralized S3-compatible Terraform state backend

**Tasks:**
1. Create MinIO namespace and resources:
   - Deployment with MinIO container
   - Persistent volume for state storage (10Gi)
   - Service exposing S3 API (port 9000) and web console (port 9001)
   - Ingress for S3 API at `minio.127.0.0.1.nip.io` (port 9000)
   - Ingress for web console at `minio-console.127.0.0.1.nip.io` (port 9001)

2. Initialize MinIO with:
   - Access key: `terraform`
   - Secret key: (generated)
   - Create bucket: `terraform-states`

3. Create Kubernetes secret with MinIO credentials for Atlantis

4. Configure MinIO for Terraform backend:
   - Enable versioning on bucket
   - Set up bucket policies

**Files to create:**
- `kubernetes/minio/namespace.yaml`
- `kubernetes/minio/deployment.yaml`
- `kubernetes/minio/service.yaml`
- `kubernetes/minio/ingress.yaml`
- `kubernetes/minio/persistent-volumes.yaml`
- `kubernetes/minio/init-job.yaml`
- `scripts/03-setup-minio.sh`

**Validation:**
- MinIO S3 API accessible at `http://minio.127.0.0.1.nip.io`
- MinIO web console accessible at `http://minio-console.127.0.0.1.nip.io`
- `terraform-states` bucket exists
- Can authenticate with credentials

**Backend Configuration:**

All Terraform configurations (both manual and Atlantis-managed) use the same MinIO endpoint via ingress:

```hcl
terraform {
  backend "s3" {
    endpoint                    = "http://minio.127.0.0.1.nip.io"
    bucket                      = "terraform-states"
    key                         = "platform/terraform.tfstate"
    region                      = "us-east-1"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
  }
}
```

**How this works:**
- **From your laptop:** `minio.127.0.0.1.nip.io` resolves to `127.0.0.1` via nip.io DNS → hits ingress on localhost → routes to MinIO
- **From Atlantis pods:** `hostAliases` (configured in deployment) makes `minio.127.0.0.1.nip.io` resolve to ingress controller ClusterIP → routes to MinIO

This allows using a single backend configuration that works in both contexts.

---

### Phase 4: GitLab Configuration

**Goal:** Configure GitLab with shared Atlantis user and Kubernetes namespace, then create platform repository

**Part A: Terraform-managed Shared Resources**

Create `atlantis-servers/shared/` Terraform configuration to manage:
- **GitLab resources** via GitLab provider:
  - Shared Atlantis service account user: `atlantis-bot`
  - Admin privileges for webhook creation
  - Personal access token with `api` scope
- **Kubernetes resources** via Kubernetes provider:
  - `atlantis` namespace (where all Atlantis servers will be deployed)
  - Kubernetes secret in `atlantis` namespace containing GitLab credentials

**Part B: GitLab Repository Creation**

Use GitLab API directly (NOT Terraform) to:
- Create GitLab repository `atlantis-demo` (top-level, no group)
- Push initial content from this local git repo

**Authentication Details:**

1. **For Terraform (GitLab provider):**
   - Requires GitLab root token with admin privileges
   - Set via environment variable: `export GITLAB_TOKEN=<root-token>`
   - Token obtained from GitLab UI or during GitLab setup (Phase 2)
   - Used to create `atlantis-bot` user and generate its token

2. **For Terraform (Kubernetes provider):**
   - Uses local kubeconfig (already configured via kubectl)
   - Needs permissions to create namespaces and secrets

3. **For GitLab API (repository creation):**
   - Uses same root token as Terraform: `GITLAB_TOKEN`
   - Makes direct API calls via curl/GitLab CLI
   - Creates the `atlantis-demo` repository

**Tasks:**

1. Set GitLab root token as environment variable:
   ```bash
   export GITLAB_TOKEN=$(kubectl get secret -n gitlab gitlab-root-token -o jsonpath='{.data.password}' | base64 -d)
   ```

2. Apply Terraform configuration manually (bootstrap step):
   ```bash
   cd atlantis-servers/shared
   terraform init
   terraform apply
   ```

3. Use GitLab API to create repository and push content:
   ```bash
   # Create repo via API
   curl --request POST "http://gitlab.127.0.0.1.nip.io/api/v4/projects" \
     --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
     --header "Content-Type: application/json" \
     --data '{
       "name": "atlantis-demo",
       "visibility": "internal"
     }'

   # Push this repo
   git remote add gitlab http://gitlab.127.0.0.1.nip.io/root/atlantis-demo.git
   git push gitlab main
   ```

**Files to create:**
- `atlantis-servers/shared/main.tf` (GitLab + Kubernetes resources)
- `atlantis-servers/shared/variables.tf`
- `atlantis-servers/shared/terraform.tfvars`
- `atlantis-servers/shared/backend.tf` (MinIO backend config)
- `atlantis-servers/shared/outputs.tf`
- `scripts/04-configure-gitlab.sh` (runs Terraform, then creates repo via API)

**Validation:**
- Can authenticate as `atlantis-bot` in GitLab UI
- `atlantis-demo` repository exists and is accessible
- `atlantis` namespace exists in Kubernetes
- GitLab token for `atlantis-bot` stored in Kubernetes secret in `atlantis` namespace
- Terraform state for shared resources stored in MinIO

**Note:** This repository IS the platform demo repo:
- Will contain `atlantis-servers/environments/platform/` - Platform Atlantis infrastructure
- Will contain `atlantis-servers/environments/system-*/` - System Atlantis infrastructure (managed by Platform Atlantis)
- Will have `atlantis.yaml` at root (created in Phase 6) - Configures Platform Atlantis workflow
- After Platform Atlantis is deployed, PRs to this repo will be managed by Platform Atlantis itself!

**Why Terraform for shared resources:**
- GitLab provider allows declarative management of users and tokens
- Kubernetes provider can create the `atlantis` namespace and secrets
- MinIO backend (from Phase 3) stores the state for these shared resources
- Demonstrates infrastructure-as-code from the beginning
- Makes the setup reproducible and version-controlled

**Why GitLab API for repository creation:**
- Repository creation is a one-time bootstrap operation
- Terraform GitLab provider can be complex for simple repo creation
- Direct API call is straightforward and easier to understand
- Separates concerns: Terraform manages persistent shared resources, API handles initial setup

---

### Phase 5: Atlantis Terraform Module

**Goal:** Create reusable Terraform module for deploying Atlantis servers

**Module Features:**
1. **Inputs:**
   - `instance_name` - Identifier for this Atlantis instance (e.g., "platform", "system-alpha")
   - `gitlab_hostname` - GitLab server address
   - `gitlab_user` - Shared GitLab username
   - `gitlab_token_secret` - Reference to K8s secret with token
   - `webhook_secret` - Secret for webhook validation
   - `repo_allowlist` - List of repos this Atlantis can manage
   - `atlantis_url` - External URL for this Atlantis instance
   - `namespace` - Kubernetes namespace where Atlantis runs (typically `atlantis`)
   - `target_namespaces` - List of namespaces this Atlantis can manage (for RBAC)
   - `resource_limits` - CPU/memory limits
   - `tf_backend_config` - MinIO/S3 backend configuration

2. **Resources Created:**
   - Kubernetes namespace (if not exists) - for Atlantis deployment
   - Target namespaces (if specified) - for system resources
   - Atlantis Deployment with:
     - MinIO credentials mounted
     - Kubernetes provider access (ServiceAccount)
     - **hostAliases** to make `minio.127.0.0.1.nip.io` resolve to ingress controller (enables same backend config as manual Terraform)
   - Service
   - Ingress
   - ConfigMap (server-side repo config)
   - Secrets (GitLab token, webhook secret, MinIO creds)
   - ServiceAccount in `atlantis` namespace
   - RBAC (Role/RoleBinding) for each target namespace

**RBAC Model:**
- Platform Atlantis: Can manage resources in `atlantis` namespace
- System Atlantis: Can manage resources in their designated target namespace only
  - Example: System-Alpha Atlantis runs in `atlantis` but can only create/modify resources in `system-alpha` namespace

3. **Outputs:**
   - `atlantis_url`
   - `webhook_url`
   - `namespace`

**Files to create:**
- `atlantis-servers/modules/atlantis-server/main.tf`
- `atlantis-servers/modules/atlantis-server/variables.tf`
- `atlantis-servers/modules/atlantis-server/outputs.tf`
- `atlantis-servers/modules/atlantis-server/templates/*.yaml.tpl`

**Key Implementation Details:**

The module must configure `hostAliases` in the Atlantis deployment to enable MinIO access via ingress:

```hcl
# In main.tf, query ingress controller service
data "kubernetes_service" "ingress_nginx" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = "ingress-nginx"
  }
}

# In deployment template (deployment.yaml.tpl)
spec:
  template:
    spec:
      hostAliases:
        - ip: "${ingress_controller_ip}"
          hostnames:
            - "minio.127.0.0.1.nip.io"
            - "gitlab.127.0.0.1.nip.io"  # May also need this for GitLab API access
```

This allows Atlantis pods to access MinIO and GitLab using the same ingress URLs that work from your laptop.

**Validation:**
- Module passes `terraform validate`
- Documentation is clear

---

### Phase 6: Platform Atlantis Deployment

**Goal:** Deploy the Platform Atlantis server using Terraform directly (bootstrap step)

**Platform Atlantis Configuration:**
- **Purpose:** Manages other Atlantis servers and platform infrastructure
- Namespace: `atlantis` (shared platform namespace for all Atlantis servers)
- Monitors: `atlantis-demo` (this repo in GitLab)
- Manages: `atlantis-servers/environments/*` (All Atlantis servers including itself)
- URL: `http://atlantis-platform.127.0.0.1.nip.io`
- State: Stored in MinIO at `atlantis-servers/platform/terraform.tfstate`
- **Access:** Only platform developers can access this namespace

**Tasks:**
1. Create platform Atlantis configuration in `atlantis-servers/environments/platform/`:
   - Use the atlantis-server module
   - Configure to watch this repository
   - Set repo allowlist to this repo
   - Configure MinIO backend

2. Apply Terraform manually (this is the bootstrap!):
   ```bash
   cd atlantis-servers/environments/platform
   terraform init
   terraform apply
   ```

3. Configure webhook in GitLab for this repository

4. Create `atlantis.yaml` at repo root to define Atlantis workflows for Platform:
   - Define projects for `atlantis-servers/environments/platform/` (Platform Atlantis itself)
   - Configure auto-plan on changes to relevant paths
   - Set up workflow requirements (e.g., approvals for production changes)

5. Commit and push platform configuration to GitLab

**Files to create:**
- `atlantis.yaml` (root level - Platform repo config)
- `atlantis-servers/environments/platform/main.tf`
- `atlantis-servers/environments/platform/variables.tf`
- `atlantis-servers/environments/platform/terraform.tfvars`
- `atlantis-servers/environments/platform/backend.tf`
- `scripts/05-deploy-platform-atlantis.sh`

**Example atlantis.yaml structure:**
```yaml
version: 3
projects:
  - name: platform-atlantis
    dir: atlantis-servers/environments/platform
    workspace: default
    autoplan:
      when_modified:
        - "*.tf"
        - "*.tfvars"
        - ../modules/atlantis-server/*.tf
        - ../modules/atlantis-server/templates/*.tpl
      enabled: true
```

**Validation:**
- Platform Atlantis UI accessible
- Webhook registered in GitLab for this repo
- Can create PR in this repo and see Atlantis respond
- Platform Atlantis can read `atlantis-servers/environments/` directory

**Key Concept:** This is the only Atlantis instance deployed manually with `terraform apply`. All subsequent Atlantis servers will be deployed via PRs to this repo, managed by Platform Atlantis.

---

### Phase 7: System Atlantis Deployments

**Goal:** Use Platform Atlantis to deploy system-specific Atlantis servers via PR workflow

**System-Alpha Atlantis Configuration:**
- Namespace: `atlantis` (same as platform - all Atlantis servers are platform components)
- Deployment name: `atlantis-system-alpha`
- Monitors: `system-alpha-infra` (GitLab repo)
- URL: `http://atlantis-alpha.127.0.0.1.nip.io`
- **Target namespace:** `system-alpha` (creates resources here via RBAC)
- ServiceAccount with Role/RoleBinding to manage `system-alpha` namespace only
- State: Stored in MinIO at `atlantis-servers/system-alpha/terraform.tfstate`

**System-Beta Atlantis Configuration:**
- Namespace: `atlantis` (same as platform - all Atlantis servers are platform components)
- Deployment name: `atlantis-system-beta`
- Monitors: `system-beta-infra` (GitLab repo)
- URL: `http://atlantis-beta.127.0.0.1.nip.io`
- **Target namespace:** `system-beta` (creates resources here via RBAC)
- ServiceAccount with Role/RoleBinding to manage `system-beta` namespace only
- State: Stored in MinIO at `atlantis-servers/system-beta/terraform.tfstate`

**Security Model:**
- System developers interact with Atlantis **only via GitLab PRs**
- System developers have **no access** to:
  - `atlantis` namespace (where Atlantis servers run)
  - `minio` namespace (where Terraform state is stored)
  - Terraform state files
- Only platform developers can access Atlantis infrastructure and state

**Tasks:**
1. Create Terraform configurations in `atlantis-servers/environments/`:
   - `atlantis-servers/environments/system-alpha/` - uses atlantis-server module
   - `atlantis-servers/environments/system-beta/` - uses atlantis-server module
   - Both configure MinIO backend

2. Create PR in this repo with system Atlantis configs

3. Platform Atlantis will:
   - Auto-plan showing the two new Atlantis deployments
   - Wait for `atlantis apply` comment
   - Deploy both system Atlantis servers

4. After apply, configure webhooks in GitLab for system repos

**Files to create:**
- `atlantis-servers/environments/system-alpha/main.tf`
- `atlantis-servers/environments/system-alpha/variables.tf`
- `atlantis-servers/environments/system-alpha/terraform.tfvars`
- `atlantis-servers/environments/system-alpha/backend.tf`
- `atlantis-servers/environments/system-beta/main.tf`
- `atlantis-servers/environments/system-beta/variables.tf`
- `atlantis-servers/environments/system-beta/terraform.tfvars`
- `atlantis-servers/environments/system-beta/backend.tf`

**Validation:**
- Both system Atlantis UIs accessible
- Webhooks registered in GitLab for system repos
- Each system Atlantis shows connected to its repository
- State files visible in MinIO console

**Demo Value:** This phase demonstrates the core value proposition - using Atlantis to manage Atlantis itself!

---

### Phase 8: Demo Repositories Setup

**Goal:** Create sample Terraform configurations in system repos for demonstrating Atlantis workflows

**Demo Infrastructure (Kubernetes-native, no cloud required):**
- ConfigMaps
- Secrets
- ServiceAccounts
- RBAC (Roles, RoleBindings)
- Resource Quotas
- Network Policies

**Repository Structure:**
Each system repo (`system-alpha-infra`, `system-beta-infra`) will have:
- `atlantis.yaml` - Project configuration
- Multiple environments (dev/prod) in subdirectories
- Terraform configs using Kubernetes provider
- MinIO backend configuration

**Atlantis.yaml Features to Demo:**
- Multiple projects in one repo (dev/prod environments)
- Workspace separation
- Custom workflows
- Plan requirements (approvals)
- Auto-plan on specific paths

**Tasks:**
1. Create demo repository content locally
2. Push to GitLab repos created in Phase 3
3. System Atlantis instances (deployed in Phase 7) will detect the repos

**Files to create:**
- `demo-repos/system-alpha-infra/*`
- `demo-repos/system-beta-infra/*`
- `scripts/06-create-demo-repos.sh`

**Validation:**
- Repos pushed to GitLab
- System Atlantis instances detect repo configuration
- Can create test PR and see auto-plan

---

### Phase 9: Demo Workflow Script

**Goal:** Create guided demo script showing the complete Atlantis bootstrap pattern and features

**Demo Scenarios:**

1. **Bootstrap Flow (The "Atlantis manages Atlantis" demo):**
   - Show Platform Atlantis running
   - Create PR to add a new system Atlantis in `atlantis-servers/environments/system-gamma/`
   - Platform Atlantis auto-plans the new Atlantis deployment
   - Comment `atlantis apply` to deploy system-gamma Atlantis
   - Show new Atlantis instance running and monitoring `system-gamma-infra` repo

2. **Basic Plan/Apply Flow:**
   - Create branch in system-alpha-infra repo
   - Add new ConfigMap resource
   - Push and create MR
   - Show system-alpha Atlantis auto-plan comment
   - Comment `atlantis apply`
   - Show resource created in cluster

3. **Multi-Environment:**
   - Change both dev and prod tfvars in system-beta-infra
   - Show separate plans for each environment
   - Apply dev first, then prod with selective `atlantis apply -p dev`

4. **System Isolation:**
   - Show system-alpha Atlantis can't affect system-beta namespace
   - Demonstrate RBAC boundaries via Terraform plan failure
   - Try to create resource in wrong namespace (should fail with permission error)
   - Show that system developers have no access to:
     - Atlantis pods/logs (in `atlantis` namespace)
     - MinIO console or state files
     - Other system's namespaces

5. **Approval Workflow:**
   - Configure require-approval in atlantis.yaml
   - Show apply blocked until MR approved
   - Approve MR, then apply

6. **Locking:**
   - Start apply in one MR
   - Show second MR is locked for same project
   - Demonstrate `atlantis unlock`

7. **State Management:**
   - Show MinIO console with all state files
   - Demonstrate state isolation between systems
   - Show Platform, System-Alpha, and System-Beta states

**Files to create:**
- `scripts/demo-workflow.sh`
- `README.md` (comprehensive setup and demo instructions)

---

## Technical Decisions

### Why GitLab CE vs alternatives:

| Option | Pros | Cons |
|--------|------|------|
| **GitLab CE** | Full-featured, real webhooks, MR UI | Heavy resource usage (~4GB RAM) |
| Gitea | Lightweight, fast | Less polished, fewer features |
| Gogs | Very lightweight | Limited webhook support |

**Recommendation:** GitLab CE - most realistic demo, best Atlantis integration

### Faking Cloud Accounts:

Instead of actual cloud providers, use:
1. **Kubernetes Provider** - Real infrastructure, no cloud needed
2. **Namespaces as "accounts"** - Each system's namespace simulates their cloud account
3. **RBAC** - ServiceAccounts with namespace-scoped permissions simulate IAM

**Namespace Architecture:**
- `gitlab` - GitLab server (platform component)
- `minio` - MinIO state storage (platform component)
- `atlantis` - All Atlantis servers (platform component, only platform developers have access)
- `system-alpha` - System Alpha resources (managed by System-Alpha Atlantis)
- `system-beta` - System Beta resources (managed by System-Beta Atlantis)

**Security Boundaries:**
- **Platform developers:** Full access to platform namespaces (gitlab, minio, atlantis)
- **System developers:** Only interact via GitLab PRs, no direct access to infrastructure
- **Atlantis ServiceAccounts:** Scoped RBAC to their designated target namespaces

### State Management:

**MinIO (S3-compatible backend)**
- ✅ Realistic production pattern (mimics AWS S3)
- ✅ Centralized state storage in Kubernetes
- ✅ Proper state locking support
- ✅ Easy to inspect via web console
- ✅ Multiple Atlantis instances can share the backend
- ⚠️ Slightly more setup than local backend

**Why not alternatives:**
- **Local backend** - State lost on pod restart, no visibility
- **HTTP backend** - Less common, basic locking
- **Kubernetes backend** - Stores state as secrets, limited tooling

**Implementation:**
- Single MinIO instance in `minio` namespace
- Bucket: `terraform-states`
- State files organized by path:
  - `platform/terraform.tfstate` - Platform Atlantis
  - `systems/system-alpha/terraform.tfstate` - System Alpha Atlantis
  - `systems/system-beta/terraform.tfstate` - System Beta Atlantis
  - System repos also use same MinIO with their own prefixes

### Security & Access Control:

**All Atlantis servers run in the `atlantis` namespace** - This is a critical design decision:

**Why a dedicated `atlantis` namespace:**
- ✅ Atlantis servers are platform components, not system components
- ✅ System developers should not have access to Atlantis infrastructure
- ✅ System developers should not have access to Terraform state
- ✅ Clear separation between platform (infra) and systems (applications)
- ✅ Demonstrates realistic enterprise security boundaries

**Access Model:**
```
Platform Developers → Full access to platform namespaces
                      (gitlab, minio, atlantis)

System Developers   → GitLab PRs only
                      NO access to: atlantis NS, minio NS, TF state

Atlantis Servers    → ServiceAccount + RBAC
                      Can manage designated target namespaces only
```

**RBAC Implementation:**
- Platform Atlantis ServiceAccount: Can create/modify resources in `atlantis` namespace
- System-Alpha Atlantis ServiceAccount: Can create/modify resources in `system-alpha` namespace only
- System-Beta Atlantis ServiceAccount: Can create/modify resources in `system-beta` namespace only

**Demo Value:** This models real-world platform engineering where platform teams manage shared infrastructure (Atlantis, state storage) and system teams only interact through controlled interfaces (PRs).

---

## Prerequisites

Before starting implementation:

```bash
# Required tools
- docker (with sufficient resources: 8GB RAM recommended)
- kind
- kubectl
- helm
- terraform >= 1.0
- git
- curl/jq (for API scripts)

# Recommended
- k9s (for cluster visualization)
```

---

## Resource Requirements

| Component | CPU Request | Memory Request | Storage |
|-----------|-------------|----------------|---------|
| GitLab CE | 500m | 3Gi | 10Gi |
| MinIO | 100m | 512Mi | 10Gi |
| Platform Atlantis | 100m | 256Mi | 1Gi |
| System Atlantis (each x2) | 100m | 256Mi | 1Gi each |
| Ingress Controller | 100m | 128Mi | - |
| **Total** | ~1.3 CPU | ~4.5Gi | ~23Gi |

**Note:** These are minimum requirements. For comfortable demo experience with GitLab, allocate at least 8GB RAM to Docker.

---

## Estimated Implementation Time

| Phase | Time Estimate |
|-------|---------------|
| Phase 1: Kind Setup | 30 min |
| Phase 2: GitLab Deploy | 1 hour |
| Phase 3: MinIO Setup | 45 min |
| Phase 4: GitLab Config (Terraform) | 1 hour |
| Phase 5: Atlantis Module | 2 hours |
| Phase 6: Platform Atlantis | 1 hour |
| Phase 7: System Atlantis | 1 hour |
| Phase 8: Demo Repos | 1 hour |
| Phase 9: Demo Script | 1.5 hours |
| **Total** | ~9.5-10.5 hours |

---

## Success Criteria

The demo is complete when:

1.  ✅ Single command sets up entire environment (GitLab + MinIO + Platform Atlantis)
2.  ✅ Platform Atlantis running and managing this repository
3.  ✅ Three Atlantis servers total: Platform, System-Alpha, System-Beta
4.  ✅ All Atlantis instances use shared GitLab service account (`atlantis-bot`)
5.  ✅ All Terraform state stored centrally in MinIO
6.  ✅ **Bootstrap demo works:** Can deploy new Atlantis via PR to platform repo
7.  ✅ Creating MR in system repos triggers automatic `terraform plan`
8.  ✅ `atlantis apply` comment deploys resources to correct namespace
9.  ✅ Systems cannot affect each other's namespaces (RBAC isolation)
10. ✅ Can view all state files in MinIO console
11. ✅ Demo workflow script walks through bootstrap + features
12. ✅ Cleanup script removes everything

**Key Demo Value:** The platform uses Atlantis to manage Atlantis itself - demonstrating infrastructure-as-code at the platform level.

---

## Next Steps

Begin implementation with Phase 1. Each phase builds on the previous, so complete them in order. The scripts should be idempotent where possible to allow re-running during development.
