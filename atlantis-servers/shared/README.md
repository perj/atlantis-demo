# Shared Resources

This Terraform configuration manages shared resources used by all Atlantis servers in the platform.

## Resources Managed

### Kubernetes Resources
- **Namespace**: `atlantis` - Where all Atlantis server deployments will run
- **Secret**: `gitlab-credentials` - Contains GitLab authentication for Atlantis servers

### GitLab Resources
- **User**: `atlantis-bot` - Service account for Atlantis automation
- **Personal Access Token**: API token with `api` scope for GitLab operations

## Authentication

### Terraform Providers

1. **Kubernetes Provider**: Configured with explicit kubeconfig path
   - **Local execution**: Uses `~/.kube/config` with `kind-atlantis-demo` context
   - **Atlantis (in-cluster)**: Platform Atlantis deployment will include init container to create `~/.kube/config` using in-cluster service account (configured in Phase 6)
   - Requires RBAC permissions to create namespaces and secrets

2. **GitLab Provider**: Authenticates using GitLab root token fetched from Kubernetes secret `gitlab-root-token` in `gitlab` namespace

### State Backend

Terraform state is stored in MinIO (S3-compatible backend):
- Bucket: `terraform-states`
- Key: `atlantis-servers/shared/terraform.tfstate`
- Endpoint: `http://minio.127.0.0.1.nip.io`

## Bootstrap vs. Atlantis Management

**Current (Bootstrap)**: This configuration is initially applied manually using `terraform apply` because:
- The `atlantis` namespace doesn't exist yet
- Platform Atlantis isn't deployed yet
- We need the GitLab credentials before Atlantis can operate

**Future Updates**: Once Platform Atlantis is deployed, changes to this configuration will be managed through GitLab PRs and the Atlantis workflow (defined in root `atlantis.yaml`).

## Cluster Safety

**Protection against wrong cluster:**
1. **Terraform validation**: The config checks for the `gitlab` namespace. If it doesn't exist, Terraform will fail before making changes.
2. **Script validation**: The setup script checks that you're using the `kind-atlantis-demo` context and warns if not.

**If running Terraform manually**, verify your context first:
```bash
kubectl config current-context  # Should show: kind-atlantis-demo
kubectl config use-context kind-atlantis-demo  # Switch if needed
kubectl get namespace gitlab    # Verify gitlab namespace exists
```

## Usage

### Initial Setup
```bash
# Run the setup script
./scripts/05-configure-shared-resources.sh

# Or manually:
cd atlantis-servers/shared
terraform init
terraform plan
terraform apply
```

### View Outputs
```bash
cd atlantis-servers/shared

# Show all outputs
terraform output

# Show sensitive token
terraform output -raw atlantis_bot_token
```

### Verify Resources
```bash
# Check namespace
kubectl get namespace atlantis

# Check secret
kubectl get secret gitlab-credentials -n atlantis
kubectl describe secret gitlab-credentials -n atlantis

# View secret data (base64 encoded)
kubectl get secret gitlab-credentials -n atlantis -o yaml
```

## Token Rotation

The GitLab personal access token uses automatic rotation configuration:
- **Token validity**: 730 days (2 years)
- **Rotation window**: 7 days before expiry
- **How it works**: When you run `terraform apply` within 7 days of expiry, Terraform will automatically rotate the token

To manually rotate the token:
1. Run `terraform apply` (will rotate if within rotation window)
2. The Kubernetes secret is automatically updated
3. Restart Atlantis pods to pick up the new credentials:
   ```bash
   kubectl rollout restart deployment -n atlantis
   ```

**Note**: This requires running `terraform apply` periodically (at least every 2 years, ideally more frequently).

## Security Notes

- The `atlantis-bot` user is **not** an admin
- Token has only `api` scope (required for Atlantis to post comments, manage webhooks, etc.)
- Token is stored as a Kubernetes secret in the `atlantis` namespace
- Terraform state contains sensitive data - ensure MinIO access is restricted
- The root GitLab token is only used during Terraform apply, not stored in state
