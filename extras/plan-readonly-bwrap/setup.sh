#!/bin/bash
# setup.sh
#
# Deploys the plan-readonly-bwrap Atlantis instance and creates the matching
# GitLab repository, fully wired up and ready to demo.
#
# Prerequisites: full demo setup must already be running (scripts 01-08).

set -euo pipefail

ADDON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$ADDON_DIR/../.." && pwd)"

INSTANCE="readonly-bwrap"
NAMESPACE="atlantis"
TARGET_NAMESPACE="system-alpha"  # The namespace the demo infra actually deploys to
ATLANTIS_HOST="atlantis-readonly-bwrap.127.0.0.1.nip.io"
GITLAB_URL="http://gitlab.127.0.0.1.nip.io"
GITLAB_API="$GITLAB_URL/api/v4"
GITLAB_GROUP="readonly-bwrap"
GITLAB_REPO="readonly-bwrap-infra"
REPO_PATH="$GITLAB_GROUP/$GITLAB_REPO"
IMAGE_NAME="atlantis-bwrap:local"

echo "========================================================"
echo "  plan-readonly-bwrap"
echo "  Instance : $INSTANCE"
echo "  Host     : $ATLANTIS_HOST"
echo "  Repo     : $GITLAB_URL/$REPO_PATH"
echo "========================================================"
echo ""

# ---- Preflight: kubectl context ---------------------------------------------

CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "none")
if [ "$CURRENT_CONTEXT" != "kind-atlantis-demo" ]; then
  echo "WARNING: Current context is '$CURRENT_CONTEXT', expected 'kind-atlantis-demo'"
  read -p "Continue anyway? (yes/no): " _continue
  if [ "$_continue" != "yes" ]; then
    echo "Aborted. Switch with: kubectl config use-context kind-atlantis-demo"
    exit 1
  fi
fi

# ---- Preflight: GitLab credentials ------------------------------------------

GITLAB_ROOT_TOKEN=$(kubectl get secret -n gitlab gitlab-root-token \
  -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "")

if [ -z "$GITLAB_ROOT_TOKEN" ]; then
  echo "ERROR: Could not retrieve GitLab root token from Kubernetes."
  echo "Make sure script 02 has been completed."
  exit 1
fi

ATLANTIS_BOT_ID=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
  "$GITLAB_API/users?username=atlantis-bot" | jq -r '.[0].id // empty')

if [ -z "$ATLANTIS_BOT_ID" ]; then
  echo "ERROR: Could not find atlantis-bot user. Make sure script 05 has been completed."
  exit 1
fi

echo "✓ Preflight checks passed"
echo ""

# =============================================================================
# Step 1: Build and load the custom Atlantis image
# =============================================================================

echo "==> [1/5] Building atlantis-bwrap image..."
cd "$ADDON_DIR"
docker build -t "$IMAGE_NAME" .
echo "    ✓ Image built"

echo "==> Loading image into Kind cluster..."
kind load docker-image "$IMAGE_NAME" --name atlantis-demo
echo "    ✓ Image loaded"
echo ""

# =============================================================================
# Step 2: Terraform — deploy the Atlantis instance
# =============================================================================

echo "==> [2/5] Deploying Atlantis instance '$INSTANCE'..."
cd "$ADDON_DIR"

terraform init -input=false

terraform apply \
  -input=false \
  -auto-approve \
  -var "instance_name=$INSTANCE" \
  -var "namespace=$NAMESPACE" \
  -var "atlantis_host=$ATLANTIS_HOST" \
  -var "atlantis_image=$IMAGE_NAME" \
  -var "repo_allowlist=[\"gitlab.127.0.0.1.nip.io/$REPO_PATH\"]" \
  -var "target_namespaces=[\"$TARGET_NAMESPACE\"]"

echo ""

# =============================================================================
# Step 3: GitLab — create group and repository
# =============================================================================

echo "==> [3/5] Creating GitLab group and repository..."

GROUP_ID=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
  "$GITLAB_API/groups/$GITLAB_GROUP" | jq -r '.id // empty')

if [ -z "$GROUP_ID" ]; then
  RESPONSE=$(curl -s -X POST -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
    "$GITLAB_API/groups" \
    -d "name=Readonly Bwrap" \
    -d "path=$GITLAB_GROUP" \
    -d "visibility=internal")
  GROUP_ID=$(echo "$RESPONSE" | jq -r '.id // empty')
  if [ -z "$GROUP_ID" ]; then
    echo "ERROR: Failed to create GitLab group. Response: $RESPONSE"
    exit 1
  fi
  echo "  ✓ Created group '$GITLAB_GROUP' (ID: $GROUP_ID)"
else
  echo "  ✓ Group '$GITLAB_GROUP' already exists (ID: $GROUP_ID)"
fi

PROJECT_ID=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
  "$GITLAB_API/projects?search=$GITLAB_REPO" | \
  jq -r ".[] | select(.path_with_namespace==\"$REPO_PATH\") | .id // empty")

if [ -z "$PROJECT_ID" ]; then
  RESPONSE=$(curl -s -X POST -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
    "$GITLAB_API/projects" \
    -d "name=$GITLAB_REPO" \
    -d "namespace_id=$GROUP_ID" \
    -d "visibility=internal" \
    -d "initialize_with_readme=false")
  PROJECT_ID=$(echo "$RESPONSE" | jq -r '.id // empty')
  if [ -z "$PROJECT_ID" ]; then
    echo "ERROR: Failed to create repository. Response: $RESPONSE"
    exit 1
  fi
  echo "  ✓ Created repository '$GITLAB_REPO' (ID: $PROJECT_ID)"
else
  echo "  ✓ Repository '$GITLAB_REPO' already exists (ID: $PROJECT_ID)"
fi

# =============================================================================
# Step 4: Push demo content and configure members
# =============================================================================

echo ""
echo "==> [4/5] Pushing demo content and configuring members..."

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

cd "$TEMP_DIR"
if git clone "$GITLAB_URL/$REPO_PATH.git" 2>/dev/null; then
  cd "$GITLAB_REPO"
else
  mkdir "$GITLAB_REPO"
  cd "$GITLAB_REPO"
  git init
  git remote add origin "$GITLAB_URL/$REPO_PATH.git"
fi

git config user.name "Administrator"
git config user.email "admin@atlantis-demo.local"
git config commit.gpgsign false

# Use the system-alpha-infra terraform content (same dir-per-environment layout).
# The atlantis.yaml from this addon provides the project definitions; the
# workflow itself lives server-side in repos.yaml so repos cannot override it.
cp -r "$PROJECT_ROOT/demo-repos/system-alpha-infra/"* .
cp "$ADDON_DIR/atlantis.yaml" .

git add .
if git diff --cached --quiet; then
  echo "  ✓ No changes to commit"
else
  git commit -m "Terraform config for readonly-bwrap demo

Demonstrates plan isolation via bwrap: terraform plan runs inside a
bwrap sandbox where the read-write SA token is replaced with a short-lived
readonly token. The rw token is physically inaccessible to any provider
code running during plan. Apply uses the full-access SA as normal."
  git push "http://root:$GITLAB_ROOT_TOKEN@gitlab.127.0.0.1.nip.io/$REPO_PATH.git" main 2>&1 || {
    git checkout -b main 2>/dev/null || true
    git push -u "http://root:$GITLAB_ROOT_TOKEN@gitlab.127.0.0.1.nip.io/$REPO_PATH.git" main
  }
  echo "  ✓ Pushed demo content"
fi

# Add developer as member (best-effort — developer user may not exist yet)
DEVELOPER_ID=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
  "$GITLAB_API/users?username=developer" | jq -r '.[0].id // empty')
if [ -n "$DEVELOPER_ID" ]; then
  curl -s -X POST -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
    "$GITLAB_API/projects/$PROJECT_ID/members" \
    -d "user_id=$DEVELOPER_ID" \
    -d "access_level=30" > /dev/null  # Developer role
  echo "  ✓ Added developer to $GITLAB_REPO"
fi

# Add atlantis-bot as maintainer
EXISTING=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
  "$GITLAB_API/projects/$PROJECT_ID/members/$ATLANTIS_BOT_ID" | jq -r '.id // empty')
if [ -z "$EXISTING" ]; then
  curl -s -X POST -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
    "$GITLAB_API/projects/$PROJECT_ID/members" \
    -d "user_id=$ATLANTIS_BOT_ID" \
    -d "access_level=40" > /dev/null  # Maintainer role
fi
echo "  ✓ Added atlantis-bot to $GITLAB_REPO"

# =============================================================================
# Step 5: Webhook and approval rules
# =============================================================================

echo ""
echo "==> [5/5] Configuring webhook and approval rules..."

# Allow local network requests (needed for nip.io webhooks — idempotent)
curl -s -X PUT -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"allow_local_requests_from_web_hooks_and_services": true}' \
  "$GITLAB_API/application/settings" > /dev/null

WEBHOOK_SECRET=$(kubectl get secret -n "$NAMESPACE" \
  "atlantis-${INSTANCE}-webhook" \
  -o jsonpath='{.data.secret}' | base64 -d)

WEBHOOK_URL="http://$ATLANTIS_HOST/events"

EXISTING_HOOK=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
  "$GITLAB_API/projects/$PROJECT_ID/hooks" | \
  jq -r ".[] | select(.url == \"$WEBHOOK_URL\") | .id // empty")

HOOK_DATA="{
  \"url\": \"$WEBHOOK_URL\",
  \"token\": \"$WEBHOOK_SECRET\",
  \"push_events\": true,
  \"merge_requests_events\": true,
  \"note_events\": true,
  \"enable_ssl_verification\": false
}"

if [ -n "$EXISTING_HOOK" ]; then
  curl -s -X PUT -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$HOOK_DATA" \
    "$GITLAB_API/projects/$PROJECT_ID/hooks/$EXISTING_HOOK" > /dev/null
else
  curl -s -X POST -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$HOOK_DATA" \
    "$GITLAB_API/projects/$PROJECT_ID/hooks" > /dev/null
fi
echo "  ✓ Webhook configured ($WEBHOOK_URL)"

ROOT_USER_ID=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
  "$GITLAB_API/users?username=root" | jq -r '.[0].id // empty')

curl -s -X PUT -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
  "$GITLAB_API/projects/$PROJECT_ID" \
  -d "merge_requests_author_approval=false" \
  -d "approvals_before_merge=1" \
  -d "only_allow_merge_if_all_discussions_are_resolved=true" \
  -d "only_allow_merge_if_pipeline_succeeds=true" > /dev/null

curl -s -X POST -H "PRIVATE-TOKEN: $GITLAB_ROOT_TOKEN" \
  "$GITLAB_API/projects/$PROJECT_ID/approval_rules" \
  -d "name=Maintainer Approval" \
  -d "approvals_required=1" \
  -d "user_ids[]=$ROOT_USER_ID" > /dev/null
echo "  ✓ Approval rules configured"

# =============================================================================

echo ""
echo "========================================================"
echo "  Setup complete!"
echo ""
echo "  Atlantis : http://$ATLANTIS_HOST"
echo "  Repo     : $GITLAB_URL/$REPO_PATH"
echo ""
echo "  Open a branch in $REPO_PATH and create a MR to see"
echo "  terraform plan run inside a bwrap credential sandbox."
echo "  The rw SA token is physically inaccessible during plan."
echo "========================================================"
