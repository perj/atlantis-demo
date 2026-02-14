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
KIND_CONFIG="${PROJECT_ROOT}/kind/cluster-config.yaml"
INGRESS_VALUES="${PROJECT_ROOT}/kubernetes/ingress-nginx/values.yaml"

# Configuration
CLUSTER_NAME="atlantis-demo"
KIND_VERSION="v0.25.0"  # Will be updated to latest
KUBECTL_WAIT_TIMEOUT="300s"

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

check_docker() {
    log_info "Checking Docker availability..."
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running or not accessible"
        exit 1
    fi

    log_success "Docker is available"
}

install_kind() {
    log_info "Checking for Kind installation..."

    if command -v kind &> /dev/null; then
        CURRENT_VERSION=$(kind version | grep -oP 'kind v\K[0-9.]+' || echo "unknown")
        log_info "Kind is already installed (version: ${CURRENT_VERSION})"
        read -p "Do you want to reinstall the latest version? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi

    log_info "Installing Kind..."

    # Detect OS and architecture
    OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m)"

    case "${ARCH}" in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        *)
            log_error "Unsupported architecture: ${ARCH}"
            exit 1
            ;;
    esac

    # Get latest Kind version from GitHub
    log_info "Fetching latest Kind version..."
    LATEST_VERSION=$(curl -sL https://api.github.com/repos/kubernetes-sigs/kind/releases/latest | grep '"tag_name"' | cut -d'"' -f4)

    if [ -z "${LATEST_VERSION}" ]; then
        log_warning "Could not fetch latest version, using ${KIND_VERSION}"
        LATEST_VERSION="${KIND_VERSION}"
    else
        log_info "Latest Kind version: ${LATEST_VERSION}"
    fi

    # Download Kind binary
    DOWNLOAD_URL="https://github.com/kubernetes-sigs/kind/releases/download/${LATEST_VERSION}/kind-${OS}-${ARCH}"
    TEMP_KIND="/tmp/kind-${LATEST_VERSION}"

    log_info "Downloading Kind from ${DOWNLOAD_URL}..."
    if ! curl -sL -o "${TEMP_KIND}" "${DOWNLOAD_URL}"; then
        log_error "Failed to download Kind"
        exit 1
    fi

    chmod +x "${TEMP_KIND}"

    # Install to user's local bin or system bin
    if [ -w "/usr/local/bin" ]; then
        INSTALL_PATH="/usr/local/bin/kind"
        mv "${TEMP_KIND}" "${INSTALL_PATH}"
    elif [ -d "${HOME}/.local/bin" ]; then
        INSTALL_PATH="${HOME}/.local/bin/kind"
        mkdir -p "${HOME}/.local/bin"
        mv "${TEMP_KIND}" "${INSTALL_PATH}"

        # Ensure ~/.local/bin is in PATH
        if [[ ":$PATH:" != *":${HOME}/.local/bin:"* ]]; then
            log_warning "~/.local/bin is not in your PATH. Add it to your shell profile:"
            log_warning 'export PATH="$HOME/.local/bin:$PATH"'
        fi
    else
        log_error "Cannot find suitable installation directory. Please install Kind manually."
        rm -f "${TEMP_KIND}"
        exit 1
    fi

    log_success "Kind installed successfully at ${INSTALL_PATH}"
    kind version
}

check_kubectl() {
    log_info "Checking kubectl availability..."
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        log_error "Please install kubectl: https://kubernetes.io/docs/tasks/tools/"
        exit 1
    fi
    log_success "kubectl is available"
}

check_helm() {
    log_info "Checking Helm availability..."
    if ! command -v helm &> /dev/null; then
        log_error "Helm is not installed or not in PATH"
        log_error "Please install Helm: https://helm.sh/docs/intro/install/"
        exit 1
    fi
    log_success "Helm is available"
}

create_cluster() {
    log_info "Checking if cluster '${CLUSTER_NAME}' already exists..."

    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        log_warning "Cluster '${CLUSTER_NAME}' already exists"
        read -p "Do you want to delete and recreate it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deleting existing cluster..."
            kind delete cluster --name "${CLUSTER_NAME}"
        else
            log_info "Using existing cluster"
            kind export kubeconfig --name "${CLUSTER_NAME}"
            return 0
        fi
    fi

    log_info "Creating Kind cluster '${CLUSTER_NAME}'..."
    if ! kind create cluster --config "${KIND_CONFIG}" --wait "${KUBECTL_WAIT_TIMEOUT}"; then
        log_error "Failed to create Kind cluster"
        exit 1
    fi

    log_success "Cluster created successfully"

    # Verify cluster is ready
    log_info "Verifying cluster nodes..."
    kubectl wait --for=condition=Ready nodes --all --timeout="${KUBECTL_WAIT_TIMEOUT}"

    kubectl get nodes
}

install_ingress_nginx() {
    log_info "Installing ingress-nginx controller..."

    # Add ingress-nginx Helm repository
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
    helm repo update

    # Check if already installed
    if helm list -n ingress-nginx 2>/dev/null | grep -q ingress-nginx; then
        log_warning "ingress-nginx is already installed"
        read -p "Do you want to upgrade it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Upgrading ingress-nginx..."
            helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
                --namespace ingress-nginx \
                --values "${INGRESS_VALUES}" \
                --wait \
                --timeout "${KUBECTL_WAIT_TIMEOUT}"
        fi
    else
        # Install ingress-nginx
        kubectl create namespace ingress-nginx 2>/dev/null || true

        helm install ingress-nginx ingress-nginx/ingress-nginx \
            --namespace ingress-nginx \
            --values "${INGRESS_VALUES}" \
            --wait \
            --timeout "${KUBECTL_WAIT_TIMEOUT}"
    fi

    log_success "ingress-nginx controller installed"

    # Wait for ingress controller to be ready
    log_info "Waiting for ingress controller to be ready..."
    kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout="${KUBECTL_WAIT_TIMEOUT}"

    kubectl get pods -n ingress-nginx
}

validate_setup() {
    log_info "Validating setup..."

    echo ""
    log_info "Cluster information:"
    kubectl cluster-info --context "kind-${CLUSTER_NAME}"

    echo ""
    log_info "Nodes:"
    kubectl get nodes

    echo ""
    log_info "Ingress controller:"
    kubectl get pods -n ingress-nginx

    echo ""
    log_info "/etc/hosts entries:"
    grep "# Atlantis Demo" /etc/hosts || log_warning "No entries found in /etc/hosts"

    echo ""
    log_success "Setup validation complete!"
}

print_summary() {
    echo ""
    echo "=============================================="
    log_success "Phase 1: Local Infrastructure Setup Complete"
    echo "=============================================="
    echo ""
    echo "Cluster Name: ${CLUSTER_NAME}"
    echo "Kubeconfig: $(kubectl config current-context)"
    echo ""
    echo "Next steps:"
    echo "  1. Run: kubectl get all --all-namespaces"
    echo "  2. Proceed to Phase 2: ./scripts/02-setup-gitlab.sh"
    echo ""
}

main() {
    log_info "Starting Phase 1: Local Infrastructure Setup"
    echo ""

    check_docker
    install_kind
    check_kubectl
    check_helm
    create_cluster
    install_ingress_nginx
    validate_setup
    print_summary
}

main "$@"
