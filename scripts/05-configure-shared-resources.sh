#!/bin/bash
set -e

echo "=== Configuring Shared Resources (Bootstrap) ==="
echo ""

# Check current Kubernetes context
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "none")
echo "Current Kubernetes context: $CURRENT_CONTEXT"
echo ""

if [ "$CURRENT_CONTEXT" != "kind-atlantis-demo" ]; then
    echo "⚠️  WARNING: Expected context 'kind-atlantis-demo' but found '$CURRENT_CONTEXT'"
    echo ""
    read -p "Do you want to continue anyway? (yes/no): " continue_anyway
    if [ "$continue_anyway" != "yes" ]; then
        echo "Aborted. Switch context with: kubectl config use-context kind-atlantis-demo"
        exit 1
    fi
    echo ""
fi

echo "This script will create:"
echo "  - Kubernetes namespace: atlantis"
echo "  - GitLab user: atlantis-bot"
echo "  - GitLab personal access token (api scope)"
echo "  - Kubernetes secret with GitLab credentials in atlantis namespace"
echo ""

# Change to the shared resources directory
cd atlantis-servers/shared

echo "Step 1: Initializing Terraform..."
terraform init

echo ""
echo "Step 2: Applying Terraform configuration..."
terraform apply

echo ""
echo "=== Shared Resources Configuration Complete ==="
echo ""
echo "Resources created:"
echo "  ✓ Kubernetes namespace: atlantis"
echo "  ✓ GitLab user: atlantis-bot"
echo "  ✓ GitLab personal access token"
echo "  ✓ Kubernetes secret: gitlab-credentials (in atlantis namespace)"
echo ""
echo "To view outputs:"
echo "  terraform output"
echo ""
echo "To view the atlantis-bot token (sensitive):"
echo "  terraform output -raw atlantis_bot_token"
echo ""
echo "To verify Kubernetes resources:"
echo "  kubectl get namespace atlantis"
echo "  kubectl get secret gitlab-credentials -n atlantis"
echo ""
echo "Next step: Phase 6 - Deploy Platform Atlantis"
echo "  Run: ./scripts/06-deploy-platform-atlantis.sh"
echo ""
