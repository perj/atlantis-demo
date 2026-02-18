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
│  3. Deploy System Atlantis servers to atlantis namespace (via MRs)       │
│                                                                          │
│  Security Model:                                                         │
│  - Platform developers: Access to atlantis, minio, gitlab namespaces     │
│  - System developers: Only interact via GitLab MRs, no infra access      │
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
- Only platform Atlantis is deployed manually; system Atlantis via MRs

```
atlantis-demo/
├── README.md
├── atlantis.yaml                    # Platform repo Atlantis config
├── scripts/
│   ├── 01-setup-kind.sh
│   ├── 02-setup-gitlab.sh
│   ├── 03-setup-minio.sh
│   ├── 04-create-repo.sh
│   ├── 05-configure-shared-resources.sh
│   ├── 06-deploy-platform-atlantis.sh
│   ├── 07-create-demo-repos.sh
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
│       ├── variables.tf
│       ├── terraform.tfvars
│       ├── backend.tf
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

3. Configure CoreDNS to resolve `*.127.0.0.1.nip.io` to the ingress controller ClusterIP
   - Adds a `rewrite` rule to the CoreDNS ConfigMap so all pods in the cluster can reach ingress-backed services (MinIO, GitLab) without per-deployment `hostAliases`

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
- **From pods in the cluster:** CoreDNS rewrites `*.127.0.0.1.nip.io` queries to resolve to the ingress-nginx-controller ClusterIP (configured in Phase 1) → routes to MinIO via ingress

This allows using a single backend configuration that works in both contexts, with no per-deployment configuration needed.

---

### Phase 4: GitLab Repository Creation

**Goal:** Create the platform repository in GitLab and push initial content

**Tasks:**

1. Use GitLab API to create `atlantis-demo` repository (top-level, no group)

2. Push this local git repo to the new GitLab repository

**Authentication:**
- Uses GitLab root token from Phase 2
- Set via environment variable: `export GITLAB_TOKEN=<root-token>`
- Can be retrieved from Kubernetes secret created in Phase 2

**Files to create:**
- `scripts/04-create-repo.sh` (creates repo via API and pushes content)

**Script tasks:**
```bash
# 1. Get GitLab root token
export GITLAB_TOKEN=$(kubectl get secret -n gitlab gitlab-root-token -o jsonpath='{.data.password}' | base64 -d)

# 2. Create repo via API
curl --request POST "http://gitlab.127.0.0.1.nip.io/api/v4/projects" \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  --header "Content-Type: application/json" \
  --data '{
    "name": "atlantis-demo",
    "visibility": "internal"
  }'

# 3. Push this repo
git remote add gitlab http://root:${GITLAB_TOKEN}@gitlab.127.0.0.1.nip.io/root/atlantis-demo.git
git push gitlab main
```

**Validation:**
- `atlantis-demo` repository exists in GitLab
- Repository contains all current files from local repo
- Can access repository via GitLab UI

**Note:** This repository IS the platform demo repo. In subsequent phases we'll add:
- `atlantis-servers/shared/` - Terraform for shared resources
- `atlantis-servers/environments/platform/` - Platform Atlantis infrastructure
- `atlantis-servers/environments/system-*/` - System Atlantis infrastructure
- `atlantis.yaml` at root - Configures Platform Atlantis workflow

---

### Phase 5: Shared Resources Configuration

**Goal:** Create Terraform configuration for shared resources (GitLab user, Kubernetes namespace) and root atlantis.yaml

**Tasks:**

1. Create `atlantis-servers/shared/` Terraform configuration to manage:
   - **Kubernetes resources** via Kubernetes provider:
     - `atlantis` namespace (where all Atlantis servers will be deployed)
     - Kubernetes secret in `atlantis` namespace containing GitLab credentials
     - Used to fetch Gitlab root token for GitLab provider
   - **GitLab resources** via GitLab provider:
     - Shared Atlantis service account user: `atlantis-bot`
     - Personal access token with `api` scope

2. Create root `atlantis.yaml` defining project for `atlantis-servers/shared/`:
   - This allows Platform Atlantis (once deployed) to manage shared resources via MRs
   - For now, we'll apply manually, but later updates will go through Atlantis

3. Apply Terraform configuration manually (bootstrap step)

**Authentication:**

1. **For Terraform (GitLab provider):**
   - Requires GitLab root token with admin privileges
   - Fetched from Kubernetes secret
   - Used to create `atlantis-bot` user and generate its token

2. **For Terraform (Kubernetes provider):**
   - Uses local kubeconfig (already configured via kubectl)
   - Needs permissions to create namespaces and secrets

**Files to create:**
- `atlantis-servers/shared/main.tf` (GitLab + Kubernetes resources)
- `atlantis-servers/shared/variables.tf`
- `atlantis-servers/shared/terraform.tfvars`
- `atlantis-servers/shared/backend.tf` (MinIO backend config)
- `atlantis-servers/shared/outputs.tf`
- `atlantis.yaml` (root level - includes project for shared resources)
- `scripts/05-configure-shared-resources.sh` (runs Terraform apply)

**Example atlantis.yaml structure:**
```yaml
version: 3
projects:
  - name: shared-resources
    dir: atlantis-servers/shared
    workspace: default
    autoplan:
      when_modified:
        - "*.tf"
        - "*.tfvars"
      enabled: true
```

**Script tasks:**
```bash
# 1. Initialize and apply Terraform
cd atlantis-servers/shared
terraform init
terraform apply
```

**Validation:**
- Can authenticate as `atlantis-bot` in GitLab UI
- `atlantis` namespace exists in Kubernetes
- GitLab token for `atlantis-bot` stored in Kubernetes secret in `atlantis` namespace
- Terraform state for shared resources stored in MinIO
- `atlantis.yaml` exists at root of repository

**Why Terraform for shared resources:**
- GitLab provider allows declarative management of users and tokens
- Kubernetes provider can create the `atlantis` namespace and secrets
- MinIO backend (from Phase 3) stores the state for these shared resources
- Demonstrates infrastructure-as-code from the beginning
- Makes the setup reproducible and version-controlled

**Why create atlantis.yaml now:**
- Once Platform Atlantis is deployed, it can manage updates to shared resources via MRs
- Demonstrates that Platform Atlantis will manage its own infrastructure
- Initial apply is manual (bootstrap), but subsequent changes go through Atlantis workflow

---

### Phase 6: Atlantis Terraform Module

**Goal:** Create reusable Terraform module for deploying Atlantis servers

**Module Features:**
1. **Inputs:**
   - `instance_name` - Identifier for this Atlantis instance (e.g., "platform", "system-alpha")
   - `gitlab_hostname` - GitLab server address
   - `gitlab_user` - Shared GitLab username
   - `gitlab_token_secret` - Reference to K8s secret with token
   - `webhook_secret` - Secret for webhook validation
   - `repo_allowlist` - List of repos this Atlantis can manage
   - `atlantis_host` - External host for this Atlantis instance
   - `namespace` - Kubernetes namespace where Atlantis runs (typically `atlantis`)
   - `target_namespaces` - List of namespaces this Atlantis can manage (for RBAC)
   - `resource_limits` - CPU/memory limits
   - `tf_backend_config` - MinIO/S3 backend configuration

2. **Resources Created:**
   - Target namespaces (if specified) - for system resources
   - Atlantis Deployment with:
     - MinIO credentials mounted
     - Kubernetes provider access (ServiceAccount)
     - **Init container** to create `~/.kube/config` using in-cluster service account (required for shared resources Terraform)
     - DNS resolution for `*.127.0.0.1.nip.io` is handled cluster-wide by CoreDNS (configured in Phase 1), so no per-deployment `hostAliases` needed
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
   - `atlantis_host`
   - `webhook_url`
   - `namespace`

**Files to create:**
- `atlantis-servers/modules/atlantis-server/main.tf`
- `atlantis-servers/modules/atlantis-server/variables.tf`
- `atlantis-servers/modules/atlantis-server/outputs.tf`
- `atlantis-servers/modules/atlantis-server/templates/*.yaml.tpl`

**Key Implementation Details:**

**1. Kubeconfig Setup for Terraform:**
The shared resources Terraform configuration expects `~/.kube/config` to exist. For Atlantis running in-cluster, we need an init container to create this:

```yaml
# In deployment template
initContainers:
  - name: setup-kubeconfig
    image: bitnami/kubectl:latest
    command:
      - sh
      - -c
      - |
        mkdir -p /home/atlantis/.kube
        kubectl config set-cluster in-cluster \
          --server=https://kubernetes.default.svc \
          --certificate-authority=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        kubectl config set-credentials atlantis \
          --token=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
        kubectl config set-context kind-atlantis-demo \
          --cluster=in-cluster \
          --user=atlantis
        kubectl config use-context kind-atlantis-demo
    volumeMounts:
      - name: atlantis-data
        mountPath: /home/atlantis
```

This creates a kubeconfig that uses the pod's service account, matching the `kind-atlantis-demo` context expected by the Terraform configuration.

**2. DNS Resolution for Ingress Access (handled by CoreDNS):**
No per-deployment configuration is needed. The CoreDNS `rewrite` rule configured in Phase 1 resolves `*.127.0.0.1.nip.io` to the ingress-nginx-controller ClusterIP for all pods in the cluster. This means the Atlantis module does **not** need:
- A `kubernetes_service` data source for the ingress controller
- `hostAliases` in the deployment template
- Any knowledge of the ingress controller IP

Atlantis pods can access `minio.127.0.0.1.nip.io` and `gitlab.127.0.0.1.nip.io` out of the box, using the same URLs that work from your laptop.

**Validation:**
- Module passes `terraform validate`
- Documentation is clear

---

### Phase 7: Platform Atlantis Deployment

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

2. Update `atlantis.yaml` at repo root to add Platform Atlantis project:
   - Add project for `atlantis-servers/environments/platform/`
   - Configure auto-plan on changes to relevant paths
   - (The atlantis.yaml was created in Phase 5 with the shared-resources project)

3. Apply Terraform manually (this is the bootstrap!):
   ```bash
   cd atlantis-servers/environments/platform
   terraform init
   terraform apply
   ```

4. Configure webhook in GitLab for this repository

5. Commit and push platform configuration to GitLab

**Files to create:**
- `atlantis-servers/environments/platform/main.tf`
- `atlantis-servers/environments/platform/variables.tf`
- `atlantis-servers/environments/platform/terraform.tfvars`
- `atlantis-servers/environments/platform/backend.tf`
- `scripts/07-deploy-platform-atlantis.sh`

**Updated atlantis.yaml structure (includes shared and platform projects):**
```yaml
version: 3
projects:
  - name: shared-resources
    dir: atlantis-servers/shared
    workspace: default
    autoplan:
      when_modified:
        - "*.tf"
        - "*.tfvars"
      enabled: true

  - name: platform-atlantis
    dir: atlantis-servers/environments/platform
    workspace: default
    autoplan:
      when_modified:
        - "*.tf"
        - "*.tfvars"
        - ../../modules/atlantis-server/**/*.tf
        - ../../modules/atlantis-server/templates/*.tpl
      enabled: true
```

**Note:** System Atlantis projects (system-alpha, system-beta) are added to atlantis.yaml in Phase 8 when the MR is created.

**Validation:**
- Platform Atlantis UI accessible
- Webhook registered in GitLab for this repo
- Can create MR in this repo and see Atlantis respond
- Platform Atlantis can read `atlantis-servers/environments/` directory

**Key Concept:** This is the only Atlantis instance deployed manually with `terraform apply`. All subsequent Atlantis servers will be deployed via MRs to this repo, managed by Platform Atlantis.

---

### Phase 8: System Atlantis Deployments

**Goal:** Use Platform Atlantis to deploy system-specific Atlantis servers via MR workflow

**System-Alpha Atlantis Configuration (Auto-Detect Projects):**
- Deployment name: `atlantis-system-alpha`
- Monitors: `system-alpha-infra` (GitLab repo)
- URL: `http://atlantis-alpha.127.0.0.1.nip.io`
- **Target namespace:** `system-alpha` (creates resources here via RBAC)
- ServiceAccount with Role/RoleBinding to manage `system-alpha` namespace only
- State: Stored in MinIO at `atlantis-servers/system-alpha/terraform.tfstate`
- **Atlantis feature:** Auto-detect projects — no `atlantis.yaml` in the repo. Atlantis automatically discovers directories containing `.tf` files and creates projects from them.

**System-Beta Atlantis Configuration (Workspace-Based Environments):**
- Deployment name: `atlantis-system-beta`
- Monitors: `system-beta-infra` (GitLab repo)
- URL: `http://atlantis-beta.127.0.0.1.nip.io`
- **Target namespace:** `system-beta` (creates resources here via RBAC)
- ServiceAccount with Role/RoleBinding to manage `system-beta` namespace only
- State: Stored in MinIO at `atlantis-servers/system-beta/terraform.tfstate`
- **Atlantis feature:** Workspace separation — single Terraform directory with an `atlantis.yaml` that defines `dev` and `prod` projects using different workspaces with environment config via workspace-based locals.

**Security Model:**
- App developers interact with Atlantis **only via GitLab MRs**
- App developers have **no access** to:
  - `atlantis` namespace (where Atlantis servers run)
  - `minio` namespace (where Terraform state is stored)
  - Terraform state files
- Only platform developers can access Atlantis infrastructure and state

**Tasks:**
1. Create Terraform configurations in `atlantis-servers/environments/`:
   - `atlantis-servers/environments/system-alpha/` - uses atlantis-server module
   - `atlantis-servers/environments/system-beta/` - uses atlantis-server module
   - Both configure MinIO backend

2. **Script creates MR** via GitLab API and handles re-runs gracefully:
   - If system configs don't exist on main: Create them fresh
   - If they already exist (re-running demo): Add a timestamp label to trigger a diff
   - Ensures there's always a meaningful change for Atlantis to plan

3. Platform Atlantis will:
   - Auto-plan showing the two new/updated Atlantis deployments
   - Wait for `atlantis apply` comment
   - Deploy both system Atlantis servers

4. After apply, configure webhooks in GitLab for system repos

**Files to create/modify:**
- `atlantis-servers/environments/system-alpha/main.tf`
- `atlantis-servers/environments/system-alpha/variables.tf`
- `atlantis-servers/environments/system-alpha/terraform.tfvars`
- `atlantis-servers/environments/system-alpha/backend.tf`
- `atlantis-servers/environments/system-beta/main.tf`
- `atlantis-servers/environments/system-beta/variables.tf`
- `atlantis-servers/environments/system-beta/terraform.tfvars`
- `atlantis-servers/environments/system-beta/backend.tf`
- `atlantis.yaml` - Add system-alpha and system-beta projects
- `scripts/08-deploy-systems-atlantis.sh` - Creates MR via API

**Updated atlantis.yaml (adds system projects):**
```yaml
version: 3
projects:
  - name: shared-resources
    dir: atlantis-servers/shared
    workspace: default
    autoplan:
      when_modified: ["*.tf", "*.tfvars"]
      enabled: true

  - name: platform-atlantis
    dir: atlantis-servers/environments/platform
    workspace: default
    autoplan:
      when_modified:
        - "*.tf"
        - "*.tfvars"
        - ../../modules/atlantis-server/**/*.tf
        - ../../modules/atlantis-server/templates/*.tpl
      enabled: true

  - name: system-alpha-atlantis
    dir: atlantis-servers/environments/system-alpha
    workspace: default
    autoplan:
      when_modified:
        - "*.tf"
        - "*.tfvars"
        - ../../modules/atlantis-server/**/*.tf
        - ../../modules/atlantis-server/templates/*.tpl
      enabled: true

  - name: system-beta-atlantis
    dir: atlantis-servers/environments/system-beta
    workspace: default
    autoplan:
      when_modified:
        - "*.tf"
        - "*.tfvars"
        - ../../modules/atlantis-server/**/*.tf
        - ../../modules/atlantis-server/templates/*.tpl
      enabled: true
```

**Script behavior (handles re-runs):**
```bash
# Script flow:
1. Check if system-alpha/beta configs exist on main branch
2. If new:
   - Create fresh configs in local branch
   - Add system projects to atlantis.yaml
3. If existing (re-run):
   - Checkout main, create new branch
   - Update terraform.tfvars with new demo_run_timestamp variable
   - This creates a harmless diff that triggers Atlantis auto-plan
4. Push branch and create MR via GitLab API
5. Output example:
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ✅ Merge Request Created Successfully!
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   📋 MR Details:
      Title: Add System Atlantis Servers
      URL: http://gitlab.127.0.0.1.nip.io/root/atlantis-demo/-/merge_requests/1

   🤖 Platform Atlantis will auto-plan in ~30 seconds:
      Monitor: http://atlantis-platform.127.0.0.1.nip.io

   📝 Next Steps:
      1. View auto-plan in MR comments
      2. Review the plan shows 2 new Atlantis deployments
      3. Comment "atlantis apply" to deploy

   🎯 After apply, system Atlantis servers will be available at:
      • System Alpha: http://atlantis-alpha.127.0.0.1.nip.io
      • System Beta:  http://atlantis-beta.127.0.0.1.nip.io
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Re-run strategy:**
- Each terraform.tfvars includes a `demo_run_timestamp` variable (used as a label)
- On re-runs, script updates this timestamp to create a diff
- Atlantis auto-plans the change (label update is harmless but triggers plan)
- Demonstrates Atlantis workflow even when infrastructure already exists

**Validation:**
- Both system Atlantis UIs accessible
- Webhooks registered in GitLab for system repos
- Each system Atlantis shows connected to its repository
- State files visible in MinIO console
- Re-running script creates new MR with updated timestamp

**Demo Value:** This phase demonstrates the core value proposition — using Atlantis to manage Atlantis itself!

---

### Phase 9: Demo Repositories Setup

**Goal:** Create sample Terraform configurations in system repos that showcase two different Atlantis project management patterns

**Demo Infrastructure (Kubernetes-native, no cloud required):**
- ConfigMaps
- Secrets
- ServiceAccounts
- RBAC (Roles, RoleBindings)
- Resource Quotas
- Network Policies

**System-Alpha: Auto-Detect Projects Pattern**

The `system-alpha-infra` repo has **no `atlantis.yaml`**. Instead, it uses separate directories for each environment. Atlantis auto-discovers them:

```
system-alpha-infra/
├── dev/
│   ├── main.tf           # K8s resources with "dev-" prefix in system-alpha namespace
│   ├── variables.tf
│   └── backend.tf        # MinIO state key: system-alpha-infra/dev/terraform.tfstate
└── prod/
    ├── main.tf           # K8s resources with "prod-" prefix in system-alpha namespace
    ├── variables.tf
    └── backend.tf        # MinIO state key: system-alpha-infra/prod/terraform.tfstate
```

- No repo-side config — Atlantis detects `dev/` and `prod/` as separate projects automatically
- A MR touching `dev/main.tf` only plans the `dev` project; touching both plans both
- Shows the simplest possible onboarding: just add `.tf` files and Atlantis handles the rest

**System-Beta: Workspace-Based Environments Pattern**

The `system-beta-infra` repo uses a single Terraform directory with an `atlantis.yaml` that defines two projects pointing to the same code but using different workspaces. Environment-specific configuration is handled via workspace-based locals:

```
system-beta-infra/
├── atlantis.yaml         # Defines dev & prod projects with workspace separation
├── main.tf               # Shared K8s resources with workspace-based config maps
├── variables.tf
└── backend.tf            # Workspace-aware state key: system-beta-infra/${workspace}/terraform.tfstate
```

`main.tf` (snippet showing workspace-based configuration):
```hcl
locals {
  config = {
    dev = {
      replica_count   = 1
    }
    prod = {
      replica_count   = 3
    }
  }[terraform.workspace]
}

resource "kubernetes_config_map" "app" {
  metadata {
    name      = "${terraform.workspace}-app-config"
    namespace = "system-beta"
  }
  data = {
    replicas = local.config.replica_count
  }
}
```

`atlantis.yaml`:
```yaml
version: 3
projects:
  - name: dev
    dir: .
    workspace: dev
    autoplan:
      when_modified: ["*.tf"]
      enabled: true
    terraform_version: v1.14.x
  - name: prod
    dir: .
    workspace: prod
    autoplan:
      when_modified: ["*.tf"]
      enabled: true
    terraform_version: v1.14.x
```

- Same Terraform code, environment config via workspace-based locals
- Any `.tf` file change triggers plans for both `dev` and `prod` projects (shared code)
- Selective apply: `atlantis apply -p dev` or `atlantis apply -p prod`
- Shows how teams can share code across environments with workspace isolation

**Atlantis Features Demonstrated Across Both Repos:**

| Feature | System-Alpha | System-Beta |
|---------|-------------|-------------|
| Project discovery | Auto-detect (no config) | Explicit `atlantis.yaml` |
| Environment separation | Separate directories | Terraform workspaces |
| Auto-plan trigger | Per-directory changes | Per-code changes (any `.tf` file) |
| Selective apply | `atlantis apply -d dev` | `atlantis apply -p dev` |
| State isolation | Separate state keys per dir | Separate state keys per workspace |

**GitLab Users and Approval Rules:**

For the demo we use two GitLab users with distinct roles:

| User | Role | Can push/create MR | Can approve MR |
|------|------|---------------------|----------------|
| `developer` | Developer | Yes | No |
| `root` | Owner/Maintainer | Yes | Yes |

The `developer` user is created in the Phase 9 script. Each system repo is configured with:
- `developer` added as a **Developer** member
- Approval rule requiring 1 approval
- "Prevent approval by author" enabled — so `developer` cannot approve their own MRs
- `root` acts as the approver (already exists as project owner)

This enables the approval workflow demo: `developer` creates the MR, Atlantis auto-plans, but `atlantis apply` is blocked until `root` approves.

**Tasks:**
1. Create `developer` GitLab user (via API)
2. Create demo repository content locally
3. Push to GitLab repos (created via API similar to Phase 4)
4. Add `developer` as a member of each repo
5. Configure approval rules on each repo
6. System Atlantis instances (deployed in Phase 8) will detect the repos

**Files to create:**
- `demo-repos/system-alpha-infra/dev/main.tf`
- `demo-repos/system-alpha-infra/dev/variables.tf`
- `demo-repos/system-alpha-infra/dev/backend.tf`
- `demo-repos/system-alpha-infra/prod/main.tf`
- `demo-repos/system-alpha-infra/prod/variables.tf`
- `demo-repos/system-alpha-infra/prod/backend.tf`
- `demo-repos/system-beta-infra/atlantis.yaml`
- `demo-repos/system-beta-infra/main.tf`
- `demo-repos/system-beta-infra/variables.tf`
- `demo-repos/system-beta-infra/backend.tf`
- `scripts/09-create-demo-repos.sh`

**Validation:**
- `developer` user exists in GitLab and can log in
- Repos pushed to GitLab with `developer` as a member
- Approval rules configured on both repos
- System-Alpha Atlantis auto-discovers `dev` and `prod` projects (no atlantis.yaml needed)
- System-Beta Atlantis shows `dev` and `prod` workspace projects from its `atlantis.yaml`
- Can create test MR as `developer` and see auto-plan for both patterns

---

### Phase 10: Demo Workflow Script

**Goal:** Create guided demo script showing the complete Atlantis bootstrap pattern and features

**Demo Scenarios:**

1. **Bootstrap Flow (The "Atlantis manages Atlantis" demo):**
   - Show Platform Atlantis running
   - Create PR to add a new system Atlantis in `atlantis-servers/environments/system-gamma/`
   - Platform Atlantis auto-plans the new Atlantis deployment
   - Comment `atlantis apply` to deploy system-gamma Atlantis
   - Show new Atlantis instance running and monitoring `system-gamma-infra` repo

2. **Auto-Detect Projects (system-alpha-infra):**
   - Create branch in system-alpha-infra repo
   - Add a new ConfigMap in `dev/main.tf`
   - Push and create MR
   - Show Atlantis auto-discovers `dev` as a project and plans it (no atlantis.yaml!)
   - Comment `atlantis apply -d dev`
   - Show resource created in cluster
   - Then modify both `dev/` and `prod/` — show Atlantis plans both projects automatically

3. **Workspace Environments (system-beta-infra):**
   - Modify `main.tf` in system-beta-infra (shared code affects both workspaces)
   - Show Atlantis creates separate plans for `dev` and `prod` workspace projects
   - Each plan uses workspace-specific config from locals (different replica counts, prefixes)
   - Apply selectively: `atlantis apply -p dev` first, then `atlantis apply -p prod`
   - Demonstrates how single codebase can manage multiple environments with workspace isolation

4. **System Isolation:**
   - Show system-alpha Atlantis can't affect system-beta namespace
   - Demonstrate RBAC boundaries via Terraform plan failure
   - Try to create resource in wrong namespace (should fail with permission error)
   - Show that system developers have no access to:
     - Atlantis pods/logs (in `atlantis` namespace)
     - MinIO console or state files
     - Other system's namespaces

5. **Approval Workflow:**
   - `developer` creates MR with infrastructure change
   - Atlantis auto-plans, but apply is blocked (requires approval)
   - Show `atlantis apply` comment rejected — MR not yet approved
   - `root` reviews and approves the MR
   - `developer` comments `atlantis apply` — now succeeds
   - Demonstrates separation of duties: committer ≠ approver

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

System Developers   → GitLab MRs only
                      NO access to: atlantis NS, minio NS, TF state

Atlantis Servers    → ServiceAccount + RBAC
                      Can manage designated target namespaces only
```

**RBAC Implementation:**
- Platform Atlantis ServiceAccount: Can create/modify resources in all namespace
- System-Alpha Atlantis ServiceAccount: Can create/modify resources in `system-alpha` namespace only
- System-Beta Atlantis ServiceAccount: Can create/modify resources in `system-beta` namespace only

**Demo Value:** This models real-world platform engineering where platform teams manage shared infrastructure (Atlantis, state storage) and system teams only interact through controlled interfaces (MRs).

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
| GitLab CE | 500m | 4Gi | 10Gi |
| MinIO | 100m | 512Mi | 10Gi |
| Platform Atlantis | 100m | 256Mi | 1Gi |
| System Atlantis (each x2) | 100m | 256Mi | 1Gi each |
| Ingress Controller | 100m | 128Mi | - |
| **Total** | ~1.3 CPU | ~5.5Gi | ~23Gi |

**Note:** These are minimum requirements. For comfortable demo experience with GitLab, allocate at least 8GB RAM to Docker.

---

## Estimated Implementation Time

| Phase | Time Estimate |
|-------|---------------|
| Phase 1: Kind Setup | 30 min |
| Phase 2: GitLab Deploy | 1 hour |
| Phase 3: MinIO Setup | 45 min |
| Phase 4: Create Repo | 20 min |
| Phase 5: Shared Resources | 45 min |
| Phase 6: Atlantis Module | 2 hours |
| Phase 7: Platform Atlantis | 1 hour |
| Phase 8: Systems Atlantis | 1 hour |
| Phase 9: Demo Repos | 1 hour |
| Phase 10: Demo Script | 1.5 hours |
| **Total** | ~9.5-10 hours |

---

## Success Criteria

The demo is complete when:

1.  ✅ Single command sets up entire environment (GitLab + MinIO + Platform Atlantis)
2.  ✅ Platform Atlantis running and managing this repository
3.  ✅ Three Atlantis servers total: Platform, System-Alpha, System-Beta
4.  ✅ All Atlantis instances use shared GitLab service account (`atlantis-bot`)
5.  ✅ All Terraform state stored centrally in MinIO
6.  ✅ **Bootstrap demo works:** Can deploy new Atlantis via MR to platform repo
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
