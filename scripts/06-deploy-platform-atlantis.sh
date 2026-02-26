#!/bin/bash
set -e

echo "=== Deploying Platform Atlantis (Bootstrap) ==="
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

# Verify prerequisites from previous phases
echo "Checking prerequisites..."

if ! kubectl get namespace atlantis &>/dev/null; then
    echo "ERROR: 'atlantis' namespace not found. Run Phase 5 first: ./scripts/05-configure-shared-resources.sh"
    exit 1
fi

if ! kubectl get secret gitlab-credentials -n atlantis &>/dev/null; then
    echo "ERROR: 'gitlab-credentials' secret not found in atlantis namespace. Run Phase 5 first."
    exit 1
fi

if ! kubectl get secret minio-credentials -n atlantis &>/dev/null; then
    echo "ERROR: 'minio-credentials' secret not found in atlantis namespace. Run Phase 5 first."
    exit 1
fi

echo "  Prerequisites OK"
echo ""

echo "This script will:"
echo "  - Deploy Platform Atlantis to the 'atlantis' namespace"
echo "  - Configure GitLab webhook for the atlantis-demo repository"
echo "  - Add atlantis-bot as a member of the repository"
echo ""

# Change to the platform environment directory
cd atlantis-servers/environments/platform

echo "Step 1: Initializing Terraform..."
terraform init

echo ""
echo "Step 2: Applying Terraform configuration..."
terraform apply

echo ""
echo "Step 3: Configuring GitLab webhook..."

# Get webhook URL and secret from Terraform outputs
WEBHOOK_URL=$(terraform output -raw webhook_url)
WEBHOOK_SECRET=$(terraform output -raw webhook_secret)

# Get GitLab token
GITLAB_TOKEN=$(kubectl get secret -n gitlab gitlab-root-token -o jsonpath='{.data.password}' | base64 -d)
GITLAB_URL="http://gitlab.127.0.0.1.nip.io"

# Get the project ID for atlantis-demo
PROJECT_ID=$(curl -s --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    "${GITLAB_URL}/api/v4/projects?search=atlantis-demo" | jq -r '.[0].id')

if [ "$PROJECT_ID" = "null" ] || [ -z "$PROJECT_ID" ]; then
    echo "ERROR: Could not find atlantis-demo project in GitLab."
    echo "       Run Phase 4 first: ./scripts/04-create-repo.sh"
    exit 1
fi

# Allow webhooks to local network addresses (required for in-cluster URLs)
echo "  Enabling local network requests from webhooks..."
curl -s --request PUT \
    --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    --header "Content-Type: application/json" \
    --data '{"allow_local_requests_from_web_hooks_and_services": true}' \
    "${GITLAB_URL}/api/v4/application/settings" | jq '.allow_local_requests_from_web_hooks_and_services'

echo "  Found project atlantis-demo (ID: $PROJECT_ID)"

# Add atlantis-bot as a project member (Maintainer role = 40)
ATLANTIS_BOT_ID=$(curl -s --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    "${GITLAB_URL}/api/v4/users?username=atlantis-bot" | jq -r '.[0].id')

if [ "$ATLANTIS_BOT_ID" = "null" ] || [ -z "$ATLANTIS_BOT_ID" ]; then
    echo "ERROR: Could not find atlantis-bot user. Run Phase 5 first."
    exit 1
fi

# Check if atlantis-bot is already a project member
EXISTING_MEMBER=$(curl -s --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    "${GITLAB_URL}/api/v4/projects/${PROJECT_ID}/members/${ATLANTIS_BOT_ID}" | jq -r '.id // empty')

if [ -n "$EXISTING_MEMBER" ]; then
    echo "  atlantis-bot is already a project member (skipping)"
else
    echo "  Adding atlantis-bot (ID: $ATLANTIS_BOT_ID) as project maintainer..."
    curl -s --request POST \
        --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
        --header "Content-Type: application/json" \
        --data "{\"user_id\": ${ATLANTIS_BOT_ID}, \"access_level\": 40}" \
        "${GITLAB_URL}/api/v4/projects/${PROJECT_ID}/members" | jq .
fi

echo ""

# Create or update webhook (find existing by URL match)
EXISTING_HOOK_ID=$(curl -s --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    "${GITLAB_URL}/api/v4/projects/${PROJECT_ID}/hooks" | jq -r ".[] | select(.url == \"${WEBHOOK_URL}\") | .id // empty")

HOOK_DATA="{
    \"url\": \"${WEBHOOK_URL}\",
    \"token\": \"${WEBHOOK_SECRET}\",
    \"push_events\": true,
    \"merge_requests_events\": true,
    \"note_events\": true,
    \"enable_ssl_verification\": false
}"

# Look and retry since the webhook setting change above might take a while to take effect.
for attempt in $(seq 1 5); do
    if [ -n "$EXISTING_HOOK_ID" ]; then
        echo "  Updating existing webhook (ID: $EXISTING_HOOK_ID)..."
        HOOK_RESULT=$(curl -s --request PUT \
            --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
            --header "Content-Type: application/json" \
            --data "$HOOK_DATA" \
            "${GITLAB_URL}/api/v4/projects/${PROJECT_ID}/hooks/${EXISTING_HOOK_ID}")
    else
        echo "  Creating webhook..."
        HOOK_RESULT=$(curl -s --request POST \
            --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
            --header "Content-Type: application/json" \
            --data "$HOOK_DATA" \
            "${GITLAB_URL}/api/v4/projects/${PROJECT_ID}/hooks")
    fi

    if echo "$HOOK_RESULT" | jq -e '.id' &>/dev/null; then
        echo "$HOOK_RESULT" | jq .
        break
    fi

    if [ "$attempt" -eq 5 ]; then
        echo "  ERROR: Failed to create webhook after 5 attempts:"
        echo "$HOOK_RESULT" | jq .
        exit 1
    fi

    echo "  Webhook creation failed (attempt $attempt/5), retrying in 3s..."
    sleep 3
done

echo ""
echo "Step 4: Verifying deployment..."

# Wait for the deployment to be ready
echo "  Waiting for Platform Atlantis deployment to be ready..."
kubectl rollout status deployment/atlantis-platform -n atlantis --timeout=120s

ATLANTIS_URL=$(terraform output -raw atlantis_url)

echo ""
echo "=== Platform Atlantis Deployment Complete ==="
echo ""
echo "Resources created:"
echo "  - Deployment: atlantis-platform (in atlantis namespace)"
echo "  - Service: atlantis-platform"
echo "  - Ingress: atlantis-platform"
echo "  - ServiceAccount: atlantis-platform"
echo "  - RBAC: edit role in atlantis namespace"
echo "  - GitLab webhook for atlantis-demo repository"
echo ""
echo "Platform Atlantis UI: ${ATLANTIS_URL}"
echo ""
echo "To verify:"
echo "  kubectl get pods -n atlantis"
echo "  curl -s ${ATLANTIS_URL}/healthz"
echo ""
echo "Next step: ./scripts/07-deploy-systems-atlantis.sh - Deploy System Atlantis servers via PR workflow"
echo ""
