#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║                                                                          ║"
echo "║          Atlantis Demo - Interactive Workflow Guide                     ║"
echo "║                                                                          ║"
echo "║  This script demonstrates the complete Atlantis bootstrap pattern       ║"
echo "║  and key features for GitOps-driven infrastructure management.          ║"
echo "║                                                                          ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# Configuration
GITLAB_URL="http://gitlab.127.0.0.1.nip.io"
GITLAB_API="$GITLAB_URL/api/v4"
PLATFORM_ATLANTIS_URL="http://atlantis-platform.127.0.0.1.nip.io"
SYSTEM_ALPHA_ATLANTIS_URL="http://atlantis-alpha.127.0.0.1.nip.io"
SYSTEM_BETA_ATLANTIS_URL="http://atlantis-beta.127.0.0.1.nip.io"
MINIO_CONSOLE_URL="http://minio-console.127.0.0.1.nip.io"

# Check current Kubernetes context
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "none")
echo "Current Kubernetes context: $CURRENT_CONTEXT"
echo ""

if [ "$CURRENT_CONTEXT" != "kind-atlantis-demo" ]; then
    echo -e "${YELLOW}⚠️  WARNING: Current context is '$CURRENT_CONTEXT', expected 'kind-atlantis-demo'${NC}"
    echo ""
    read -p "Do you want to continue anyway? (yes/no): " continue_anyway
    if [ "$continue_anyway" != "yes" ]; then
        echo "Aborted. Switch context with: kubectl config use-context kind-atlantis-demo"
        exit 1
    fi
    echo ""
fi

# Load GitLab credentials
echo -e "${BLUE}Loading credentials...${NC}"
GITLAB_ROOT_TOKEN=$(kubectl get secret -n gitlab gitlab-root-token -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "")
DEVELOPER_PASSWORD="Dem0!@#DevUser"
DEVELOPER_PASSWORD_ENCODED=$(printf '%s' "$DEVELOPER_PASSWORD" | python3 -c "import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read(),safe=''))")

if [ -z "$GITLAB_ROOT_TOKEN" ]; then
    echo -e "${RED}❌ Failed to retrieve GitLab credentials${NC}"
    echo "Make sure the setup scripts have been completed and the cluster is running"
    exit 1
fi

echo -e "${GREEN}✓ Credentials loaded${NC}"
echo ""

# Helper function to pause and wait for user
pause() {
    echo ""
    echo -e "${YELLOW}Press ENTER to continue...${NC}"
    read
}

# Helper function to wait for MR to be created
wait_for_mr() {
    local project_id=$1
    local branch_name=$2
    local max_wait=30
    local count=0

    echo -e "${BLUE}Waiting for merge request to be created...${NC}"
    while [ $count -lt $max_wait ]; do
        MR_IID=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
            "$GITLAB_API/projects/$project_id/merge_requests?state=opened&source_branch=$branch_name" | \
            jq -r '.[0].iid // empty')

        if [ -n "$MR_IID" ]; then
            echo -e "${GREEN}✓ Merge request !$MR_IID created${NC}"
            return 0
        fi

        sleep 1
        ((count++))
    done

    echo -e "${RED}❌ Timeout waiting for merge request${NC}"
    return 1
}

# Helper function to show Atlantis status
show_atlantis_pods() {
    echo -e "${BLUE}Current Atlantis deployments:${NC}"
    kubectl get pods -n atlantis -o wide 2>/dev/null || echo "  No pods found"
    echo ""
}

# Demo Menu
show_menu() {
    echo ""
    echo -e "${BOLD}${CYAN}Demo Scenarios:${NC}"
    echo -e ""
    echo -e "  ${BOLD}1${NC} - Bootstrap Flow: Atlantis manages Atlantis"
    echo -e "  ${BOLD}2${NC} - Auto-Detect Projects (System-Alpha)"
    echo -e "  ${BOLD}3${NC} - Workspace Environments (System-Beta)"
    echo -e "  ${BOLD}4${NC} - System Isolation & RBAC"
    echo -e "  ${BOLD}5${NC} - Approval Workflow"
    echo -e "  ${BOLD}6${NC} - Locking Mechanism"
    echo -e "  ${BOLD}7${NC} - State Management"
    echo -e ""
    echo -e "  ${BOLD}8${NC} - Show All URLs"
    echo -e "  ${BOLD}9${NC} - Cleanup Demo Resources"
    echo -e "  ${BOLD}0${NC} - Exit"
    echo -e ""
}

#############################################################################
# Demo 1: Bootstrap Flow
#############################################################################
demo_bootstrap() {
    echo ""
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN}Demo 1: Bootstrap Flow - Atlantis Manages Atlantis${NC}"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""

    # Generate a unique system name so the demo is re-runnable
    SYSTEM_SUFFIX="$(date +%s | tail -c 5)"
    SYSTEM_NAME="system-${SYSTEM_SUFFIX}"
    SYSTEM_DIR="$PROJECT_ROOT/atlantis-servers/environments/$SYSTEM_NAME"
    SYSTEM_BRANCH="add-${SYSTEM_NAME}-atlantis"
    SYSTEM_MODULE="${SYSTEM_NAME//-/_}"       # system_12345 (valid TF identifier)
    SYSTEM_SHORT="${SYSTEM_NAME#system-}"     # 12345 (for atlantis URL subdomain)

    echo -e "${CYAN}This demo shows how Platform Atlantis manages other Atlantis instances.${NC}"
    echo -e "${CYAN}We'll create a new ${BOLD}$SYSTEM_NAME${NC}${CYAN} Atlantis by submitting a PR.${NC}"
    echo ""

    show_atlantis_pods

    pause

    echo -e "${BLUE}Step 1: Creating $SYSTEM_NAME Atlantis configuration${NC}"
    echo ""

    mkdir -p "$SYSTEM_DIR"

    cat > "$SYSTEM_DIR/main.tf" << EOF
terraform {
  required_version = ">= 1.14"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.8"
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "kind-atlantis-demo"
}

module "${SYSTEM_MODULE}_atlantis" {
  source = "../../modules/atlantis-server"

  instance_name = "$SYSTEM_NAME"
  repo_allowlist = [
    "gitlab.127.0.0.1.nip.io/${SYSTEM_NAME}/*",
  ]
  atlantis_host     = "atlantis-${SYSTEM_SHORT}.127.0.0.1.nip.io"
  target_namespaces = ["${SYSTEM_NAME}"]
}

output "atlantis_url" {
  description = "$SYSTEM_NAME Atlantis URL"
  value       = module.${SYSTEM_MODULE}_atlantis.atlantis_url
}

output "webhook_url" {
  description = "Webhook URL to configure in GitLab"
  value       = module.${SYSTEM_MODULE}_atlantis.webhook_url
}

output "webhook_secret" {
  description = "Webhook secret to configure in GitLab"
  value       = module.${SYSTEM_MODULE}_atlantis.webhook_secret
  sensitive   = true
}

output "gitlab_webhook_setup" {
  description = "Instructions for configuring the GitLab webhook"
  value       = module.${SYSTEM_MODULE}_atlantis.gitlab_webhook_setup
}
EOF

    cat > "$SYSTEM_DIR/backend.tf" << EOF
terraform {
  backend "s3" {
    bucket = "terraform-statess"
    key    = "atlantis-servers/${SYSTEM_NAME}/terraform.tfstate"
    region = "us-east-1"

    endpoints = {
      s3 = "http://minio.127.0.0.1.nip.io"
    }
    access_key                  = "terraform"
    secret_key                  = "terraform-secret-key-change-me"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true
  }
}
EOF

    echo -e "${GREEN}✓ Created $SYSTEM_NAME configuration files${NC}"
    echo ""

    echo -e "${BLUE}Step 2: Updating atlantis.yaml to include $SYSTEM_NAME project${NC}"
    echo ""

    cat >> "$PROJECT_ROOT/atlantis.yaml" << EOF

  # $SYSTEM_NAME Atlantis server - managed by Platform Atlantis
  - name: ${SYSTEM_NAME}-atlantis
    dir: atlantis-servers/environments/${SYSTEM_NAME}
    workspace: default
    autoplan:
      when_modified:
        - "*.tf"
        - "*.tfvars"
        - ../../modules/atlantis-server/**/*.tf
        - ../../modules/atlantis-server/templates/*.tpl
      enabled: true
EOF

    echo -e "${GREEN}✓ Updated atlantis.yaml${NC}"
    echo ""

    echo -e "${BLUE}Step 3: Creating feature branch and committing changes${NC}"
    echo ""

    cd "$PROJECT_ROOT"
    git checkout -b "$SYSTEM_BRANCH"
    git add "atlantis-servers/environments/$SYSTEM_NAME/" atlantis.yaml
    GIT_AUTHOR_NAME="Administrator" GIT_AUTHOR_EMAIL="admin@atlantis-demo.local" \
    GIT_COMMITTER_NAME="Administrator" GIT_COMMITTER_EMAIL="admin@atlantis-demo.local" \
    git -c commit.gpgsign=false commit -m "Add $SYSTEM_NAME Atlantis server

This new Atlantis instance will manage the $SYSTEM_NAME namespace.
Platform Atlantis will deploy it via this PR."

    echo -e "${GREEN}✓ Changes committed to branch '$SYSTEM_BRANCH'${NC}"
    echo ""

    echo -e "${BLUE}Step 4: Pushing branch to GitLab${NC}"
    echo ""

    PROJECT_ID=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
        "$GITLAB_API/projects?search=atlantis-demo" | jq -r '.[0].id // empty')

    if [ -z "$PROJECT_ID" ]; then
        echo -e "${RED}❌ Could not find atlantis-demo project${NC}"
        return 1
    fi

    git push "http://root:$GITLAB_ROOT_TOKEN@gitlab.127.0.0.1.nip.io/root/atlantis-demo.git" "$SYSTEM_BRANCH"

    echo -e "${GREEN}✓ Branch pushed to GitLab${NC}"
    echo ""


    git switch -
    echo -e "${BLUE}Switched back to previous branch${NC}"

    echo -e "${BLUE}Step 5: Creating merge request${NC}"
    echo ""

    MR_RESPONSE=$(curl -s -X POST -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
        "$GITLAB_API/projects/$PROJECT_ID/merge_requests" \
        -d "source_branch=$SYSTEM_BRANCH" \
        -d "target_branch=main" \
        -d "title=Add $SYSTEM_NAME Atlantis Server" \
        -d "description=Deploy new Atlantis instance for $SYSTEM_NAME namespace")

    MR_IID=$(echo "$MR_RESPONSE" | jq -r '.iid // empty')
    MR_URL=$(echo "$MR_RESPONSE" | jq -r '.web_url // empty')

    echo -e "${GREEN}✓ Merge request created: !$MR_IID${NC}"
    echo ""
    echo -e "${CYAN}${BOLD}Next steps:${NC}"
    echo -e "  1. Open the MR in your browser: ${BLUE}$MR_URL${NC}"
    echo -e "  2. Platform Atlantis will automatically plan the new deployment"
    echo -e "  3. Review the plan output in the MR comments"
    echo -e "  4. Comment ${BOLD}'atlantis apply -p ${SYSTEM_NAME}-atlantis'${NC} to deploy"
    echo -e "  5. After apply, run: ${BOLD}kubectl get pods -n atlantis${NC} to see the new pod"
    echo ""

    pause

    echo -e "${CYAN}Checking Atlantis pods after deployment...${NC}"
    show_atlantis_pods
}

#############################################################################
# Demo 2: Auto-Detect Projects
#############################################################################
demo_auto_detect() {
    echo ""
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN}Demo 2: Auto-Detect Projects (System-Alpha)${NC}"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""

    echo -e "${CYAN}System-Alpha uses directory-based auto-detection (no atlantis.yaml).${NC}"
    echo -e "${CYAN}We'll modify the dev/ directory and see Atlantis auto-discover it.${NC}"
    echo ""

    echo -e "${BLUE}Current System-Alpha structure:${NC}"
    echo "  system-alpha-infra/"
    echo "  ├── dev/              <- Atlantis auto-detects this as a project"
    echo "  └── prod/             <- Atlantis auto-detects this as a project"
    echo ""

    pause

    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT

    echo -e "${BLUE}Step 1: Cloning system-alpha-infra repository${NC}"
    cd "$TEMP_DIR"
    git clone "http://root:$GITLAB_ROOT_TOKEN@gitlab.127.0.0.1.nip.io/system-alpha/system-alpha-infra.git"
    cd system-alpha-infra
    git config user.name "Demo User"
    git config user.email "demo@atlantis-demo.local"
    git config commit.gpgsign false

    # Create feature branch
    BRANCH_NAME="add-dev-configmap-$(date +%s)"
    git checkout -b "$BRANCH_NAME"

    echo -e "${GREEN}✓ Repository cloned${NC}"
    echo ""

    echo -e "${BLUE}Step 2: Adding a new ConfigMap to dev/ environment${NC}"
    echo ""

    # Add a new ConfigMap to dev/main.tf
    cat >> dev/main.tf << 'EOF'

# New ConfigMap for demonstration
resource "kubernetes_config_map" "demo_new" {
  metadata {
    name      = "demo-new-config"
    namespace = "system-alpha"

    labels = {
      managed-by = "terraform"
      demo       = "auto-detect"
    }
  }

  data = {
    feature_flag = "enabled"
    version      = "1.0.0"
  }
}
EOF

    git add dev/main.tf
    git commit -m "Add new demo ConfigMap to dev environment

This change affects only the dev/ directory, so Atlantis
should auto-plan only the 'dev' project."

    echo -e "${GREEN}✓ Changes committed${NC}"
    echo ""

    echo -e "${BLUE}Step 3: Pushing and creating merge request${NC}"
    git push -u origin "$BRANCH_NAME"

    # Get project ID
    PROJECT_ID=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
        "$GITLAB_API/projects?search=system-alpha-infra" | \
        jq -r '.[] | select(.path_with_namespace=="system-alpha/system-alpha-infra") | .id')

    # Create MR
    MR_RESPONSE=$(curl -s -X POST -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
        "$GITLAB_API/projects/$PROJECT_ID/merge_requests" \
        -d "source_branch=$BRANCH_NAME" \
        -d "target_branch=main" \
        -d "title=Add new ConfigMap to dev environment" \
        -d "description=Demo: Auto-detect pattern - only dev/ should be planned")

    MR_IID=$(echo "$MR_RESPONSE" | jq -r '.iid // empty')
    MR_URL=$(echo "$MR_RESPONSE" | jq -r '.web_url // empty')

    echo -e "${GREEN}✓ Merge request created: !$MR_IID${NC}"
    echo ""
    echo -e "${CYAN}${BOLD}What to observe:${NC}"
    echo -e "  1. Open MR: ${BLUE}$MR_URL${NC}"
    echo -e "  2. Atlantis auto-plans ${BOLD}only the 'dev' project${NC} (not prod)"
    echo -e "  3. The plan shows the new ConfigMap will be created"
    echo -e "  4. Comment ${BOLD}'atlantis apply -d dev'${NC} to apply"
    echo -e "  5. Verify: ${BOLD}kubectl get configmap -n system-alpha demo-new-config${NC}"
    echo ""

    echo -e "${YELLOW}Now let's modify a shared module to see multi-project planning...${NC}"
    pause

    echo -e "${BLUE}Step 4: Modifying shared module (affects both dev & prod)${NC}"

    # Create a new branch for module changes
    BRANCH_NAME_2="update-module-$(date +%s)"
    git checkout main
    git pull origin main
    git config user.name "Demo User"
    git config user.email "demo@atlantis-demo.local"
    git config commit.gpgsign false
    git checkout -b "$BRANCH_NAME_2"

    # Modify the shared module
    sed -i 's/managed-by  = "terraform"/managed-by  = "terraform-atlantis"/' modules/environment/main.tf

    git add modules/environment/main.tf
    git commit -m "Update label in shared environment module

This change affects the modules/ directory, so Atlantis
should auto-plan BOTH dev and prod projects."

    git push -u origin "$BRANCH_NAME_2"

    # Create second MR
    MR_RESPONSE_2=$(curl -s -X POST -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
        "$GITLAB_API/projects/$PROJECT_ID/merge_requests" \
        -d "source_branch=$BRANCH_NAME_2" \
        -d "target_branch=main" \
        -d "title=Update shared module label" \
        -d "description=Demo: Module change affects both dev and prod projects")

    MR_IID_2=$(echo "$MR_RESPONSE_2" | jq -r '.iid // empty')
    MR_URL_2=$(echo "$MR_RESPONSE_2" | jq -r '.web_url // empty')

    echo -e "${GREEN}✓ Second merge request created: !$MR_IID_2${NC}"
    echo ""
    echo -e "${CYAN}${BOLD}What to observe:${NC}"
    echo -e "  1. Open MR: ${BLUE}$MR_URL_2${NC}"
    echo -e "  2. Atlantis auto-plans ${BOLD}BOTH dev AND prod projects${NC}"
    echo -e "  3. You can apply them selectively:"
    echo -e "     - ${BOLD}'atlantis apply -d dev'${NC}"
    echo -e "     - ${BOLD}'atlantis apply -d prod'${NC}"
    echo ""
}

#############################################################################
# Demo 3: Workspace Environments
#############################################################################
demo_workspaces() {
    echo ""
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN}Demo 3: Workspace Environments (System-Beta)${NC}"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""

    echo -e "${CYAN}System-Beta uses workspace-based pattern with explicit atlantis.yaml.${NC}"
    echo -e "${CYAN}Single codebase, separate workspace configs for dev and prod.${NC}"
    echo ""

    echo -e "${BLUE}Current System-Beta structure:${NC}"
    echo "  system-beta-infra/"
    echo "  ├── atlantis.yaml    <- Defines 'dev' and 'prod' workspace projects"
    echo "  ├── main.tf          <- Shared code"
    echo "  └── backend.tf       <- Workspace-based state keys"
    echo ""

    pause

    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT

    echo -e "${BLUE}Step 1: Cloning system-beta-infra repository${NC}"
    cd "$TEMP_DIR"
    git clone "http://root:$GITLAB_ROOT_TOKEN@gitlab.127.0.0.1.nip.io/system-beta/system-beta-infra.git"
    cd system-beta-infra
    git config user.name "Demo User"
    git config user.email "demo@atlantis-demo.local"
    git config commit.gpgsign false

    # Create feature branch
    BRANCH_NAME="update-shared-code-$(date +%s)"
    git checkout -b "$BRANCH_NAME"

    echo -e "${GREEN}✓ Repository cloned${NC}"
    echo ""

    echo -e "${BLUE}Step 2: Modifying shared main.tf (affects both workspaces)${NC}"
    echo ""

    # Add a new shared resource
    cat >> main.tf << 'EOF'

# New shared ConfigMap (will be created in both workspaces)
resource "kubernetes_config_map" "shared_feature" {
  metadata {
    name      = "${terraform.workspace}-shared-feature"
    namespace = local.namespace

    labels = {
      managed-by = "terraform"
      workspace  = terraform.workspace
    }
  }

  data = {
    feature_enabled = "true"
    workspace       = terraform.workspace
    replicas        = tostring(local.config.replica_count)
  }
}
EOF

    git add main.tf
    git commit -m "Add shared feature ConfigMap

This change to main.tf will trigger plans for BOTH
dev and prod workspace projects."

    echo -e "${GREEN}✓ Changes committed${NC}"
    echo ""

    echo -e "${BLUE}Step 3: Pushing and creating merge request${NC}"
    git push -u origin "$BRANCH_NAME"

    # Get project ID
    PROJECT_ID=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
        "$GITLAB_API/projects?search=system-beta-infra" | \
        jq -r '.[] | select(.path_with_namespace=="system-beta/system-beta-infra") | .id')

    # Create MR
    MR_RESPONSE=$(curl -s -X POST -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
        "$GITLAB_API/projects/$PROJECT_ID/merge_requests" \
        -d "source_branch=$BRANCH_NAME" \
        -d "target_branch=main" \
        -d "title=Add shared feature ConfigMap" \
        -d "description=Demo: Workspace pattern - both dev and prod will be planned")

    MR_IID=$(echo "$MR_RESPONSE" | jq -r '.iid // empty')
    MR_URL=$(echo "$MR_RESPONSE" | jq -r '.web_url // empty')

    echo -e "${GREEN}✓ Merge request created: !$MR_IID${NC}"
    echo ""
    echo -e "${CYAN}${BOLD}What to observe:${NC}"
    echo -e "  1. Open MR: ${BLUE}$MR_URL${NC}"
    echo -e "  2. Atlantis auto-plans ${BOLD}BOTH 'dev' and 'prod' workspace projects${NC}"
    echo -e "  3. Each plan uses workspace-specific configuration:"
    echo -e "     - dev: 1 replica, debug logging"
    echo -e "     - prod: 3 replicas, info logging"
    echo -e "  4. Apply selectively:"
    echo -e "     - ${BOLD}'atlantis apply -p dev'${NC} (apply dev workspace first)"
    echo -e "     - ${BOLD}'atlantis apply -p prod'${NC} (then prod after testing)"
    echo -e "  5. Verify resources:"
    echo -e "     - ${BOLD}kubectl get configmap -n system-beta dev-shared-feature${NC}"
    echo -e "     - ${BOLD}kubectl get configmap -n system-beta prod-shared-feature${NC}"
    echo ""

    pause
}

#############################################################################
# Demo 4: System Isolation
#############################################################################
demo_isolation() {
    echo ""
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN}Demo 4: System Isolation & RBAC${NC}"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""

    echo -e "${CYAN}Each Atlantis instance has RBAC permissions only for its target namespace.${NC}"
    echo -e "${CYAN}Let's try to make System-Alpha create a resource in System-Beta's namespace.${NC}"
    echo ""

    pause

    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT

    echo -e "${BLUE}Step 1: Cloning system-alpha-infra repository${NC}"
    cd "$TEMP_DIR"
    git clone "http://root:$GITLAB_ROOT_TOKEN@gitlab.127.0.0.1.nip.io/system-alpha/system-alpha-infra.git"
    cd system-alpha-infra
    git config user.name "Demo User"
    git config user.email "demo@atlantis-demo.local"
    git config commit.gpgsign false

    # Create feature branch
    BRANCH_NAME="test-isolation-$(date +%s)"
    git checkout -b "$BRANCH_NAME"

    echo -e "${GREEN}✓ Repository cloned${NC}"
    echo ""

    echo -e "${BLUE}Step 2: Attempting to create resource in system-beta namespace${NC}"
    echo ""

    # Try to create a resource in the wrong namespace
    cat >> dev/main.tf << 'EOF'

# SECURITY TEST: Try to create resource in system-beta namespace
# This should FAIL due to RBAC restrictions
resource "kubernetes_config_map" "cross_namespace_test" {
  metadata {
    name      = "unauthorized-configmap"
    namespace = "system-beta"  # Wrong namespace!

    labels = {
      test = "rbac-isolation"
    }
  }

  data = {
    message = "This should not be created"
  }
}
EOF

    git add dev/main.tf
    git commit -m "Test: Attempt cross-namespace resource creation

This will demonstrate RBAC isolation - the plan/apply should fail
because System-Alpha's ServiceAccount doesn't have permissions
to create resources in system-beta namespace."

    echo -e "${GREEN}✓ Changes committed${NC}"
    echo ""

    echo -e "${BLUE}Step 3: Pushing and creating merge request${NC}"
    git push -u origin "$BRANCH_NAME"

    # Get project ID
    PROJECT_ID=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
        "$GITLAB_API/projects?search=system-alpha-infra" | \
        jq -r '.[] | select(.path_with_namespace=="system-alpha/system-alpha-infra") | .id')

    # Create MR
    MR_RESPONSE=$(curl -s -X POST -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
        "$GITLAB_API/projects/$PROJECT_ID/merge_requests" \
        -d "source_branch=$BRANCH_NAME" \
        -d "target_branch=main" \
        -d "title=[SECURITY TEST] Cross-namespace resource attempt" \
        -d "description=Demo: This will fail due to RBAC isolation")

    MR_IID=$(echo "$MR_RESPONSE" | jq -r '.iid // empty')
    MR_URL=$(echo "$MR_RESPONSE" | jq -r '.web_url // empty')

    echo -e "${GREEN}✓ Merge request created: !$MR_IID${NC}"
    echo ""
    echo -e "${CYAN}${BOLD}What to observe:${NC}"
    echo -e "  1. Open MR: ${BLUE}$MR_URL${NC}"
    echo -e "  2. Atlantis will plan successfully (showing intended changes)"
    echo -e "  3. But ${BOLD}'atlantis apply'${NC} will ${RED}FAIL${NC} with permission error:"
    echo -e "     ${RED}Error: configmaps is forbidden: User \"system:serviceaccount:${NC}"
    echo -e "     ${RED}atlantis:atlantis-system-alpha\" cannot create resource${NC}"
    echo ""
    echo -e "${CYAN}${BOLD}RBAC Boundaries Demonstrated:${NC}"
    echo -e "  ✓ System-Alpha Atlantis can only manage 'system-alpha' namespace"
    echo -e "  ✓ System-Beta Atlantis can only manage 'system-beta' namespace"
    echo -e "  ✓ Platform Atlantis can only manage 'atlantis' namespace"
    echo -e "  ✓ Developers have ${BOLD}NO${NC} direct access to:"
    echo -e "    - Atlantis pods (in 'atlantis' namespace)"
    echo -e "    - MinIO console or state files"
    echo -e "    - Other system namespaces"
    echo ""

    echo -e "${YELLOW}Let's verify the RBAC configuration...${NC}"
    pause

    echo -e "${BLUE}System-Alpha ServiceAccount permissions:${NC}"
    kubectl describe role -n system-alpha atlantis-system-alpha 2>/dev/null || echo "  Role not found"
    echo ""

    echo -e "${BLUE}System-Beta ServiceAccount permissions:${NC}"
    kubectl describe role -n system-beta atlantis-system-beta 2>/dev/null || echo "  Role not found"
    echo ""
}

#############################################################################
# Demo 5: Approval Workflow
#############################################################################
demo_approval() {
    echo ""
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN}Demo 5: Approval Workflow${NC}"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""

    echo -e "${CYAN}GitLab approval rules enforce separation of duties.${NC}"
    echo -e "${CYAN}Developer creates MR → Atlantis plans → Maintainer approves → Apply allowed${NC}"
    echo ""

    echo -e "${BLUE}Users in this demo:${NC}"
    echo -e "  ${BOLD}developer${NC} - Can create MRs and push code (Developer role)"
    echo -e "  ${BOLD}root${NC}      - Can approve MRs (Maintainer/Owner role)"
    echo ""
    echo -e "${YELLOW}Password for 'developer': $DEVELOPER_PASSWORD${NC}"
    echo ""

    pause

    echo -e "${CYAN}${BOLD}Workflow demonstration:${NC}"
    echo ""
    echo -e "${BOLD}1. Developer creates MR:${NC}"
    echo -e "   - Log in as 'developer' at: ${BLUE}$GITLAB_URL${NC}"
    echo -e "   - Navigate to system-alpha-infra or system-beta-infra"
    echo -e "   - Create a branch and modify any .tf file"
    echo -e "   - Create merge request"
    echo ""

    echo -e "${BOLD}2. Atlantis auto-plans:${NC}"
    echo -e "   - Atlantis comments on MR with plan output"
    echo -e "   - Plan shows what changes will be made"
    echo -e "   - MR pipeline shows as 'running' (apply check is required and still pending)"
    echo ""

    echo -e "${BOLD}3. Developer tries to apply:${NC}"
    echo -e "   - Comment: ${BOLD}'atlantis apply'${NC}"
    echo -e "   - In this demo the apply will succeed immediately without approval."
    echo -e "   - This is a ${BOLD}GitLab CE limitation${NC}: CE does not expose project-level"
    echo -e "     approval rules via the API, so Atlantis sees 0 required approvals"
    echo -e "     and considers the 'approved' requirement trivially satisfied."
    echo -e "   - The Atlantis server-side config correctly sets:"
    echo -e "     ${BOLD}apply_requirements: [approved, mergeable]${NC}"
    echo -e "   - On ${BOLD}GitLab EE${NC} (or GitHub / Bitbucket), you would configure a project"
    echo -e "     approval rule requiring 1 approval from a Maintainer. Atlantis would"
    echo -e "     then query the approval API and block the apply with:"
    echo -e "     ${RED}\"Apply requirements not met: approval required\"${NC}"
    echo ""

    echo -e "${BOLD}4. Maintainer approves (how it works on GitLab EE / GitHub):${NC}"
    echo -e "   - Log in as 'root' at: ${BLUE}$GITLAB_URL${NC}"
    echo -e "   - Review the plan output and code changes in the MR"
    echo -e "   - Click 'Approve' button — this satisfies the ${BOLD}approved${NC} requirement"
    echo -e "   - Atlantis polls the GitLab approval API and unblocks the apply"
    echo ""

    echo -e "${BOLD}5. Developer applies (after approval in EE / GitHub):${NC}"
    echo -e "   - Comment: ${BOLD}'atlantis apply'${NC}"
    echo -e "   - Atlantis applies changes and comments with results"
    echo -e "   - Resources are created/updated in Kubernetes"
    echo -e "   - After apply, Atlantis auto-merges the MR"
    echo ""

    pause

    echo -e "${CYAN}Let's create a demo MR to show this workflow...${NC}"
    echo ""

    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT

    echo -e "${BLUE}Creating demo MR in system-alpha-infra...${NC}"
    cd "$TEMP_DIR"
    git clone "http://developer:$DEVELOPER_PASSWORD_ENCODED@gitlab.127.0.0.1.nip.io/system-alpha/system-alpha-infra.git"
    cd system-alpha-infra
    git config user.name "Demo Developer"
    git config user.email "developer@atlantis-demo.local"
    git config commit.gpgsign false

    BRANCH_NAME="approval-demo-$(date +%s)"
    git checkout -b "$BRANCH_NAME"

    # Make a simple change
    cat >> dev/main.tf << 'EOF'

# ConfigMap for approval workflow demo
resource "kubernetes_config_map" "approval_demo" {
  metadata {
    name      = "approval-workflow-demo"
    namespace = "system-alpha"

    labels = {
      demo = "approval-workflow"
    }
  }

  data = {
    message = "This resource requires approval before apply"
  }
}
EOF

    git add dev/main.tf
    git commit -m "Add ConfigMap for approval workflow demo

This MR demonstrates the approval workflow:
1. Atlantis will auto-plan
2. Apply is blocked until approved
3. Root user must approve
4. Then developer can apply"

    git push -u origin "$BRANCH_NAME"

    # Mint a short-lived PAT for the developer via the admin API, use it to create
    # the MR as the developer, then immediately revoke it.
    # (OAuth password grant is disabled by default in GitLab 15+; Sudo requires
    # a token with the 'sudo' scope which the root token doesn't have.)
    DEVELOPER_ID=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
        "$GITLAB_API/users?username=developer" | jq -r '.[0].id // empty')

    TEMP_PAT=$(curl -s -X POST -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
        "$GITLAB_API/users/$DEVELOPER_ID/personal_access_tokens" \
        -d "name=demo-approval-temp" \
        -d "scopes[]=api" \
        -d "expires_at=$(date -d '+1 day' '+%Y-%m-%d' 2>/dev/null || date -v+1d '+%Y-%m-%d')")
    DEVELOPER_TOKEN=$(echo "$TEMP_PAT" | jq -r '.token // empty')
    TEMP_PAT_ID=$(echo "$TEMP_PAT" | jq -r '.id // empty')

    PROJECT_ID=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
        "$GITLAB_API/projects?search=system-alpha-infra" | \
        jq -r '.[] | select(.path_with_namespace=="system-alpha/system-alpha-infra") | .id')

    MR_RESPONSE=$(curl -s -X POST -H "PRIVATE-TOKEN: $DEVELOPER_TOKEN" \
        "$GITLAB_API/projects/$PROJECT_ID/merge_requests" \
        -d "source_branch=$BRANCH_NAME" \
        -d "target_branch=main" \
        -d "title=Approval Workflow Demo" \
        -d "description=This MR demonstrates approval requirements")

    # Revoke the temporary token immediately
    [ -n "$TEMP_PAT_ID" ] && curl -s -X DELETE -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
        "$GITLAB_API/personal_access_tokens/$TEMP_PAT_ID" > /dev/null

    MR_IID=$(echo "$MR_RESPONSE" | jq -r '.iid // empty')
    MR_URL=$(echo "$MR_RESPONSE" | jq -r '.web_url // empty')

    if [ -n "$MR_IID" ]; then
        echo -e "${GREEN}✓ Merge request created by developer: !$MR_IID${NC}"
        echo ""
        echo -e "${CYAN}${BOLD}Next steps:${NC}"
        echo -e "  1. Open MR: ${BLUE}$MR_URL${NC}"
        echo -e "  2. Wait for Atlantis to auto-plan and comment with the plan output"
        echo -e "  3. As developer, comment: ${BOLD}'atlantis apply'${NC}"
        echo -e "     The apply will succeed in this demo (GitLab CE limitation — see above)."
        echo -e "     On ${BOLD}GitLab EE or GitHub${NC}, Atlantis would block here until a"
        echo -e "     Maintainer approves the MR, enforcing separation of duties."
        echo -e "  4. As root, click 'Approve' to show what the approval step looks like"
        echo ""
    else
        echo -e "${RED}❌ Could not create merge request${NC}"
        echo "Response: $MR_RESPONSE"
    fi

    pause
}

#############################################################################
# Demo 6: Locking
#############################################################################
demo_locking() {
    echo ""
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN}Demo 6: Locking Mechanism${NC}"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""

    echo -e "${CYAN}Atlantis locks prevent concurrent changes to the same project.${NC}"
    echo -e "${CYAN}The lock is acquired at ${BOLD}plan time${NC}${CYAN}, not apply time.${NC}"
    echo -e "${CYAN}This prevents race conditions and state corruption.${NC}"
    echo ""

    pause

    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT

    # Get project ID
    PROJECT_ID=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
        "$GITLAB_API/projects?search=system-alpha-infra" | \
        jq -r '.[] | select(.path_with_namespace=="system-alpha/system-alpha-infra") | .id')

    if [ -z "$PROJECT_ID" ]; then
        echo -e "${RED}❌ Could not find system-alpha-infra project${NC}"
        return 1
    fi

    echo -e "${BLUE}Step 1: Creating MR #1 — first change to dev/${NC}"
    echo ""

    cd "$TEMP_DIR"
    git clone "http://root:$GITLAB_ROOT_TOKEN@gitlab.127.0.0.1.nip.io/system-alpha/system-alpha-infra.git"
    cd system-alpha-infra
    git config user.name "Demo User"
    git config user.email "demo@atlantis-demo.local"
    git config commit.gpgsign false

    BRANCH_1="locking-demo-mr1-$(date +%s)"
    git checkout -b "$BRANCH_1"

    cat >> dev/main.tf << 'EOF'

# ConfigMap for locking demo - MR #1
resource "kubernetes_config_map" "lock_demo_mr1" {
  metadata {
    name      = "lock-demo-mr1"
    namespace = "system-alpha"
    labels = {
      demo = "locking-mr1"
    }
  }
  data = {
    message = "Created by MR 1"
  }
}
EOF

    git add dev/main.tf
    git commit -m "Locking demo: MR #1 — add lock-demo-mr1 ConfigMap"
    git push -u origin "$BRANCH_1"

    MR1_RESPONSE=$(curl -s -X POST -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
        "$GITLAB_API/projects/$PROJECT_ID/merge_requests" \
        -d "source_branch=$BRANCH_1" \
        -d "target_branch=main" \
        -d "title=Locking Demo: MR #1 (leave this open / unapplied)" \
        -d "description=Demo: This MR will hold the Atlantis lock after planning.")

    MR1_IID=$(echo "$MR1_RESPONSE" | jq -r '.iid // empty')
    MR1_URL=$(echo "$MR1_RESPONSE" | jq -r '.web_url // empty')

    echo -e "${GREEN}✓ MR #1 created: !$MR1_IID${NC}"
    echo ""
    echo -e "${CYAN}  Open: ${BLUE}$MR1_URL${NC}"
    echo ""
    echo -e "${YELLOW}Atlantis will auto-plan MR #1 shortly. The plan acquires the lock${NC}"
    echo -e "${YELLOW}on dev/ immediately — ${BOLD}even before any apply.${NC}"
    echo ""
    echo -e "Wait for Atlantis to post the plan comment on MR #1, then press ENTER."
    echo -e "${CYAN}(You can watch: ${BLUE}$MR1_URL${CYAN})${NC}"
    pause

    echo -e "${BLUE}Step 2: Creating MR #2 — a second change to the same dev/${NC}"
    echo ""

    git checkout main
    git pull origin main
    git config user.name "Demo User"
    git config user.email "demo@atlantis-demo.local"
    git config commit.gpgsign false

    BRANCH_2="locking-demo-mr2-$(date +%s)"
    git checkout -b "$BRANCH_2"

    cat >> dev/main.tf << 'EOF'

# ConfigMap for locking demo - MR #2
resource "kubernetes_config_map" "lock_demo_mr2" {
  metadata {
    name      = "lock-demo-mr2"
    namespace = "system-alpha"
    labels = {
      demo = "locking-mr2"
    }
  }
  data = {
    message = "Created by MR 2"
  }
}
EOF

    git add dev/main.tf
    git commit -m "Locking demo: MR #2 — add lock-demo-mr2 ConfigMap"
    git push -u origin "$BRANCH_2"

    MR2_RESPONSE=$(curl -s -X POST -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
        "$GITLAB_API/projects/$PROJECT_ID/merge_requests" \
        -d "source_branch=$BRANCH_2" \
        -d "target_branch=main" \
        -d "title=Locking Demo: MR #2 (will be blocked by lock from MR #1)" \
        -d "description=Demo: Atlantis will refuse to plan this while MR #1 holds the lock.")

    MR2_IID=$(echo "$MR2_RESPONSE" | jq -r '.iid // empty')
    MR2_URL=$(echo "$MR2_RESPONSE" | jq -r '.web_url // empty')

    echo -e "${GREEN}✓ MR #2 created: !$MR2_IID${NC}"
    echo ""
    echo -e "${CYAN}  Open: ${BLUE}$MR2_URL${NC}"
    echo ""

    echo -e "${CYAN}${BOLD}What to observe:${NC}"
    echo ""
    echo -e "${BOLD}Current state — MR #1 is planned but NOT applied:${NC}"
    echo -e "  • Atlantis holds a lock on ${BOLD}system-alpha-infra/dev${NC}"
    echo -e "  • The lock was acquired at ${BOLD}plan time${NC}, not apply time"
    echo -e "  • MR #2 will auto-plan and Atlantis will comment something like:"
    echo -e "    ${RED}\"This project is currently locked by MR !$MR1_IID\"${NC}"
    echo ""
    echo -e "${BOLD}To confirm the lock in the Atlantis UI:${NC}"
    echo -e "  ${BLUE}$SYSTEM_ALPHA_ATLANTIS_URL${NC}  → Locks tab"
    echo ""
    echo -e "${BOLD}To release the lock and allow MR #2 to proceed:${NC}"
    echo -e "  Option A — Apply MR #1:"
    echo -e "    Comment on MR !$MR1_IID: ${BOLD}'atlantis apply -d dev'${NC}"
    echo -e "    Lock releases automatically after apply + merge."
    echo ""
    echo -e "  Option B — Abandon MR #1 (unlock without applying):"
    echo -e "    Comment on MR !$MR1_IID: ${BOLD}'atlantis unlock'${NC}"
    echo -e "    Or close the MR — Atlantis releases the lock."
    echo ""
    echo -e "${BOLD}After the lock is released:${NC}"
    echo -e "  Comment on MR !$MR2_IID: ${BOLD}'atlantis plan -d dev'${NC}"
    echo -e "  Atlantis will now plan and MR #2 can proceed."
    echo ""

    pause
}

#############################################################################
# Demo 7: State Management
#############################################################################
demo_state() {
    echo ""
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN}Demo 7: State Management${NC}"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""

    echo -e "${CYAN}All Terraform state is stored in MinIO (S3-compatible storage).${NC}"
    echo -e "${CYAN}Each system has isolated state files with proper organization.${NC}"
    echo ""

    pause

    echo -e "${BLUE}State file organization:${NC}"
    echo ""
    echo -e "${BOLD}MinIO Bucket: terraform-states${NC}"
    echo -e "├── atlantis-servers/"
    echo -e "│   ├── platform/terraform.tfstate              ${CYAN}(Platform Atlantis)${NC}"
    echo -e "│   ├── shared/terraform.tfstate                ${CYAN}(Shared config)${NC}"
    echo -e "│   ├── system-alpha/terraform.tfstate          ${CYAN}(System-Alpha Atlantis)${NC}"
    echo -e "│   └── system-beta/terraform.tfstate           ${CYAN}(System-Beta Atlantis)${NC}"
    echo -e "├── system-alpha-infra/"
    echo -e "│   ├── dev/terraform.tfstate                   ${CYAN}(System-Alpha dev env)${NC}"
    echo -e "│   └── prod/terraform.tfstate                  ${CYAN}(System-Alpha prod env)${NC}"
    echo -e "└── env:/"
    echo -e "    ├── dev/system-beta-infra/terraform.tfstate  ${CYAN}(System-Beta dev workspace)${NC}"
    echo -e "    └── prod/system-beta-infra/terraform.tfstate ${CYAN}(System-Beta prod workspace)${NC}"
    echo ""

    pause

    echo -e "${BLUE}Accessing MinIO Console:${NC}"
    echo ""

    # Get MinIO credentials
    MINIO_ROOT_USER=$(kubectl get secret -n minio minio-credentials -o jsonpath='{.data.rootUser}' 2>/dev/null | base64 -d)
    MINIO_ROOT_PASSWORD=$(kubectl get secret -n minio minio-credentials -o jsonpath='{.data.rootPassword}' 2>/dev/null | base64 -d)

    echo -e "  URL: ${BLUE}$MINIO_CONSOLE_URL${NC}"
    echo -e "  Username: ${BOLD}$MINIO_ROOT_USER${NC}"
    echo -e "  Password: ${BOLD}$MINIO_ROOT_PASSWORD${NC}"
    echo ""

    echo -e "${CYAN}${BOLD}In the MinIO console you can:${NC}"
    echo -e "  1. Navigate to the 'terraform-states' bucket"
    echo -e "  2. Browse all state files by system and environment"
    echo -e "  3. View state file contents (JSON format)"
    echo -e "  4. See state file metadata (size, last modified, etc.)"
    echo ""

    echo -e "${YELLOW}⚠️  Important: Developers have NO access to MinIO${NC}"
    echo -e "    - State files are secured in the 'minio' namespace"
    echo -e "    - Only platform admins can access the console"
    echo -e "    - Atlantis ServiceAccounts have scoped S3 API access"
    echo ""

    pause

    echo -e "${BLUE}Listing state files via kubectl:${NC}"
    echo ""

    # Use MinIO client to list states
    echo -e "${CYAN}Listing state files via MinIO Client (mc)...${NC}"
    MINIO_POD=$(kubectl get pod -n minio -l app=minio -o jsonpath='{.items[0].metadata.name}')

    if [ -n "$MINIO_POD" ]; then
        echo ""
        kubectl exec -n minio "$MINIO_POD" -- sh -c \
            "mc alias set local http://localhost:9000 \"$MINIO_ROOT_USER\" \"$MINIO_ROOT_PASSWORD\" >/dev/null 2>&1 && mc ls local/terraform-states --recursive" 2>/dev/null || \
            echo "  (Could not list state files)"
        echo ""
    fi

    echo -e "${CYAN}${BOLD}State isolation benefits:${NC}"
    echo -e "  ✓ Centralized backup and versioning"
    echo -e "  ✓ No state files in git repositories"
    echo -e "  ✓ Each system's state is isolated"
    echo -e "  ✓ Easy to audit and monitor"
    echo -e "  ✓ Supports remote team collaboration"
    echo ""

    pause
}

#############################################################################
# Show All URLs
#############################################################################
show_urls() {
    echo ""
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}All Demo URLs${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""

    echo -e "${BOLD}GitLab:${NC}"
    echo -e "  URL: ${BLUE}$GITLAB_URL${NC}"
    GITLAB_ROOT_PASSWORD=$(kubectl get secret -n gitlab gitlab-root-password -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)
    echo -e "  Root user: ${BOLD}root${NC} / ${BOLD}$GITLAB_ROOT_PASSWORD${NC}"
    echo -e "  Developer: ${BOLD}developer${NC} / ${BOLD}$DEVELOPER_PASSWORD${NC}"
    echo ""

    echo -e "${BOLD}Atlantis Instances:${NC}"
    echo -e "  Platform: ${BLUE}$PLATFORM_ATLANTIS_URL${NC}"
    echo -e "  System-Alpha: ${BLUE}$SYSTEM_ALPHA_ATLANTIS_URL${NC}"
    echo -e "  System-Beta: ${BLUE}$SYSTEM_BETA_ATLANTIS_URL${NC}"
    echo ""

    echo -e "${BOLD}MinIO Console:${NC}"
    MINIO_ROOT_USER=$(kubectl get secret -n minio minio-credentials -o jsonpath='{.data.rootUser}' 2>/dev/null | base64 -d)
    MINIO_ROOT_PASSWORD=$(kubectl get secret -n minio minio-credentials -o jsonpath='{.data.rootPassword}' 2>/dev/null | base64 -d)
    echo -e "  URL: ${BLUE}$MINIO_CONSOLE_URL${NC}"
    echo -e "  Username: ${BOLD}$MINIO_ROOT_USER${NC}"
    echo -e "  Password: ${BOLD}$MINIO_ROOT_PASSWORD${NC}"
    echo ""

    echo -e "${BOLD}GitLab Repositories:${NC}"
    echo -e "  Platform: ${BLUE}$GITLAB_URL/root/atlantis-demo${NC}"
    echo -e "  System-Alpha: ${BLUE}$GITLAB_URL/system-alpha/system-alpha-infra${NC}"
    echo -e "  System-Beta: ${BLUE}$GITLAB_URL/system-beta/system-beta-infra${NC}"
    echo ""
}

#############################################################################
# Cleanup
#############################################################################
cleanup_demo() {
    echo ""
    echo -e "${BOLD}${YELLOW}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${YELLOW}Cleanup Demo Resources${NC}"
    echo -e "${BOLD}${YELLOW}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""

    echo -e "${RED}This will:${NC}"
    echo -e "  - Delete all demo MRs and branches in GitLab"
    echo -e "  - Remove demo resources from Kubernetes namespaces"
    echo -e "  - Keep the infrastructure (Atlantis, GitLab, MinIO)"
    echo ""

    read -p "Are you sure you want to cleanup demo resources? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        echo -e "${CYAN}Cleanup cancelled${NC}"
        return
    fi

    echo ""
    echo -e "${BLUE}Cleaning up demo resources...${NC}"

    # Delete demo ConfigMaps in system-alpha
    echo "Removing demo resources from system-alpha namespace..."
    kubectl delete configmap -n system-alpha demo-new-config 2>/dev/null || true
    kubectl delete configmap -n system-alpha approval-workflow-demo 2>/dev/null || true

    # Delete demo ConfigMaps in system-beta
    echo "Removing demo resources from system-beta namespace..."
    kubectl delete configmap -n system-beta dev-shared-feature 2>/dev/null || true
    kubectl delete configmap -n system-beta prod-shared-feature 2>/dev/null || true

    # Close demo MRs in GitLab
    echo "Closing demo merge requests..."

    for repo in "system-alpha/system-alpha-infra" "system-beta/system-beta-infra"; do
        PROJECT_ID=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
            "$GITLAB_API/projects?search=${repo##*/}" | \
            jq -r ".[] | select(.path_with_namespace==\"$repo\") | .id")

        if [ -n "$PROJECT_ID" ]; then
            # Get all open MRs
            MR_IIDS=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
                "$GITLAB_API/projects/$PROJECT_ID/merge_requests?state=opened" | \
                jq -r '.[].iid')

            for MR_IID in $MR_IIDS; do
                curl -s -X PUT -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
                    "$GITLAB_API/projects/$PROJECT_ID/merge_requests/$MR_IID" \
                    -d "state_event=close" > /dev/null
                echo "  Closed MR !$MR_IID in $repo"
            done
        fi
    done

    echo ""
    echo -e "${GREEN}✓ Cleanup complete${NC}"
    echo ""
}

#############################################################################
# Main Menu Loop
#############################################################################

while true; do
    show_menu
    read -p "Select demo scenario (0-9): " choice

    case $choice in
        1) demo_bootstrap ;;
        2) demo_auto_detect ;;
        3) demo_workspaces ;;
        4) demo_isolation ;;
        5) demo_approval ;;
        6) demo_locking ;;
        7) demo_state ;;
        8) show_urls ;;
        9) cleanup_demo ;;
        0)
            echo ""
            echo -e "${CYAN}Thank you for exploring the Atlantis demo!${NC}"
            echo ""
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice. Please select 0-9.${NC}"
            ;;
    esac
done
