#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Phase 9: Demo Repositories Setup ==="
echo ""

# Check current Kubernetes context
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "none")
echo "Current Kubernetes context: $CURRENT_CONTEXT"
echo ""

if [ "$CURRENT_CONTEXT" != "kind-atlantis-demo" ]; then
    echo "⚠️  WARNING: Current context is '$CURRENT_CONTEXT', expected 'kind-atlantis-demo'"
    echo ""
    read -p "Do you want to continue anyway? (yes/no): " continue_anyway
    if [ "$continue_anyway" != "yes" ]; then
        echo "Aborted. Switch context with: kubectl config use-context kind-atlantis-demo"
        exit 1
    fi
    echo ""
fi

# Load GitLab root token from Kubernetes
echo "Loading GitLab credentials from Kubernetes..."
GITLAB_ROOT_TOKEN=$(kubectl get secret -n gitlab gitlab-root-token -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "")

if [ -z "$GITLAB_ROOT_TOKEN" ]; then
  echo "❌ Failed to retrieve GitLab root token from Kubernetes"
  echo "Make sure Phase 4 has been completed and the gitlab-root-token secret exists"
  exit 1
fi

echo "✓ GitLab credentials loaded"
echo ""

GITLAB_URL="http://gitlab.127.0.0.1.nip.io"
GITLAB_API="$GITLAB_URL/api/v4"

# Demo repositories configuration
SYSTEM_ALPHA_REPO="system-alpha/system-alpha-infra"
SYSTEM_BETA_REPO="system-beta/system-beta-infra"

# Developer user configuration
DEVELOPER_USERNAME="developer"
DEVELOPER_EMAIL="developer@atlantis-demo.local"
DEVELOPER_PASSWORD="Dem0!@#DevUser"
DEVELOPER_NAME="Demo Developer"

echo ""
echo "Step 1: Create developer GitLab user"
echo "-----------------------------------"

# Check if developer user already exists
DEVELOPER_ID=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
  "$GITLAB_API/users?username=$DEVELOPER_USERNAME" | jq -r '.[0].id // empty')

if [ -n "$DEVELOPER_ID" ]; then
  echo "✓ Developer user already exists (ID: $DEVELOPER_ID)"
else
  echo "Creating developer user..."
  RESPONSE=$(curl -s -X POST -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
    "$GITLAB_API/users" \
    -d "email=$DEVELOPER_EMAIL" \
    -d "username=$DEVELOPER_USERNAME" \
    -d "name=$DEVELOPER_NAME" \
    -d "password=$DEVELOPER_PASSWORD" \
    -d "skip_confirmation=true")

  DEVELOPER_ID=$(echo "$RESPONSE" | jq -r '.id // empty')

  if [ -z "$DEVELOPER_ID" ]; then
    echo "❌ Failed to create developer user"
    echo "Response: $RESPONSE"
    exit 1
  fi

  echo "✓ Created developer user (ID: $DEVELOPER_ID)"
fi

echo ""
echo "Step 2: Create System-Alpha repository"
echo "--------------------------------------"

# Check if System-Alpha group exists
SYSTEM_ALPHA_GROUP_ID=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
  "$GITLAB_API/groups/system-alpha" | jq -r '.id // empty')

if [ -z "$SYSTEM_ALPHA_GROUP_ID" ]; then
  echo "Creating system-alpha group..."
  RESPONSE=$(curl -s -X POST -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
    "$GITLAB_API/groups" \
    -d "name=System Alpha" \
    -d "path=system-alpha" \
    -d "visibility=internal")

  SYSTEM_ALPHA_GROUP_ID=$(echo "$RESPONSE" | jq -r '.id // empty')

  if [ -z "$SYSTEM_ALPHA_GROUP_ID" ]; then
    echo "❌ Failed to create system-alpha group"
    echo "Response: $RESPONSE"
    exit 1
  fi

  echo "✓ Created system-alpha group (ID: $SYSTEM_ALPHA_GROUP_ID)"
else
  echo "✓ System-alpha group already exists (ID: $SYSTEM_ALPHA_GROUP_ID)"
fi

# Check if System-Alpha repo exists
SYSTEM_ALPHA_PROJECT_ID=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
  "$GITLAB_API/projects?search=system-alpha-infra" | jq -r '.[] | select(.path_with_namespace=="system-alpha/system-alpha-infra") | .id // empty')

if [ -z "$SYSTEM_ALPHA_PROJECT_ID" ]; then
  echo "Creating system-alpha-infra repository..."
  RESPONSE=$(curl -s -X POST -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
    "$GITLAB_API/projects" \
    -d "name=system-alpha-infra" \
    -d "namespace_id=$SYSTEM_ALPHA_GROUP_ID" \
    -d "visibility=internal" \
    -d "initialize_with_readme=false")

  SYSTEM_ALPHA_PROJECT_ID=$(echo "$RESPONSE" | jq -r '.id // empty')

  if [ -z "$SYSTEM_ALPHA_PROJECT_ID" ]; then
    echo "❌ Failed to create system-alpha-infra repository"
    echo "Response: $RESPONSE"
    exit 1
  fi

  echo "✓ Created system-alpha-infra repository (ID: $SYSTEM_ALPHA_PROJECT_ID)"
else
  echo "✓ System-alpha-infra repository already exists (ID: $SYSTEM_ALPHA_PROJECT_ID)"
fi

echo ""
echo "Step 3: Create System-Beta repository"
echo "------------------------------------"

# Check if System-Beta group exists
SYSTEM_BETA_GROUP_ID=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
  "$GITLAB_API/groups/system-beta" | jq -r '.id // empty')

if [ -z "$SYSTEM_BETA_GROUP_ID" ]; then
  echo "Creating system-beta group..."
  RESPONSE=$(curl -s -X POST -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
    "$GITLAB_API/groups" \
    -d "name=System Beta" \
    -d "path=system-beta" \
    -d "visibility=internal")

  SYSTEM_BETA_GROUP_ID=$(echo "$RESPONSE" | jq -r '.id // empty')

  if [ -z "$SYSTEM_BETA_GROUP_ID" ]; then
    echo "❌ Failed to create system-beta group"
    echo "Response: $RESPONSE"
    exit 1
  fi

  echo "✓ Created system-beta group (ID: $SYSTEM_BETA_GROUP_ID)"
else
  echo "✓ System-beta group already exists (ID: $SYSTEM_BETA_GROUP_ID)"
fi

# Check if System-Beta repo exists
SYSTEM_BETA_PROJECT_ID=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
  "$GITLAB_API/projects?search=system-beta-infra" | jq -r '.[] | select(.path_with_namespace=="system-beta/system-beta-infra") | .id // empty')

if [ -z "$SYSTEM_BETA_PROJECT_ID" ]; then
  echo "Creating system-beta-infra repository..."
  RESPONSE=$(curl -s -X POST -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
    "$GITLAB_API/projects" \
    -d "name=system-beta-infra" \
    -d "namespace_id=$SYSTEM_BETA_GROUP_ID" \
    -d "visibility=internal" \
    -d "initialize_with_readme=false")

  SYSTEM_BETA_PROJECT_ID=$(echo "$RESPONSE" | jq -r '.id // empty')

  if [ -z "$SYSTEM_BETA_PROJECT_ID" ]; then
    echo "❌ Failed to create system-beta-infra repository"
    echo "Response: $RESPONSE"
    exit 1
  fi

  echo "✓ Created system-beta-infra repository (ID: $SYSTEM_BETA_PROJECT_ID)"
else
  echo "✓ System-beta-infra repository already exists (ID: $SYSTEM_BETA_PROJECT_ID)"
fi

echo ""
echo "Step 4: Push System-Alpha demo content"
echo "--------------------------------------"

# Create temporary directory for git operations
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# System-Alpha repo
cd "$TEMP_DIR"
if git clone "$GITLAB_URL/system-alpha/system-alpha-infra.git" 2>/dev/null; then
  cd system-alpha-infra
else
  # If clone fails, initialize new repo
  mkdir system-alpha-infra
  cd system-alpha-infra
  git init
  git remote add origin "$GITLAB_URL/system-alpha/system-alpha-infra.git"
fi

# Configure git for this repo
git config user.name "Administrator"
git config user.email "admin@atlantis-demo.local"
git config commit.gpgsign false

# Copy demo files
cp -r "$PROJECT_ROOT/demo-repos/system-alpha-infra/"* .

# Commit and push
git add .
if git diff --cached --quiet; then
  echo "✓ No changes to commit for system-alpha-infra"
else
  git commit -m "Initial Terraform configuration for System Alpha

Auto-detect projects pattern with separate dev/ and prod/ directories.
Each environment is discovered automatically by Atlantis."

  # Push using token authentication
  git push "http://root:$GITLAB_ROOT_TOKEN@gitlab.127.0.0.1.nip.io/system-alpha/system-alpha-infra.git" main 2>&1 || {
    # If main doesn't exist, try master or create main
    git checkout -b main 2>/dev/null || true
    git push -u "http://root:$GITLAB_ROOT_TOKEN@gitlab.127.0.0.1.nip.io/system-alpha/system-alpha-infra.git" main
  }

  echo "✓ Pushed system-alpha-infra content"
fi

echo ""
echo "Step 5: Push System-Beta demo content"
echo "-------------------------------------"

cd "$TEMP_DIR"
if git clone "$GITLAB_URL/system-beta/system-beta-infra.git" 2>/dev/null; then
  cd system-beta-infra
else
  # If clone fails, initialize new repo
  mkdir system-beta-infra
  cd system-beta-infra
  git init
  git remote add origin "$GITLAB_URL/system-beta/system-beta-infra.git"
fi

# Configure git for this repo
git config user.name "Administrator"
git config user.email "admin@atlantis-demo.local"
git config commit.gpgsign false

# Copy demo files
cp -r "$PROJECT_ROOT/demo-repos/system-beta-infra/"* .

# Commit and push
git add .
if git diff --cached --quiet; then
  echo "✓ No changes to commit for system-beta-infra"
else
  git commit -m "Initial Terraform configuration for System Beta

Workspace-based pattern with atlantis.yaml defining dev and prod projects.
Shared code with environment-specific configuration via workspaces."

  # Push using token authentication
  git push "http://root:$GITLAB_ROOT_TOKEN@gitlab.127.0.0.1.nip.io/system-beta/system-beta-infra.git" main 2>&1 || {
    # If main doesn't exist, try master or create main
    git checkout -b main 2>/dev/null || true
    git push -u "http://root:$GITLAB_ROOT_TOKEN@gitlab.127.0.0.1.nip.io/system-beta/system-beta-infra.git" main
  }

  echo "✓ Pushed system-beta-infra content"
fi

echo ""
echo "Step 6: Add developer as repository member"
echo "------------------------------------------"

# Add developer to System-Alpha repo
echo "Adding developer to system-alpha-infra..."
curl -s -X POST -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
  "$GITLAB_API/projects/$SYSTEM_ALPHA_PROJECT_ID/members" \
  -d "user_id=$DEVELOPER_ID" \
  -d "access_level=30" > /dev/null # 30 = Developer role

echo "✓ Added developer to system-alpha-infra"

# Add developer to System-Beta repo
echo "Adding developer to system-beta-infra..."
curl -s -X POST -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
  "$GITLAB_API/projects/$SYSTEM_BETA_PROJECT_ID/members" \
  -d "user_id=$DEVELOPER_ID" \
  -d "access_level=30" > /dev/null # 30 = Developer role

echo "✓ Added developer to system-beta-infra"

echo ""
echo "Step 7: Add atlantis-bot as repository member"
echo "---------------------------------------------"

# Get atlantis-bot user ID
ATLANTIS_BOT_ID=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
  "$GITLAB_API/users?username=atlantis-bot" | jq -r '.[0].id // empty')

if [ -z "$ATLANTIS_BOT_ID" ]; then
  echo "❌ Could not find atlantis-bot user"
  echo "Make sure Phase 5 has been completed"
  exit 1
fi

# Add atlantis-bot to System-Alpha repo (Maintainer role = 40)
echo "Adding atlantis-bot to system-alpha-infra..."
EXISTING_MEMBER=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
  "$GITLAB_API/projects/$SYSTEM_ALPHA_PROJECT_ID/members/$ATLANTIS_BOT_ID" | jq -r '.id // empty')

if [ -n "$EXISTING_MEMBER" ]; then
  echo "✓ atlantis-bot is already a member of system-alpha-infra"
else
  curl -s -X POST -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
    "$GITLAB_API/projects/$SYSTEM_ALPHA_PROJECT_ID/members" \
    -d "user_id=$ATLANTIS_BOT_ID" \
    -d "access_level=40" > /dev/null # 40 = Maintainer role
  echo "✓ Added atlantis-bot to system-alpha-infra"
fi

# Add atlantis-bot to System-Beta repo (Maintainer role = 40)
echo "Adding atlantis-bot to system-beta-infra..."
EXISTING_MEMBER=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
  "$GITLAB_API/projects/$SYSTEM_BETA_PROJECT_ID/members/$ATLANTIS_BOT_ID" | jq -r '.id // empty')

if [ -n "$EXISTING_MEMBER" ]; then
  echo "✓ atlantis-bot is already a member of system-beta-infra"
else
  curl -s -X POST -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
    "$GITLAB_API/projects/$SYSTEM_BETA_PROJECT_ID/members" \
    -d "user_id=$ATLANTIS_BOT_ID" \
    -d "access_level=40" > /dev/null # 40 = Maintainer role
  echo "✓ Added atlantis-bot to system-beta-infra"
fi

echo ""
echo "Step 8: Configure GitLab webhooks"
echo "---------------------------------"

# Enable local network requests for webhooks (if not already enabled)
echo "Enabling local network requests from webhooks..."
curl -s -X PUT -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"allow_local_requests_from_web_hooks_and_services": true}' \
  "$GITLAB_API/application/settings" > /dev/null

# Configure webhook for System-Alpha
echo ""
echo "Configuring webhook for system-alpha-infra..."

# Construct webhook URL (predictable pattern)
WEBHOOK_URL_ALPHA="http://atlantis-alpha.127.0.0.1.nip.io/events"

# Get webhook secret from Kubernetes (atlantis namespace)
WEBHOOK_SECRET_ALPHA=$(kubectl get secret -n atlantis atlantis-system-alpha-webhook -o jsonpath='{.data.secret}' 2>/dev/null | base64 -d || echo "")

if [ -z "$WEBHOOK_SECRET_ALPHA" ]; then
  echo "⚠️  WARNING: Could not get webhook secret for System-Alpha from Kubernetes"
  echo "Make sure Phase 8 has been completed"
else
  # Check for existing webhook
  EXISTING_HOOK_ID=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
    "$GITLAB_API/projects/$SYSTEM_ALPHA_PROJECT_ID/hooks" | \
    jq -r ".[] | select(.url == \"$WEBHOOK_URL_ALPHA\") | .id // empty")

  HOOK_DATA="{
    \"url\": \"$WEBHOOK_URL_ALPHA\",
    \"token\": \"$WEBHOOK_SECRET_ALPHA\",
    \"push_events\": true,
    \"merge_requests_events\": true,
    \"note_events\": true,
    \"enable_ssl_verification\": false
  }"

  if [ -n "$EXISTING_HOOK_ID" ]; then
    echo "  Updating existing webhook (ID: $EXISTING_HOOK_ID)..."
    curl -s -X PUT -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$HOOK_DATA" \
      "$GITLAB_API/projects/$SYSTEM_ALPHA_PROJECT_ID/hooks/$EXISTING_HOOK_ID" > /dev/null
  else
    echo "  Creating new webhook..."
    curl -s -X POST -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$HOOK_DATA" \
      "$GITLAB_API/projects/$SYSTEM_ALPHA_PROJECT_ID/hooks" > /dev/null
  fi
  echo "✓ Configured webhook for system-alpha-infra"
fi

# Configure webhook for System-Beta
echo ""
echo "Configuring webhook for system-beta-infra..."

# Construct webhook URL (predictable pattern)
WEBHOOK_URL_BETA="http://atlantis-beta.127.0.0.1.nip.io/events"

# Get webhook secret from Kubernetes (atlantis namespace)
WEBHOOK_SECRET_BETA=$(kubectl get secret -n atlantis atlantis-system-beta-webhook -o jsonpath='{.data.secret}' 2>/dev/null | base64 -d || echo "")

if [ -z "$WEBHOOK_SECRET_BETA" ]; then
  echo "⚠️  WARNING: Could not get webhook secret for System-Beta from Kubernetes"
  echo "Make sure Phase 8 has been completed"
else
  # Check for existing webhook
  EXISTING_HOOK_ID=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
    "$GITLAB_API/projects/$SYSTEM_BETA_PROJECT_ID/hooks" | \
    jq -r ".[] | select(.url == \"$WEBHOOK_URL_BETA\") | .id // empty")

  HOOK_DATA="{
    \"url\": \"$WEBHOOK_URL_BETA\",
    \"token\": \"$WEBHOOK_SECRET_BETA\",
    \"push_events\": true,
    \"merge_requests_events\": true,
    \"note_events\": true,
    \"enable_ssl_verification\": false
  }"

  if [ -n "$EXISTING_HOOK_ID" ]; then
    echo "  Updating existing webhook (ID: $EXISTING_HOOK_ID)..."
    curl -s -X PUT -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$HOOK_DATA" \
      "$GITLAB_API/projects/$SYSTEM_BETA_PROJECT_ID/hooks/$EXISTING_HOOK_ID" > /dev/null
  else
    echo "  Creating new webhook..."
    curl -s -X POST -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$HOOK_DATA" \
      "$GITLAB_API/projects/$SYSTEM_BETA_PROJECT_ID/hooks" > /dev/null
  fi
  echo "✓ Configured webhook for system-beta-infra"
fi

echo ""
echo "Step 9: Configure approval rules"
echo "--------------------------------"

# Configure System-Alpha approval rules
echo "Configuring approval rules for system-alpha-infra..."

# Set project-level approval and merge settings
curl -s -X PUT -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
  "$GITLAB_API/projects/$SYSTEM_ALPHA_PROJECT_ID" \
  -d "merge_requests_author_approval=false" \
  -d "approvals_before_merge=1" \
  -d "only_allow_merge_if_all_discussions_are_resolved=true" \
  -d "only_allow_merge_if_pipeline_succeeds=true" > /dev/null

# Create approval rule
curl -s -X POST -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
  "$GITLAB_API/projects/$SYSTEM_ALPHA_PROJECT_ID/approval_rules" \
  -d "name=Maintainer Approval" \
  -d "approvals_required=1" > /dev/null

echo "✓ Configured approval rules for system-alpha-infra"

# Configure System-Beta approval rules
echo "Configuring approval rules for system-beta-infra..."

# Set project-level approval and merge settings
curl -s -X PUT -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
  "$GITLAB_API/projects/$SYSTEM_BETA_PROJECT_ID" \
  -d "merge_requests_author_approval=false" \
  -d "approvals_before_merge=1" \
  -d "only_allow_merge_if_all_discussions_are_resolved=true" \
  -d "only_allow_merge_if_pipeline_succeeds=true" > /dev/null

# Create approval rule
curl -s -X POST -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
  "$GITLAB_API/projects/$SYSTEM_BETA_PROJECT_ID/approval_rules" \
  -d "name=Maintainer Approval" \
  -d "approvals_required=1" > /dev/null

echo "✓ Configured approval rules for system-beta-infra"

echo ""
echo "=== Phase 9 Complete ==="
echo ""
echo "Demo repositories have been created and configured:"
echo ""
echo "System-Alpha (Auto-detect pattern):"
echo "  Repository: $GITLAB_URL/system-alpha/system-alpha-infra"
echo "  Pattern: Separate directories (dev/, prod/)"
echo "  Atlantis: Auto-discovers projects (no atlantis.yaml)"
echo ""
echo "System-Beta (Workspace-based pattern):"
echo "  Repository: $GITLAB_URL/system-beta/system-beta-infra"
echo "  Pattern: Shared code with workspace separation"
echo "  Atlantis: Explicit projects in atlantis.yaml"
echo ""
echo "Developer User:"
echo "  Username: $DEVELOPER_USERNAME"
echo "  Password: $DEVELOPER_PASSWORD"
echo "  Email: $DEVELOPER_EMAIL"
echo "  Access: Developer role on both repos"
echo ""
echo "Atlantis Bot:"
echo "  User: atlantis-bot"
echo "  Access: Maintainer role on both repos"
echo "  Webhooks: Configured for both repos"
echo ""
echo "Approval Rules:"
echo "  - 1 approval required before merge"
echo "  - Author cannot approve their own MRs"
echo "  - All discussions must be resolved"
echo "  - Pipeline (Atlantis) must succeed"
echo "  - Root user can approve as maintainer"
echo ""
echo "Next Steps:"
echo "  1. Atlantis will automatically detect these repos via repo-allowlist"
echo "  2. Test creating MRs as developer user"
echo "  3. Verify auto-plan triggers on both patterns"
echo "  4. Test approval workflow (developer creates MR, root approves)"
echo "  5. Verify Atlantis can apply after approval"
