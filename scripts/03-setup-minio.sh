#!/bin/bash
set -e

CLUSTER_NAME="atlantis-demo"

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

verify_context

echo "=== Setting up MinIO for Terraform State Backend ==="

# Apply resources in order
echo "Creating MinIO namespace..."
kubectl apply -f kubernetes/minio/namespace.yaml

echo "Creating persistent volume claim..."
kubectl apply -f kubernetes/minio/persistent-volumes.yaml

echo "Deploying MinIO..."
kubectl apply -f kubernetes/minio/deployment.yaml

echo "Creating MinIO service..."
kubectl apply -f kubernetes/minio/service.yaml

echo "Creating ingress resources..."
kubectl apply -f kubernetes/minio/ingress.yaml

echo "Waiting for MinIO deployment to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/minio -n minio

echo "Running MinIO initialization job..."
kubectl delete job minio-init -n minio --ignore-not-found
kubectl apply -f kubernetes/minio/init-job.yaml

echo "Waiting for initialization job to complete..."
kubectl wait --for=condition=complete --timeout=120s job/minio-init -n minio

echo ""
echo "=== MinIO Setup Complete ==="
echo ""
echo "MinIO S3 API available at: http://minio.127.0.0.1.nip.io"
echo "MinIO Console available at: http://minio-console.127.0.0.1.nip.io"
echo ""
echo "Credentials:"
echo "  Access Key: terraform"
echo "  Secret Key: terraform-secret-key-change-me"
echo ""
echo "Bucket: terraform-states (versioning enabled)"
echo ""
echo "To verify the setup:"
echo "  kubectl get pods -n minio"
echo "  kubectl logs -n minio job/minio-init"
echo ""
