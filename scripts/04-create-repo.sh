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

# Configuration
CLUSTER_NAME="atlantis-demo"
NAMESPACE="gitlab"
GITLAB_URL="http://gitlab.127.0.0.1.nip.io"
REPO_NAME="atlantis-demo"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
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

get_root_password() {
    log_info "Retrieving GitLab root password..."

    local password
    password=$(kubectl get secret gitlab-root-password -n "${NAMESPACE}" -o jsonpath='{.data.password}' | base64 -d 2>/dev/null)

    if [ -z "${password}" ]; then
        log_error "Could not retrieve root password from secret"
        exit 1
    fi

    log_success "Root password retrieved"
    echo "${password}"
}

create_access_token() {
    log_info "Creating GitLab Personal Access Token..."

    # Check if token secret already exists
    if kubectl get secret gitlab-root-token -n "${NAMESPACE}" &>/dev/null; then
        log_warning "Token secret already exists, retrieving existing token..."
        local existing_token
        existing_token=$(kubectl get secret gitlab-root-token -n "${NAMESPACE}" -o jsonpath='{.data.password}' | base64 -d)

        # Verify the token still works
        local response_code
        response_code=$(curl -s -o /dev/null -w "%{http_code}" \
            --header "PRIVATE-TOKEN: ${existing_token}" \
            "${GITLAB_URL}/api/v4/user")

        if [ "${response_code}" == "200" ]; then
            log_success "Existing token is valid"
            echo "${existing_token}"
            return 0
        else
            log_warning "Existing token is invalid, creating new one..."
            kubectl delete secret gitlab-root-token -n "${NAMESPACE}"
        fi
    fi

    # Get the GitLab pod name
    local pod_name
    pod_name=$(kubectl get pod -n "${NAMESPACE}" -l app=gitlab -o jsonpath='{.items[0].metadata.name}')

    if [ -z "${pod_name}" ]; then
        log_error "Could not find GitLab pod"
        exit 1
    fi

    log_info "Creating token via GitLab Rails console..."

    # Create a personal access token using GitLab Rails console
    # This is more reliable than web scraping
    local token
    token=$(kubectl exec -i -n "${NAMESPACE}" "${pod_name}" -- gitlab-rails runner - <<'RUBY' 2>/dev/null | tail -1
user = User.find_by_username('root')
token = user.personal_access_tokens.create(
  name: 'atlantis-demo-token',
  scopes: [:api, :read_repository, :write_repository],
  expires_at: 365.days.from_now
)
puts token.token if token.persisted?
RUBY
)

    if [ -z "${token}" ] || [ "${token}" == "null" ]; then
        log_error "Could not create access token via Rails console"
        exit 1
    fi

    # Verify the token works (with retry for GitLab API readiness)
    log_info "Verifying token..."
    local max_attempts=10
    local attempt=1
    local response_code

    while [ $attempt -le $max_attempts ]; do
        response_code=$(curl -s -o /dev/null -w "%{http_code}" \
            --header "PRIVATE-TOKEN: ${token}" \
            "${GITLAB_URL}/api/v4/user")

        if [ "${response_code}" == "200" ]; then
            log_success "Token verified successfully"
            break
        fi

        if [ $attempt -eq $max_attempts ]; then
            log_error "Token validation failed after ${max_attempts} attempts (HTTP ${response_code})"
            exit 1
        fi

        log_info "API not ready (HTTP ${response_code}), retrying... (${attempt}/${max_attempts})"
        sleep 3
        ((attempt++))
    done

    # Store token in Kubernetes secret
    kubectl create secret generic gitlab-root-token \
        -n "${NAMESPACE}" \
        --from-literal=password="${token}" >&2

    log_success "Personal Access Token created and stored"
    echo "${token}"
}

create_repository() {
    local token="$1"

    log_info "Creating GitLab repository '${REPO_NAME}'..."

    # Check if repository already exists
    local response_code
    response_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --header "PRIVATE-TOKEN: ${token}" \
        "${GITLAB_URL}/api/v4/projects/root%2F${REPO_NAME}")

    if [ "${response_code}" == "200" ]; then
        log_warning "Repository '${REPO_NAME}' already exists"
        return 0
    fi

    # Create repository
    local response
    response=$(curl -s --request POST "${GITLAB_URL}/api/v4/projects" \
        --header "PRIVATE-TOKEN: ${token}" \
        --header "Content-Type: application/json" \
        --data "{
            \"name\": \"${REPO_NAME}\",
            \"visibility\": \"internal\",
            \"initialize_with_readme\": false
        }")

    # Check if creation was successful
    if echo "${response}" | grep -q '"id"'; then
        log_success "Repository created successfully"
    else
        log_error "Failed to create repository"
        log_error "Response: ${response}"
        exit 1
    fi
}

push_repository() {
    local token="$1"

    log_info "Configuring git remote..."

    cd "${PROJECT_ROOT}"

    # Remove existing demo remote if it exists
    if git remote get-url demo &>/dev/null; then
        log_warning "Removing existing 'demo' remote"
        git remote remove demo
    fi

    git remote add demo "http://root:${token}@gitlab.127.0.0.1.nip.io/root/${REPO_NAME}.git"

    log_success "Git remote configured"

    # Get current branch
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)

    log_info "Pushing to GitLab (branch: ${current_branch})..."

    if git push demo "${current_branch}"; then
        log_success "Repository pushed successfully"
    else
        log_error "Failed to push repository"
        exit 1
    fi
}

validate_setup() {
    local token="$1"

    log_info "Validating repository setup..."

    # Get repository info
    local response
    response=$(curl -s \
        --header "PRIVATE-TOKEN: ${token}" \
        "${GITLAB_URL}/api/v4/projects/root%2F${REPO_NAME}")

    if echo "${response}" | grep -q '"id"'; then
        local web_url
        web_url=$(echo "${response}" | grep -oP '"web_url":"\K[^"]+')
        log_success "Repository is accessible at: ${web_url}"
    else
        log_warning "Could not validate repository"
        return 1
    fi

    # List branches
    log_info "Branches in repository:"
    curl -s \
        --header "PRIVATE-TOKEN: ${token}" \
        "${GITLAB_URL}/api/v4/projects/root%2F${REPO_NAME}/repository/branches" | \
        grep -oP '"name":"\K[^"]+' || log_warning "Could not list branches"
}

print_summary() {
    local token="$1"

    echo ""
    echo "=============================================="
    log_success "Phase 4: Repository Creation Complete"
    echo "=============================================="
    echo ""
    echo "Repository URL: ${GITLAB_URL}/root/${REPO_NAME}"
    echo "Repository API: ${GITLAB_URL}/api/v4/projects/root%2F${REPO_NAME}"
    echo ""
    log_info "Access Token stored in Kubernetes:"
    echo "  kubectl get secret gitlab-root-token -n ${NAMESPACE} -o jsonpath='{.data.password}' | base64 -d"
    echo ""
    log_success "Repository is ready for use!"
    echo ""
    echo "Next steps:"
    echo "  1. Verify repository in GitLab UI: ${GITLAB_URL}/root/${REPO_NAME}"
    echo "  2. Check that all files are present"
    echo "  3. Proceed to Phase 5: Shared Terraform Resources"
    echo ""
}

main() {
    log_info "Starting Phase 4: GitLab Repository Creation"
    echo ""

    verify_context

    local access_token
    access_token=$(create_access_token)

    create_repository "${access_token}"
    push_repository "${access_token}"
    validate_setup "${access_token}"

    print_summary "${access_token}"
}

main "$@"
