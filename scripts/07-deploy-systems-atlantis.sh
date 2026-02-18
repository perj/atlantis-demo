#!/bin/bash
set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Phase 8: Deploy System Atlantis Servers"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check current Kubernetes context
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "none")
echo "Current Kubernetes context: $CURRENT_CONTEXT"
echo ""

if [ "$CURRENT_CONTEXT" != "kind-atlantis-demo" ]; then
    echo "WARNING: Expected context 'kind-atlantis-demo' but found '$CURRENT_CONTEXT'"
    echo ""
    read -p "Do you want to continue anyway? (yes/no): " continue_anyway
    if [ "$continue_anyway" != "yes" ]; then
        echo "Aborted. Switch context with: kubectl config use-context kind-atlantis-demo"
        exit 1
    fi
    echo ""
fi

# Configuration
GITLAB_URL="http://gitlab.127.0.0.1.nip.io"
GITLAB_TOKEN=$(kubectl get secret -n gitlab gitlab-root-token -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "")
MAIN_BRANCH="main"
BRANCH_NAME="add-system-atlantis-$(date +%Y%m%d-%H%M%S)"
MR_TITLE="Add System Atlantis Servers"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)

if [ -z "$GITLAB_TOKEN" ]; then
    echo "ERROR: Could not retrieve GitLab token from Kubernetes secret."
    echo "       Make sure the gitlab-root-token secret exists in the gitlab namespace."
    exit 1
fi

# Get the project ID for atlantis-demo
PROJECT_ID=$(curl -s --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    "${GITLAB_URL}/api/v4/projects?search=atlantis-demo" | jq -r '.[0].id')

if [ "$PROJECT_ID" = "null" ] || [ -z "$PROJECT_ID" ]; then
    echo "ERROR: Could not find atlantis-demo project in GitLab."
    exit 1
fi

echo "Found GitLab project: atlantis-demo (ID: $PROJECT_ID)"
echo ""

# Create branch
echo "Creating branch: $BRANCH_NAME"
git switch -c "$BRANCH_NAME"
echo ""

echo "Updating demo.tf configurations with timestamp to trigger plan..."

# Update the default value with current timestamp in system-alpha demo.tf
sed -i "s/default     = \".*\"/default     = \"$TIMESTAMP\"/" atlantis-servers/environments/system-alpha/demo.tf

# Update the default value with current timestamp in system-beta demo.tf
sed -i "s/default     = \".*\"/default     = \"$TIMESTAMP\"/" atlantis-servers/environments/system-beta/demo.tf

echo "  Updated timestamp to: $TIMESTAMP"
echo ""

# Stage and commit changes
echo "Committing changes..."
git add atlantis-servers/environments/system-alpha/
git add atlantis-servers/environments/system-beta/
git add atlantis.yaml

COMMIT_MESSAGE="Deploy System Atlantis servers (demo run: $TIMESTAMP)

Updates System Atlantis server configurations:
- System Alpha Atlantis deployment
- System Beta Atlantis deployment

Updated timestamp: $TIMESTAMP

This demonstrates the PR workflow for managing Atlantis infrastructure."

git commit -m "$COMMIT_MESSAGE"
echo ""

# Push to GitLab
echo "Pushing to GitLab..."
git push demo "$BRANCH_NAME"
echo ""

# Create Merge Request via GitLab API
echo "Creating Merge Request..."

MR_DESCRIPTION="## Deploy System Atlantis Servers

This MR deploys/updates two system-specific Atlantis instances via Platform Atlantis:

### System Alpha Atlantis
- **Instance name:** \`atlantis-system-alpha\`
- **Monitors:** \`system-alpha-infra\` repository (will be created in Phase 9)
- **URL:** http://atlantis-alpha.127.0.0.1.nip.io
- **Target namespace:** \`system-alpha\` (namespace-scoped RBAC)
- **Feature:** Auto-detect projects (no atlantis.yaml required in repo)
- **State:** MinIO at \`atlantis-servers/system-alpha/terraform.tfstate\`

### System Beta Atlantis
- **Instance name:** \`atlantis-system-beta\`
- **Monitors:** \`system-beta-infra\` repository (will be created in Phase 9)
- **URL:** http://atlantis-beta.127.0.0.1.nip.io
- **Target namespace:** \`system-beta\` (namespace-scoped RBAC)
- **Feature:** Workspace-based environments (dev/prod projects in atlantis.yaml)
- **State:** MinIO at \`atlantis-servers/system-beta/terraform.tfstate\`

### Security Model
- App developers interact with system Atlantis **only via GitLab MRs**
- App developers have **no access** to:
  - \`atlantis\` namespace (where Atlantis servers run)
  - \`minio\` namespace (where Terraform state is stored)
  - Terraform state files
- Only platform developers can access Atlantis infrastructure

### Demo Run Timestamp
Updated to: \`$TIMESTAMP\`

### What happens next:
1. Platform Atlantis will auto-plan in ~30 seconds
2. Review the plan in this MR's comments
3. Comment \`atlantis apply\` to deploy/update
4. After apply, system Atlantis servers will be available"

MR_RESPONSE=$(curl -s --request POST \
    --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    --header "Content-Type: application/json" \
    --data "{
        \"source_branch\": \"${BRANCH_NAME}\",
        \"target_branch\": \"${MAIN_BRANCH}\",
        \"title\": \"${MR_TITLE}\",
        \"description\": $(echo "$MR_DESCRIPTION" | jq -Rs .),
        \"remove_source_branch\": true
    }" \
    "${GITLAB_URL}/api/v4/projects/${PROJECT_ID}/merge_requests")

MR_IID=$(echo "$MR_RESPONSE" | jq -r '.iid // empty')
MR_WEB_URL=$(echo "$MR_RESPONSE" | jq -r '.web_url // empty')

if [ -z "$MR_IID" ]; then
    echo "ERROR: Failed to create Merge Request"
    echo "$MR_RESPONSE" | jq .
    exit 1
fi

# Switch back to main branch
echo "Switching back to main branch..."
git switch "$MAIN_BRANCH"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Merge Request Created Successfully!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 MR Details:"
echo "   Title: $MR_TITLE"
echo "   URL: $MR_WEB_URL"
echo ""
echo "🤖 Platform Atlantis will auto-plan in ~30 seconds:"
echo "   Monitor: http://atlantis-platform.127.0.0.1.nip.io"
echo ""
echo "📝 Next Steps:"
echo "   1. View auto-plan in MR comments"
echo "   2. Review the plan shows 2 new Atlantis deployments"
echo "   3. Comment \"atlantis apply\" to deploy"
echo ""
echo "🎯 After apply, system Atlantis servers will be available at:"
echo "   • System Alpha: http://atlantis-alpha.127.0.0.1.nip.io"
echo "   • System Beta:  http://atlantis-beta.127.0.0.1.nip.io"
echo ""
echo "💡 Note: The system repos (system-alpha-infra, system-beta-infra)"
echo "   will be created in Phase 9. For now, the Atlantis servers"
echo "   will be deployed but won't detect any repos until then."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
