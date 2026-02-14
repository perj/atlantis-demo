#!/usr/bin/env bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GITLAB_K8S_DIR="${PROJECT_ROOT}/kubernetes/gitlab"

# Configuration
CLUSTER_NAME="atlantis-demo"
NAMESPACE="gitlab"
KUBECTL_WAIT_TIMEOUT="600s"
GITLAB_URL="http://gitlab.127.0.0.1.nip.io"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

verify_context() {
    log_info "Verifying kubectl context..."

    CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "none")
    EXPECTED_CONTEXT="kind-${CLUSTER_NAME}"

    if [ "${CURRENT_CONTEXT}" != "${EXPECTED_CONTEXT}" ]; then
        log_warning "Current context is '${CURRENT_CONTEXT}', expected '${EXPECTED_CONTEXT}'"

        # Check if the expected context exists
        if kubectl config get-contexts "${EXPECTED_CONTEXT}" &>/dev/null; then
            log_info "Switching to '${EXPECTED_CONTEXT}' context..."
            kubectl config use-context "${EXPECTED_CONTEXT}"
            log_success "Context switched to '${EXPECTED_CONTEXT}'"
        else
            log_error "Context '${EXPECTED_CONTEXT}' not found. Did you run 01-setup-kind.sh?"
            log_error "Available contexts:"
            kubectl config get-contexts
            exit 1
        fi
    else
        log_success "Already using correct context: ${EXPECTED_CONTEXT}"
    fi

    # Verify cluster is accessible
    if ! kubectl cluster-info &>/dev/null; then
        log_error "Cannot access cluster. Is it running?"
        exit 1
    fi
}

generate_root_password() {
    log_info "Generating GitLab root password..." >&2

    # Use a fixed password for demo
    GITLAB_ROOT_PASSWORD="atlantisdemo123"

    log_success "Root password generated" >&2
    echo "${GITLAB_ROOT_PASSWORD}"
}

create_namespace() {
    log_info "Creating GitLab namespace..."

    if kubectl get namespace "${NAMESPACE}" &>/dev/null; then
        log_warning "Namespace '${NAMESPACE}' already exists"
    else
        kubectl apply -f "${GITLAB_K8S_DIR}/namespace.yaml"
        log_success "Namespace created"
    fi
}

create_root_password_secret() {
    local password="$1"

    log_info "Creating root password secret..."

    if kubectl get secret gitlab-root-password -n "${NAMESPACE}" &>/dev/null; then
        log_warning "Secret 'gitlab-root-password' already exists, deleting..."
        kubectl delete secret gitlab-root-password -n "${NAMESPACE}"
    fi

    kubectl create secret generic gitlab-root-password \
        -n "${NAMESPACE}" \
        --from-literal=password="${password}"

    log_success "Root password secret created"
}

create_persistent_volumes() {
    log_info "Creating persistent volumes..."

    kubectl apply -f "${GITLAB_K8S_DIR}/persistent-volumes.yaml"

    log_success "Persistent volumes created"

    # Note: PVCs use WaitForFirstConsumer binding mode, so they'll bind when the pod starts
    log_info "Note: PVCs will bind when GitLab pod starts (WaitForFirstConsumer mode)"
    kubectl get pvc -n "${NAMESPACE}"
}

deploy_gitlab() {
    log_info "Deploying GitLab..."

    kubectl apply -f "${GITLAB_K8S_DIR}/deployment.yaml"
    kubectl apply -f "${GITLAB_K8S_DIR}/service.yaml"
    kubectl apply -f "${GITLAB_K8S_DIR}/ingress.yaml"

    log_success "GitLab resources created"
}

wait_for_gitlab() {
    log_info "Waiting for GitLab to be ready..."
    log_warning "This may take 5-10 minutes. GitLab is a heavy application."
    echo ""

    # Wait for deployment to be available
    log_info "Waiting for deployment to be ready..."
    kubectl wait --for=condition=available \
        deployment/gitlab \
        -n "${NAMESPACE}" \
        --timeout="${KUBECTL_WAIT_TIMEOUT}" || {
        log_error "Deployment did not become available in time"
        log_info "Checking pod status..."
        kubectl get pods -n "${NAMESPACE}"
        log_info "Checking pod logs..."
        kubectl logs -n "${NAMESPACE}" -l app=gitlab --tail=50
        exit 1
    }

    log_success "GitLab deployment is available"

    # Wait for the pod to be fully ready
    log_info "Waiting for pod to be ready..."
    kubectl wait --for=condition=ready \
        pod -l app=gitlab \
        -n "${NAMESPACE}" \
        --timeout="${KUBECTL_WAIT_TIMEOUT}" || {
        log_error "Pod did not become ready in time"
        log_info "Checking pod status..."
        kubectl get pods -n "${NAMESPACE}"
        exit 1
    }

    log_success "GitLab pod is ready"

    # Additional wait for GitLab to fully initialize
    log_info "Waiting for GitLab web interface to be responsive..."
    local max_attempts=60
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if curl -s -o /dev/null -w "%{http_code}" "${GITLAB_URL}/users/sign_in" | grep -q "200"; then
            log_success "GitLab is responding"
            break
        fi

        echo -ne "\rAttempt ${attempt}/${max_attempts}... "
        sleep 10
        ((attempt++))
    done

    if [ $attempt -gt $max_attempts ]; then
        log_error "GitLab did not become responsive in time"
        exit 1
    fi

    echo ""
}

test_gitlab_access() {
    log_info "Testing GitLab access..."

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "${GITLAB_URL}/users/sign_in")

    if [ "${http_code}" == "200" ]; then
        log_success "GitLab is accessible at ${GITLAB_URL}"
    else
        log_warning "GitLab returned HTTP ${http_code}"
        log_info "It may still be initializing. Try accessing it in a few minutes."
    fi
}

set_root_password() {
    local password="$1"

    log_info "Setting GitLab root password..."

    # Get the pod name
    local pod_name
    pod_name=$(kubectl get pod -n "${NAMESPACE}" -l app=gitlab -o jsonpath='{.items[0].metadata.name}')

    if [ -z "${pod_name}" ]; then
        log_error "Could not find GitLab pod"
        return 1
    fi

    # Reset the password using gitlab-rake (works for both new and existing installations)
    log_info "Using gitlab-rake to set password..."

    # Use printf to send password twice (password + confirmation) via stdin
    if ! printf "%s\n%s\n" "${password}" "${password}" | \
        kubectl exec -i -n "${NAMESPACE}" "${pod_name}" -- \
        gitlab-rake "gitlab:password:reset[root]" 2>&1 | tee /dev/tty | grep -q "successfully"; then
        log_warning "Could not set password via gitlab-rake"
        log_warning "You may need to set it manually with:"
        log_warning "  kubectl exec -it -n ${NAMESPACE} ${pod_name} -- gitlab-rake \"gitlab:password:reset[root]\""
        return 1
    fi

    log_success "Root password set successfully"
}

validate_setup() {
    log_info "Validating GitLab setup..."

    echo ""
    log_info "Namespace resources:"
    kubectl get all -n "${NAMESPACE}"

    echo ""
    log_info "Persistent volumes:"
    kubectl get pvc -n "${NAMESPACE}"

    echo ""
    log_info "Ingress:"
    kubectl get ingress -n "${NAMESPACE}"

    echo ""
    log_success "Validation complete!"
}

print_summary() {
    local password="$1"

    echo ""
    echo "=============================================="
    log_success "Phase 2: GitLab Deployment Complete"
    echo "=============================================="
    echo ""
    echo "GitLab URL: ${GITLAB_URL}"
    echo "Username:   root"
    echo "Password:   ${password}"
    echo ""
    log_info "Access GitLab at: ${GITLAB_URL}"
    echo ""
    log_warning "Note: If you cannot login, reset the password manually:"
    log_warning "  POD=\$(kubectl get pod -n gitlab -l app=gitlab -o jsonpath='{.items[0].metadata.name}')"
    log_warning "  kubectl exec -it -n gitlab \$POD -- gitlab-rake \"gitlab:password:reset[root]\""
    echo ""
    log_warning "If you cannot access GitLab via the browser:"
    log_warning "  1. Make sure you can ping gitlab.127.0.0.1.nip.io"
    log_warning "  2. Check that ingress is working: kubectl get ingress -n gitlab"
    log_warning "  3. Try port-forward: kubectl port-forward -n gitlab svc/gitlab 8080:80"
    log_warning "     Then access at: http://localhost:8080"
    echo ""
    echo "Next steps:"
    echo "  1. Log in to GitLab at ${GITLAB_URL}"
    echo "  2. Verify you can access the admin area"
    echo "  3. Proceed to Phase 3: ./scripts/03-configure-gitlab.sh"
    echo ""
}

main() {
    log_info "Starting Phase 2: GitLab Deployment"
    echo ""

    verify_context

    local root_password
    root_password=$(generate_root_password)

    create_namespace
    create_root_password_secret "${root_password}"
    create_persistent_volumes
    deploy_gitlab
    wait_for_gitlab
    test_gitlab_access
    set_root_password "${root_password}"
    validate_setup

    print_summary "${root_password}"
}

main "$@"
