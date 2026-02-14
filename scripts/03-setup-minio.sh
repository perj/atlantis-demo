#!/bin/bash
set -e

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
